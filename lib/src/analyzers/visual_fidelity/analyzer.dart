// ALEA — Visual Fidelity Analyzer.
//
// Verifies generated Dart code against the rules in
// `adapters/code_gen/_common/flutter-defaults.md` and (when NDS is present in
// the run directory) against the design spec.
//
// Source: ported from flutter-ui/SKILL.md Agent 5 critical checks. Each rule
// here corresponds to one of the "critical element checks" from that document.
//
// AST note: the analyzer uses `getParsedUnit` (syntactic only — fixture files
// don't have resolvable Flutter imports). In syntactic AST, expressions like
// `Text('foo')`, `Image.asset(...)`, `SvgPicture.asset(...)`, `Lottie.asset(...)`
// can be either `InstanceCreationExpression` or `MethodInvocation` depending on
// context and parser heuristics. Every rule visitor handles both shapes via a
// shared call-extraction helper.
//
// Rule severity choices:
//   - missing_image_fit:          critical (layout unpredictable, but not a runtime crash)
//   - emoji_as_icon:              critical when NDS source=figma, major otherwise
//   - button_without_content:     blocker (broken UX)
//   - asset_path_broken:          critical (runtime crash when path doesn't exist)
//   - color_not_in_catalog:       blocker — NDS color the consumer's design system does not declare
//   - color_ambiguous:            critical — closest token is within tolerance, but multiple candidates tie
//   - typography_not_in_catalog:  blocker — NDS (size, weight) the consumer has not declared
//   - typography_ambiguous:       critical — closest type token clears noMatch but not match
//   - ignored_widget_hint:        blocker — STUB until code-gen emits NDS annotations
//   - gradient_degraded:          blocker — STUB until code-gen emits NDS annotations
//
// The catalog-driven rules (color_*, typography_*) run only when both an NDS
// document is present in `runDirectory` AND the caller injected a
// `DesignTokenCatalog` into `AnalyzerContext.tokenCatalog`. Otherwise the
// analyzer silently degrades to the AST-only rules.

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../contracts/analyzer.dart';
import '../../contracts/design_token_catalog.dart';
import '../../contracts/run_journal.dart';
import '../../contracts/token_resolver.dart';
import '../../resolvers/palette/resolver.dart';
import '../../resolvers/type_scale/resolver.dart';

class VisualFidelityAnalyzer extends Analyzer {
  @override
  String get name => 'visual_fidelity';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final issues = <AnalysisIssue>[];
    final nds = await _loadNds(ctx.runDirectory);

    // ── AST-only rules ──────────────────────────────────────────────────────
    if (ctx.filePaths.isNotEmpty) {
      final paths = ctx.filePaths.map(p.normalize).toList();
      final collection = AnalysisContextCollection(includedPaths: paths);

      for (final filePath in paths) {
        final context = collection.contextFor(filePath);
        final parseResult = context.currentSession.getParsedUnit(filePath);
        if (parseResult is! ParsedUnitResult) continue;

        final relativePath = _projectRelative(filePath, ctx.projectRoot);
        final visitors = <_RuleVisitor>[
          _MissingImageFitVisitor(relativePath, parseResult.lineInfo),
          _EmojiAsIconVisitor(
            relativePath,
            parseResult.lineInfo,
            ndsSourceAdapter: nds?.adapter,
          ),
          _ButtonWithoutContentVisitor(relativePath, parseResult.lineInfo),
          _AssetPathBrokenVisitor(
            relativePath,
            parseResult.lineInfo,
            projectRoot: ctx.projectRoot,
            sourceContent: parseResult.content,
          ),
        ];
        for (final v in visitors) {
          parseResult.unit.accept(v);
        }
        for (final v in visitors) {
          issues.addAll(v.issues);
        }
      }
    }

    // ── Catalog-driven rules ────────────────────────────────────────────────
    final catalog = ctx.tokenCatalog;
    if (nds != null && catalog != null) {
      final opts = ctx.config.analyzers.optionsFor(name);
      issues.addAll(
        await _runCatalogChecks(
          nds: nds,
          catalog: catalog,
          journal: ctx.journal,
          options: opts,
        ),
      );
    }

    return issues;
  }

  /// Load the NDS document from the run directory, if any. Returns null when
  /// no NDS file exists or when YAML parsing fails (the malformed-NDS issue
  /// is surfaced by the design-source adapter's own validation).
  Future<_NdsDocument?> _loadNds(String? runDirectory) async {
    if (runDirectory == null) return null;
    final dir = Directory(runDirectory);
    if (!await dir.exists()) return null;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final ndsFile = File(p.join(entity.path, 'nds.yaml'));
      if (!await ndsFile.exists()) continue;
      try {
        final content = await ndsFile.readAsString();
        final yaml = loadYaml(content);
        if (yaml is! YamlMap) continue;
        final doc = yaml['document'];
        if (doc is! YamlMap) continue;
        final source = doc['source'];
        final adapter = source is YamlMap ? source['adapter'] : null;
        final elementsRaw = doc['elements'];
        final elements = <Map<String, Object?>>[];
        if (elementsRaw is YamlList) {
          for (final e in elementsRaw) {
            if (e is YamlMap) {
              elements.add(_yamlMapToDart(e));
            }
          }
        }
        return _NdsDocument(
          adapter: adapter is String ? adapter : null,
          elements: List.unmodifiable(elements),
          ndsPath: p.relative(ndsFile.path, from: runDirectory),
        );
      } catch (_) {
        // Skip malformed NDS — handled elsewhere.
        continue;
      }
    }
    return null;
  }

  Future<List<AnalysisIssue>> _runCatalogChecks({
    required _NdsDocument nds,
    required DesignTokenCatalog catalog,
    required RunJournal? journal,
    required Map<String, Object?> options,
  }) async {
    final issues = <AnalysisIssue>[];
    final checkColors = (options['check_colors'] as bool?) ?? true;
    final checkTypography = (options['check_typography'] as bool?) ?? true;
    final matchThreshold =
        (options['match_threshold'] as num?)?.toDouble() ?? 0.85;
    final noMatchThreshold =
        (options['no_match_threshold'] as num?)?.toDouble() ?? 0.40;

    final hints = ResolverHints(
      matchThreshold: matchThreshold,
      noMatchThreshold: noMatchThreshold,
    );

    final paletteResolver = checkColors ? PaletteResolver(catalog) : null;
    final typeScaleResolver = checkTypography
        ? TypeScaleResolver(catalog)
        : null;

    for (final element in nds.elements) {
      final id = element['id']?.toString() ?? '<unknown>';

      if (paletteResolver != null) {
        for (final loc in const [
          'background.value',
          'border.color',
          'style.color',
        ]) {
          final hex = _readNested(element, loc);
          if (hex is! String) continue;
          final query = ColorQuery.fromHex(hex);
          if (query == null) continue;
          final result = await paletteResolver.resolve(query, hints);
          await journal?.record(
            JournalEvent(
              source: 'analyzer:$name',
              kind: JournalEventKind.check,
              payload: {
                'element_id': id,
                'field': loc,
                'query_hex': hex,
                ...result.toJson(),
              },
            ),
          );
          final issue = _colorIssue(
            ndsPath: nds.ndsPath,
            elementId: id,
            field: loc,
            queryHex: hex,
            result: result,
          );
          if (issue != null) issues.add(issue);
        }
      }

      if (typeScaleResolver != null && element['type']?.toString() == 'text') {
        final style = element['style'];
        if (style is Map<String, Object?>) {
          final size = (style['size'] as num?)?.toDouble();
          final weight = _ndsWeightToNumeric(style['weight']?.toString());
          if (size != null && weight != null) {
            final query = TypographyQuery(fontSize: size, fontWeight: weight);
            final result = await typeScaleResolver.resolve(query, hints);
            await journal?.record(
              JournalEvent(
                source: 'analyzer:$name',
                kind: JournalEventKind.check,
                payload: {
                  'element_id': id,
                  'query_size': size,
                  'query_weight': weight,
                  ...result.toJson(),
                },
              ),
            );
            final issue = _typographyIssue(
              ndsPath: nds.ndsPath,
              elementId: id,
              query: query,
              result: result,
            );
            if (issue != null) issues.add(issue);
          }
        }
      }
    }

    return issues;
  }

  AnalysisIssue? _colorIssue({
    required String ndsPath,
    required String elementId,
    required String field,
    required String queryHex,
    required ResolutionResult<ColorToken> result,
  }) {
    switch (result.verdict) {
      case ResolutionVerdict.match:
        return null;
      case ResolutionVerdict.ambiguous:
        return AnalysisIssue(
          file: ndsPath,
          rule:
              'Visual fidelity: NDS color $queryHex at element "$elementId.$field" '
              'is ambiguous between catalog candidates',
          ruleId: 'visual_fidelity/color_ambiguous',
          message: _ambiguousColorMessage(elementId, field, queryHex, result),
          suggestedFix:
              'Pick one of: ${_topNames(result.candidates)}. If none is correct, '
              'add a new token to the design system.',
          severity: Severity.critical,
        );
      case ResolutionVerdict.noMatch:
        final closest = result.candidates.isNotEmpty
            ? result.candidates.first
            : null;
        return AnalysisIssue(
          file: ndsPath,
          rule:
              'Visual fidelity: NDS color $queryHex at element "$elementId.$field" '
              'is not in the design-token catalog',
          ruleId: 'visual_fidelity/color_not_in_catalog',
          message: closest == null
              ? 'No token comes within tolerance of $queryHex (catalog has '
                    '${result.candidates.length} candidates).'
              : 'Closest token: ${closest.token.qualifiedName} '
                    '(${closest.rationale ?? 'score=${closest.score.toStringAsFixed(2)}'}). '
                    'The design uses a color the consumer has not declared.',
          suggestedFix: closest == null
              ? 'Add a new token to the design system, or change the design '
                    'to use an existing palette entry.'
              : 'Either change the design to use ${closest.token.qualifiedName}, '
                    'or add $queryHex as a new token in the consumer\'s palette.',
          severity: Severity.blocker,
        );
    }
  }

  AnalysisIssue? _typographyIssue({
    required String ndsPath,
    required String elementId,
    required TypographyQuery query,
    required ResolutionResult<TypographyToken> result,
  }) {
    switch (result.verdict) {
      case ResolutionVerdict.match:
        return null;
      case ResolutionVerdict.ambiguous:
        return AnalysisIssue(
          file: ndsPath,
          rule:
              'Visual fidelity: typography (size=${query.fontSize}, '
              'weight=${query.fontWeight}) at "$elementId" is ambiguous',
          ruleId: 'visual_fidelity/typography_ambiguous',
          message:
              'Closest candidates: ${_topNames(result.candidates)}. The catalog '
              'has multiple tokens within tolerance.',
          suggestedFix:
              'Pick one of: ${_topNames(result.candidates)}. If the design '
              'requires a new step, add a TypographyToken.',
          severity: Severity.critical,
        );
      case ResolutionVerdict.noMatch:
        final closest = result.candidates.isNotEmpty
            ? result.candidates.first
            : null;
        return AnalysisIssue(
          file: ndsPath,
          rule:
              'Visual fidelity: typography (size=${query.fontSize}, '
              'weight=${query.fontWeight}) at "$elementId" is not in the catalog',
          ruleId: 'visual_fidelity/typography_not_in_catalog',
          message: closest == null
              ? 'No typography token matches size=${query.fontSize} '
                    'weight=${query.fontWeight}.'
              : 'Closest token: ${closest.token.qualifiedName} '
                    '(${closest.rationale ?? ''}).',
          suggestedFix: closest == null
              ? 'Add a TypographyToken to the consumer\'s catalog, or change '
                    'the design to use an existing token.'
              : 'Change the design to ${closest.token.qualifiedName}, or add '
                    'a new TypographyToken with size=${query.fontSize}, '
                    'weight=${query.fontWeight}.',
          severity: Severity.blocker,
        );
    }
  }

  String _ambiguousColorMessage(
    String elementId,
    String field,
    String hex,
    ResolutionResult<ColorToken> result,
  ) {
    final list = result.candidates
        .take(2)
        .map((c) => '${c.token.qualifiedName} (${c.rationale ?? ''})')
        .join(' vs ');
    return 'Two tokens are within tolerance of $hex: $list. Pick one '
        'explicitly so the generated code is deterministic.';
  }

  String _topNames<T extends DesignToken>(List<TokenCandidate<T>> candidates) =>
      candidates.take(3).map((c) => c.token.qualifiedName).join(', ');

  static Object? _readNested(Map<String, Object?> map, String dottedPath) {
    final parts = dottedPath.split('.');
    Object? current = map;
    for (final part in parts) {
      if (current is! Map<String, Object?>) return null;
      current = current[part];
    }
    return current;
  }

  static int? _ndsWeightToNumeric(String? raw) {
    switch (raw) {
      case 'normal':
        return 400;
      case 'w600':
        return 600;
      case 'bold':
        return 700;
      default:
        return null;
    }
  }

  static Map<String, Object?> _yamlMapToDart(YamlMap raw) {
    return Map<String, Object?>.fromEntries(
      raw.entries.map((e) => MapEntry(e.key.toString(), _coerceYaml(e.value))),
    );
  }

  static Object? _coerceYaml(Object? v) {
    if (v is YamlMap) return _yamlMapToDart(v);
    if (v is YamlList) return v.map(_coerceYaml).toList(growable: false);
    return v;
  }

  String _projectRelative(String path, String projectRoot) {
    if (!p.isAbsolute(path)) return path;
    try {
      return p.relative(path, from: projectRoot);
    } catch (_) {
      return path;
    }
  }
}

/// Internal snapshot of an NDS document.
class _NdsDocument {
  final String? adapter;
  final List<Map<String, Object?>> elements;
  final String ndsPath;

  const _NdsDocument({
    required this.adapter,
    required this.elements,
    required this.ndsPath,
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Normalized view of a "call expression" — either an
/// [InstanceCreationExpression] or a [MethodInvocation] with a SimpleIdentifier
/// target. Lets rule visitors handle both AST shapes uniformly.
class _Call {
  _Call(this.node, this.type, this.method, this.args);
  final AstNode node;

  /// The class/identifier on the left of the dot, or the bare identifier when
  /// there's no dot. E.g. `Image.asset(...)` → `Image`. `Text(...)` → `Text`.
  final String type;

  /// The method/named-constructor name after the dot, or null when there's no
  /// dot. E.g. `Image.asset(...)` → `asset`. `Text(...)` → null.
  final String? method;

  final ArgumentList args;
}

_Call? _toCall(AstNode node) {
  if (node is InstanceCreationExpression) {
    final type = node.constructorName.type.name.lexeme;
    final ctor = node.constructorName.name?.name;
    return _Call(node, type, ctor, node.argumentList);
  }
  if (node is MethodInvocation) {
    final target = node.target;
    if (target == null) {
      // Bare identifier call: `Text('foo')`, `ElevatedButton(...)`.
      return _Call(node, node.methodName.name, null, node.argumentList);
    }
    if (target is SimpleIdentifier) {
      // Dotted: `Image.asset(...)`, `Lottie.asset(...)`, `OutlinedButton.icon(...)`.
      return _Call(node, target.name, node.methodName.name, node.argumentList);
    }
  }
  return null;
}

abstract class _RuleVisitor extends RecursiveAstVisitor<void> {
  final List<AnalysisIssue> issues = [];

  /// Subclasses override to inspect the normalized call.
  void onCall(_Call call);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final call = _toCall(node);
    if (call != null) onCall(call);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final call = _toCall(node);
    if (call != null) onCall(call);
    super.visitMethodInvocation(node);
  }
}

// ── Rule 1: missing_image_fit ──────────────────────────────────────────────

class _MissingImageFitVisitor extends _RuleVisitor {
  _MissingImageFitVisitor(this.filePath, this.lineInfo);
  final String filePath;
  final LineInfo lineInfo;

  static const _patterns = <(String, String)>{
    ('Image', 'asset'),
    ('Image', 'network'),
    ('Image', 'file'),
    ('Image', 'memory'),
    ('SvgPicture', 'asset'),
    ('SvgPicture', 'network'),
    ('SvgPicture', 'string'),
    ('SvgPicture', 'memoryBytes'),
    ('Lottie', 'asset'),
    ('Lottie', 'network'),
    ('Lottie', 'memory'),
    ('Lottie', 'file'),
  };

  @override
  void onCall(_Call call) {
    if (call.method == null) return;
    if (!_patterns.contains((call.type, call.method!))) return;
    final hasFit = call.args.arguments.any(
      (arg) => arg is NamedExpression && arg.name.label.name == 'fit',
    );
    if (hasFit) return;
    final line = lineInfo.getLocation(call.node.offset).lineNumber;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: line,
        rule: 'Visual fidelity: image widget must specify fit:',
        ruleId: 'visual_fidelity/missing_image_fit',
        message:
            '${call.type}.${call.method}(...) called without a fit: argument.',
        suggestedFix:
            'Add `fit: BoxFit.contain` for icons/illustrations, or '
            '`fit: BoxFit.cover` for backgrounds.',
        severity: Severity.critical,
      ),
    );
  }
}

// ── Rule 2: emoji_as_icon ──────────────────────────────────────────────────

class _EmojiAsIconVisitor extends _RuleVisitor {
  _EmojiAsIconVisitor(this.filePath, this.lineInfo, {this.ndsSourceAdapter});
  final String filePath;
  final LineInfo lineInfo;
  final String? ndsSourceAdapter;

  @override
  void onCall(_Call call) {
    if (call.type != 'Text' || call.method != null) return;
    if (call.args.arguments.isEmpty) return;
    final first = call.args.arguments.first;
    if (first is! StringLiteral) return;
    final value = first.stringValue;
    if (value == null || !_looksLikeEmojiIcon(value)) return;
    final line = lineInfo.getLocation(call.node.offset).lineNumber;
    // Severity ladder: critical when the design source is figma (emoji is
    // explicitly substituting an icon node); major otherwise.
    final severity = ndsSourceAdapter == 'figma'
        ? Severity.critical
        : Severity.major;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: line,
        rule:
            'Visual fidelity: emoji used as an icon stand-in inside Text(...)',
        ruleId: 'visual_fidelity/emoji_as_icon',
        message:
            'Text widget contains only emoji ("$value"); the design likely '
            'expected an Image.asset() / SvgPicture.asset() / Lottie.asset() here.',
        suggestedFix:
            'Replace with the correct asset call. If the asset path is unknown, '
            'emit a `// TODO: asset unknown` comment and a placeholder SizedBox.',
        severity: severity,
      ),
    );
  }

  static bool _looksLikeEmojiIcon(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 4) return false;
    final runes = trimmed.runes.toList();
    if (runes.isEmpty) return false;
    final hasEmoji = runes.any(_isEmojiRune);
    if (!hasEmoji) return false;
    return runes.every(
      (r) => _isEmojiRune(r) || r == 0x200D || r == 0xFE0F || r == 0xFE0E,
    );
  }

  static bool _isEmojiRune(int r) =>
      (r >= 0x1F000 && r <= 0x1FFFF) ||
      (r >= 0x2600 && r <= 0x27BF) ||
      (r >= 0x2300 && r <= 0x23FF);
}

// ── Rule 3: button_without_content ─────────────────────────────────────────

class _ButtonWithoutContentVisitor extends _RuleVisitor {
  _ButtonWithoutContentVisitor(this.filePath, this.lineInfo);
  final String filePath;
  final LineInfo lineInfo;

  static const _buttonTypes = {
    'ElevatedButton',
    'TextButton',
    'OutlinedButton',
    'FilledButton',
    'CupertinoButton',
  };

  static const _contentTypes = {
    'Text',
    'Image',
    'Icon',
    'SvgPicture',
    'Lottie',
    'RichText',
    'SelectableText',
  };

  @override
  void onCall(_Call call) {
    if (!_buttonTypes.contains(call.type)) return;
    // Named constructors like ElevatedButton.icon(...) almost always include
    // an `icon:` Icon — but we still scan the subtree for a content widget.
    if (!_hasVisibleContent(call.args)) {
      final line = lineInfo.getLocation(call.node.offset).lineNumber;
      final ctorSuffix = call.method == null ? '' : '.${call.method}';
      issues.add(
        AnalysisIssue(
          file: filePath,
          line: line,
          rule: 'Visual fidelity: button must contain visible content',
          ruleId: 'visual_fidelity/button_without_content',
          message:
              '${call.type}$ctorSuffix has no Text, Image, Icon, or other '
              'visible widget as content. The button will render blank.',
          suggestedFix:
              'Add a child Text("...") or Image.asset(...) / Icon(...) matching '
              'the NDS button.label or button.icon.',
          severity: Severity.blocker,
        ),
      );
    }
  }

  bool _hasVisibleContent(ArgumentList args) {
    var found = false;
    final scout = _ContentScout(_contentTypes, () => found = true);
    args.visitChildren(scout);
    return found;
  }
}

class _ContentScout extends RecursiveAstVisitor<void> {
  _ContentScout(this.contentTypes, this.onFound);
  final Set<String> contentTypes;
  final void Function() onFound;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    if (contentTypes.contains(type)) onFound();
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target;
    final type = target == null
        ? node.methodName.name
        : (target is SimpleIdentifier ? target.name : null);
    if (type != null && contentTypes.contains(type)) onFound();
    super.visitMethodInvocation(node);
  }
}

// ── Rule 4: asset_path_broken ──────────────────────────────────────────────

class _AssetPathBrokenVisitor extends _RuleVisitor {
  _AssetPathBrokenVisitor(
    this.filePath,
    this.lineInfo, {
    required this.projectRoot,
    required this.sourceContent,
  });
  final String filePath;
  final LineInfo lineInfo;
  final String projectRoot;
  final String sourceContent;

  static const _patterns = <(String, String)>{
    ('Image', 'asset'),
    ('SvgPicture', 'asset'),
    ('Lottie', 'asset'),
  };

  @override
  void onCall(_Call call) {
    if (call.method == null) return;
    if (!_patterns.contains((call.type, call.method!))) return;
    if (call.args.arguments.isEmpty) return;
    final first = call.args.arguments.first;
    if (first is! StringLiteral) return;
    final path = first.stringValue;
    if (path == null) return;
    // packages/* references resolve against an imported package's assets,
    // not the consumer project. False positives common otherwise.
    if (path.startsWith('packages/')) return;
    final absolute = p.normalize(p.join(projectRoot, path));
    if (File(absolute).existsSync()) return;
    if (_hasTodoCommentNearby(call.node)) return;

    final line = lineInfo.getLocation(call.node.offset).lineNumber;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: line,
        rule: 'Visual fidelity: asset file does not exist',
        ruleId: 'visual_fidelity/asset_path_broken',
        message:
            '${call.type}.${call.method}("$path") references a file that does '
            'not exist at <projectRoot>/$path. This will crash at runtime.',
        suggestedFix:
            'Add the asset to the project (and declare it in pubspec.yaml), OR '
            'replace the call with a `// TODO: asset missing — expected at '
            '$path` comment plus a placeholder SizedBox.',
        severity: Severity.critical,
      ),
    );
  }

  /// Returns true if the source within ~200 chars before [node] contains a
  /// TODO comment mentioning "asset", "missing", or "unknown".
  bool _hasTodoCommentNearby(AstNode node) {
    final start = node.offset;
    final from = (start - 200).clamp(0, sourceContent.length);
    final snippet = sourceContent.substring(from, start);
    final pattern = RegExp(
      r'//\s*TODO\b.*(asset|missing|unknown)',
      caseSensitive: false,
    );
    return pattern.hasMatch(snippet);
  }
}
