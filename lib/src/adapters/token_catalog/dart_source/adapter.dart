// ALEA — DartSourceTokenCatalogAdapter.
//
// Reads design tokens from Dart source files via the analyzer AST. Suitable
// for projects whose design system is declared as classes with
// `static const Color` (or similar) fields — a very common Flutter pattern.
//
// Recognized syntactic shapes for color tokens:
//
//   class AppColors {
//     static const Color primary = Color(0xFF0066CC);
//     static const Color overlay = Color.fromARGB(0x80, 0, 0, 0);
//     static const Color alias   = primary;     // <-- skipped (aliases are
//                                                    not resolved here)
//   }
//
// Each accepted field yields a [ColorToken] whose `qualifiedName` is the
// `<ClassName>.<fieldName>` form expected by consumer code. Aliases and
// non-literal expressions are not interpreted — the adapter ignores them
// and emits an entry in the returned list ONLY when the value is fully
// resolvable from the AST.
//
// Typography and spacing extraction are intentionally limited in Phase 2.
// The contract methods are implemented but return empty lists when the
// corresponding `*_class` convention key is not provided. Phase 4 will
// extend them.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../../../contracts/design_token_catalog.dart';

/// Default class names recognized when no `conventions` knobs are passed.
const _defaultColorClass = 'StyleColors';

class DartSourceTokenCatalogAdapter implements DesignTokenCatalog {
  /// Absolute path of the directory (or single .dart file) to scan.
  final String absoluteSourcePath;

  /// Consumer-declared name of the class that holds color tokens. Defaults
  /// to "StyleColors" as a common Flutter convention. Other projects
  /// pass their own (e.g. "Palette", "AppColors").
  final String colorClass;

  /// Optional class names for typography/spacing/custom families. When null
  /// the corresponding catalog method returns an empty list (the resolver
  /// must tolerate this — see contract).
  final String? typographyClass;
  final String? spacingClass;
  final String? customClass;

  DartSourceTokenCatalogAdapter({
    required this.absoluteSourcePath,
    this.colorClass = _defaultColorClass,
    this.typographyClass,
    this.spacingClass,
    this.customClass,
  });

  /// Build from a `theme.token_catalog` config block. `absoluteSourcePath`
  /// must be resolved by the caller (the factory does this against the
  /// project root).
  factory DartSourceTokenCatalogAdapter.fromConventions({
    required String absoluteSourcePath,
    required Map<String, Object?> conventions,
  }) {
    return DartSourceTokenCatalogAdapter(
      absoluteSourcePath: absoluteSourcePath,
      colorClass:
          _stringConvention(conventions, 'color_class') ?? _defaultColorClass,
      typographyClass: _stringConvention(conventions, 'typography_class'),
      spacingClass: _stringConvention(conventions, 'spacing_class'),
      customClass: _stringConvention(conventions, 'custom_class'),
    );
  }

  @override
  String get sourceId => 'dart_source';

  @override
  Future<List<ColorToken>> colors() async {
    final files = _collectDartFiles();
    final out = <ColorToken>[];
    for (final file in files) {
      final result = parseFile(
        path: file,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      for (final decl in result.unit.declarations) {
        if (decl is! ClassDeclaration) continue;
        if (decl.namePart.typeName.lexeme != colorClass) continue;
        out.addAll(_collectColorsFromClass(decl));
      }
    }
    return List.unmodifiable(out);
  }

  @override
  Future<List<TypographyToken>> typography() async {
    if (typographyClass == null) return const [];
    // Phase 4 will implement TextStyle / FontWeight extraction. Returning
    // empty is contractually valid (resolvers tolerate it).
    return const [];
  }

  @override
  Future<List<SpacingToken>> spacing() async {
    if (spacingClass == null) return const [];
    return const [];
  }

  @override
  Future<List<NamedToken>> custom(String family) async {
    if (customClass == null) return const [];
    return const [];
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  List<String> _collectDartFiles() {
    final entity = FileSystemEntity.typeSync(absoluteSourcePath);
    if (entity == FileSystemEntityType.notFound) {
      throw DesignTokenCatalogException(
        'Source path does not exist',
        source: absoluteSourcePath,
      );
    }
    if (entity == FileSystemEntityType.file) {
      return [p.normalize(absoluteSourcePath)];
    }
    final dir = Directory(absoluteSourcePath);
    return dir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => p.normalize(f.absolute.path))
        .toList(growable: false);
  }

  Iterable<ColorToken> _collectColorsFromClass(ClassDeclaration decl) sync* {
    for (final member in decl.body.members) {
      if (member is! FieldDeclaration) continue;
      if (!member.isStatic) continue;
      final type = member.fields.type;
      if (type == null) continue;
      // Lexical Color match — robust against analyzer API drift. Accepts
      // both `Color` and `Color?`.
      final typeSource = type.toSource();
      if (typeSource != 'Color' && typeSource != 'Color?') continue;

      for (final variable in member.fields.variables) {
        final init = variable.initializer;
        if (init == null) continue;
        final argb = _extractArgb(init);
        if (argb == null) continue;
        yield ColorToken(
          qualifiedName: '$colorClass.${variable.name.lexeme}',
          argb: argb,
        );
      }
    }
  }

  /// Extract a 32-bit ARGB from a Color constructor expression.
  ///
  /// The Dart parser represents `Color(0xFF…)` as a [MethodInvocation] (the
  /// parser has no resolution context to know `Color` is a class). The same
  /// expression prefixed with `const` becomes [InstanceCreationExpression].
  /// We handle both. Returns null for aliases, computed expressions, or
  /// unrecognized constructors.
  int? _extractArgb(Expression expr) {
    if (expr is InstanceCreationExpression) {
      return _argbFromInstance(expr);
    }
    if (expr is MethodInvocation) {
      return _argbFromMethodInvocation(expr);
    }
    return null;
  }

  int? _argbFromInstance(InstanceCreationExpression expr) {
    final typeName = expr.constructorName.type.name.lexeme;
    if (typeName != 'Color') return null;
    final namedCtor = expr.constructorName.name?.name;
    return _decodeColorArgs(namedCtor, _argExpressions(expr.argumentList));
  }

  int? _argbFromMethodInvocation(MethodInvocation expr) {
    final target = expr.target;
    final methodName = expr.methodName.name;
    if (target == null) {
      // Color(0xFF…)
      if (methodName != 'Color') return null;
      return _decodeColorArgs(null, _argExpressions(expr.argumentList));
    }
    if (target is SimpleIdentifier && target.name == 'Color') {
      // Color.fromARGB(a, r, g, b) etc.
      return _decodeColorArgs(methodName, _argExpressions(expr.argumentList));
    }
    return null;
  }

  List<Expression> _argExpressions(ArgumentList list) => list.arguments
      .map((a) => a is NamedExpression ? a.expression : a)
      .toList(growable: false);

  int? _decodeColorArgs(String? namedCtor, List<Expression> args) {
    if (namedCtor == null && args.length == 1) {
      final lit = args.first;
      if (lit is IntegerLiteral) return lit.value;
      return null;
    }
    if (namedCtor == 'fromARGB' && args.length == 4) {
      final ints = <int>[];
      for (final a in args) {
        if (a is! IntegerLiteral) return null;
        final v = a.value;
        if (v == null || v < 0 || v > 0xFF) return null;
        ints.add(v);
      }
      return (ints[0] << 24) | (ints[1] << 16) | (ints[2] << 8) | ints[3];
    }
    if (namedCtor == 'fromRGBO' && args.length == 4) {
      // Color.fromRGBO(r, g, b, opacity) — opacity is a double 0..1.
      if (args[0] is! IntegerLiteral ||
          args[1] is! IntegerLiteral ||
          args[2] is! IntegerLiteral) {
        return null;
      }
      final r = (args[0] as IntegerLiteral).value;
      final g = (args[1] as IntegerLiteral).value;
      final b = (args[2] as IntegerLiteral).value;
      double? opacity;
      final op = args[3];
      if (op is DoubleLiteral) {
        opacity = op.value;
      } else if (op is IntegerLiteral) {
        opacity = op.value?.toDouble();
      }
      if (r == null || g == null || b == null || opacity == null) {
        return null;
      }
      if (opacity < 0 || opacity > 1) return null;
      final a = (opacity * 255).round() & 0xFF;
      return (a << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
    }
    return null;
  }

  static String? _stringConvention(
    Map<String, Object?> conventions,
    String key,
  ) {
    final v = conventions[key];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }
}
