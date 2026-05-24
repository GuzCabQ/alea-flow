// ALEA — WidgetInventoryBuilder.
//
// Scans a Dart codebase for reusable widget classes and produces a
// [WidgetInventory]. AST-based (uses `package:analyzer`) — no regex, no
// hand-written tokenizer.
//
// Recognition heuristic (a class is "Widget-like" when):
//   1. Its name matches one of the configured suffixes
//      (`*Component`, `*Widget`, `*Button`, `*Card`, …), OR
//   2. It extends one of the configured base classes
//      (`StatelessWidget`, `StatefulWidget`, `GetView<...>`, ...).
//
// Per matched class, the builder extracts:
//   - `className`: the AST class name.
//   - `category`: derived from the matched suffix, lowercased
//     (`ButtonSaveComponent` → `button`).
//   - `tokensUsed`: every `<TokenClass>.<member>` reference found in the
//     class body, where `<TokenClass>` is one of the configured token
//     classes (default `StyleColors`, `StyleFonts`, `StyleSize`).
//   - `constructorSignature`: the primary constructor rendered as source.
//   - `md5Hash`: hash of the file content as read from disk.

import 'dart:async';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../contracts/run_journal.dart';
import '../contracts/widget_inventory.dart';
import 'in_memory_widget_inventory.dart';

/// Default class-name suffixes that mark a Dart class as "widget-like".
const defaultWidgetSuffixes = <String, String>{
  'Component': 'component',
  'Widget': 'widget',
  'Button': 'button',
  'Card': 'card',
  'Input': 'input',
  'Field': 'field',
  'Form': 'form',
  'Screen': 'screen',
  'Page': 'page',
  'View': 'view',
  'Section': 'section',
  'Dialog': 'dialog',
  'Sheet': 'sheet',
  'List': 'list',
  'Item': 'item',
};

/// Default base classes that mark a Dart class as a Flutter widget.
const defaultWidgetBases = <String>{
  'StatelessWidget',
  'StatefulWidget',
  'ConsumerWidget',
  'HookWidget',
  'HookConsumerWidget',
  'GetView',
  'GetWidget',
  'GetResponsiveView',
};

/// Default token classes whose static members count as design-token usage.
const defaultTokenClasses = <String>{'StyleColors', 'StyleFonts', 'StyleSize'};

class WidgetInventoryBuilder {
  /// Absolute paths (files or directories) to scan. Directories are walked
  /// recursively for `.dart` files; symlinks are not followed.
  final List<String> scanPaths;

  /// Suffix → category mapping. A class whose name ends with the suffix is
  /// recognized as widget-like and tagged with the matching category.
  final Map<String, String> widgetSuffixes;

  /// Base classes (by simple name) that mark a class as widget-like even
  /// when its name does not match any suffix.
  final Set<String> widgetBases;

  /// Token classes whose `<class>.<member>` references are recorded under
  /// [WidgetEntry.tokensUsed].
  final Set<String> tokenClasses;

  /// Root used to convert absolute paths in [WidgetEntry.filePath] to
  /// project-relative form. Null disables conversion.
  final String? projectRoot;

  WidgetInventoryBuilder({
    required this.scanPaths,
    this.widgetSuffixes = defaultWidgetSuffixes,
    this.widgetBases = defaultWidgetBases,
    this.tokenClasses = defaultTokenClasses,
    this.projectRoot,
  });

  /// Walk [scanPaths], discover widget-like classes, and assemble an
  /// in-memory inventory. Emits journal events when [journal] is non-null.
  Future<WidgetInventory> build({RunJournal? journal}) async {
    await journal?.record(
      JournalEvent(
        source: 'inventory:widget_inventory_builder',
        kind: JournalEventKind.started,
        payload: {'scan_paths': scanPaths},
      ),
    );

    final files = _collectDartFiles();
    final entries = <WidgetEntry>[];
    for (final file in files) {
      try {
        entries.addAll(await _scanFile(file));
      } on FileSystemException {
        // Unreadable file — skip with a journal warning instead of aborting.
        await journal?.record(
          JournalEvent(
            source: 'inventory:widget_inventory_builder',
            kind: JournalEventKind.warning,
            payload: {'file': file, 'reason': 'unreadable'},
          ),
        );
      }
    }

    // Deterministic ordering: by filePath then className.
    entries.sort((a, b) {
      final byPath = a.filePath.compareTo(b.filePath);
      if (byPath != 0) return byPath;
      return a.className.compareTo(b.className);
    });

    await journal?.record(
      JournalEvent(
        source: 'inventory:widget_inventory_builder',
        kind: JournalEventKind.completed,
        payload: {
          'files_scanned': files.length,
          'widgets_found': entries.length,
        },
      ),
    );

    return InMemoryWidgetInventory(entries: entries, sourceId: 'dart_source');
  }

  /// Serialize [inventory] as Style-Dictionary-style JSON at
  /// `<runDirectory>/widget_inventory.json` (caller provides the path).
  Future<void> emitJsonTo(
    String absolutePath,
    WidgetInventory inventory,
  ) async {
    final entries = await inventory.entries();
    final json = <String, Object?>{
      'version': '1.0.0',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'source': inventory.sourceId,
      'entries': entries.map((e) => e.toJson()).toList(),
    };
    final file = File(absolutePath);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    await file.writeAsString(_prettyJson(json));
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  List<String> _collectDartFiles() {
    final out = <String>[];
    for (final raw in scanPaths) {
      final entity = FileSystemEntity.typeSync(raw);
      if (entity == FileSystemEntityType.notFound) continue;
      if (entity == FileSystemEntityType.file) {
        if (raw.endsWith('.dart')) out.add(p.normalize(raw));
        continue;
      }
      final dir = Directory(raw);
      for (final e
          in dir
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()) {
        if (e.path.endsWith('.dart')) out.add(p.normalize(e.absolute.path));
      }
    }
    return out;
  }

  Future<List<WidgetEntry>> _scanFile(String absolutePath) async {
    final content = await File(absolutePath).readAsString();
    final md5Hash = md5.convert(content.codeUnits).toString();

    final parsed = parseFile(
      path: absolutePath,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );

    final entries = <WidgetEntry>[];
    for (final decl in parsed.unit.declarations) {
      if (decl is! ClassDeclaration) continue;
      final className = decl.namePart.typeName.lexeme;
      if (className.startsWith('_')) continue;

      final category = _categoryOf(className, decl);
      if (category == null) continue;

      final tokens = _tokensUsedIn(decl);
      final ctor = _renderPrimaryConstructor(decl);

      entries.add(
        WidgetEntry(
          className: className,
          filePath: _projectRelative(absolutePath),
          category: category,
          tokensUsed: tokens,
          constructorSignature: ctor,
          md5Hash: md5Hash,
          meta: {
            if (decl.extendsClause != null)
              'extends': decl.extendsClause!.superclass.toSource(),
          },
        ),
      );
    }
    return entries;
  }

  /// Return the category if [decl] is widget-like by name or by base class,
  /// or null otherwise.
  ///
  /// Algorithm:
  ///   1. Split [className] into PascalCase tokens (`ButtonSaveComponent` →
  ///      `['Button', 'Save', 'Component']`).
  ///   2. The RIGHTMOST token that maps to a SPECIFIC category in
  ///      [widgetSuffixes] (i.e. not `Component` / `Widget`) wins. This
  ///      handles both `LoginButton` (suffix) and `ButtonSaveComponent`
  ///      (prefix) — in both, the only specific token is `Button`.
  ///   3. Fall back to the rightmost GENERIC token (`Component`, `Widget`).
  ///   4. Fall back to the extends clause when none of the tokens match.
  String? _categoryOf(String className, ClassDeclaration decl) {
    const generics = {'Component', 'Widget'};
    final tokens = _pascalCaseSplit(className);

    String? specificKey;
    String? genericKey;
    for (final t in tokens) {
      if (!widgetSuffixes.containsKey(t)) continue;
      if (generics.contains(t)) {
        genericKey = t;
      } else {
        specificKey = t;
      }
    }
    if (specificKey != null) return widgetSuffixes[specificKey];
    if (genericKey != null) return widgetSuffixes[genericKey];

    final ext = decl.extendsClause?.superclass;
    if (ext != null) {
      final baseName = ext.name.lexeme;
      if (widgetBases.contains(baseName)) {
        return baseName.toLowerCase().replaceAll('widget', '').isEmpty
            ? 'widget'
            : baseName.toLowerCase().replaceAll('widget', '');
      }
    }
    return null;
  }

  /// Split a PascalCase identifier into its constituent tokens. Numbers stay
  /// attached to the preceding token (`Section2` → `['Section2']`); acronyms
  /// are not split (`SectionURLForm` → `['Section', 'URLForm']` — close
  /// enough for category detection).
  static List<String> _pascalCaseSplit(String s) {
    final out = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      final isUpper = c >= 0x41 && c <= 0x5A;
      if (isUpper && buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
      buf.writeCharCode(c);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  List<String> _tokensUsedIn(ClassDeclaration decl) {
    final visitor = _TokenReferenceCollector(tokenClasses);
    decl.accept(visitor);
    final sorted = visitor.references.toList()..sort();
    return List.unmodifiable(sorted);
  }

  String? _renderPrimaryConstructor(ClassDeclaration decl) {
    ConstructorDeclaration? primary;
    for (final member in decl.body.members) {
      if (member is! ConstructorDeclaration) continue;
      // First public constructor wins as "primary". Subclasses with multiple
      // public constructors will show only the first — good enough for the
      // inventory.
      final ctorName = member.name?.lexeme;
      if (ctorName != null && ctorName.startsWith('_')) continue;
      primary ??= member;
    }
    if (primary == null) return null;
    // Render as source. AST.toSource preserves formatting reasonably well.
    return primary.toSource();
  }

  String _projectRelative(String absolutePath) {
    if (projectRoot == null) return absolutePath;
    try {
      return p.relative(absolutePath, from: projectRoot).replaceAll(r'\', '/');
    } catch (_) {
      return absolutePath;
    }
  }

  String _prettyJson(Map<String, Object?> map) {
    // Simple JSON pretty-printer to avoid pulling json_encoder configuration.
    // Two-space indent matches the project convention.
    final buf = StringBuffer();
    _writeJson(map, buf, 0);
    buf.writeln();
    return buf.toString();
  }

  void _writeJson(Object? value, StringBuffer buf, int indent) {
    if (value == null) {
      buf.write('null');
      return;
    }
    if (value is String) {
      buf.write('"');
      buf.write(value.replaceAll(r'\', r'\\').replaceAll('"', r'\"'));
      buf.write('"');
      return;
    }
    if (value is num || value is bool) {
      buf.write(value);
      return;
    }
    if (value is List) {
      if (value.isEmpty) {
        buf.write('[]');
        return;
      }
      buf.writeln('[');
      for (var i = 0; i < value.length; i++) {
        buf.write('  ' * (indent + 1));
        _writeJson(value[i], buf, indent + 1);
        if (i < value.length - 1) buf.write(',');
        buf.writeln();
      }
      buf.write('  ' * indent);
      buf.write(']');
      return;
    }
    if (value is Map<String, Object?>) {
      if (value.isEmpty) {
        buf.write('{}');
        return;
      }
      buf.writeln('{');
      final keys = value.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        buf.write('  ' * (indent + 1));
        buf.write('"');
        buf.write(keys[i]);
        buf.write('": ');
        _writeJson(value[keys[i]], buf, indent + 1);
        if (i < keys.length - 1) buf.write(',');
        buf.writeln();
      }
      buf.write('  ' * indent);
      buf.write('}');
      return;
    }
    buf.write('"$value"');
  }
}

/// Collects every `<TokenClass>.<member>` reference inside the visited
/// subtree. Detects both PrefixedIdentifier and PropertyAccess shapes.
class _TokenReferenceCollector extends RecursiveAstVisitor<void> {
  _TokenReferenceCollector(this.tokenClasses);
  final Set<String> tokenClasses;
  final Set<String> references = {};

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final prefix = node.prefix.name;
    if (tokenClasses.contains(prefix)) {
      references.add('$prefix.${node.identifier.name}');
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    final target = node.target;
    if (target is SimpleIdentifier && tokenClasses.contains(target.name)) {
      references.add('${target.name}.${node.propertyName.name}');
    }
    super.visitPropertyAccess(node);
  }
}
