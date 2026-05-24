// ALEA — Layer Integrity Analyzer.
//
// Ported from tools/pipeline/lib/src/analyzers/layer_integrity_analyzer.dart.
//
// Design property:
//   - Nothing about the consumer's package name, layer set, or path segments
//     is hardcoded. Every value comes from
//     `AnalyzerContext.config.architecture.layers` and
//     `AnalyzerContext.config.project.packageName`.
//
// Algorithm:
//   1. For each input file, find its layer by matching the project-relative
//      file path against `layers[*].paths`. Files not in any layer are skipped.
//   2. Parse the file's import directives via package:analyzer's AST.
//   3. Canonicalize each import URI:
//        - `dart:*` and `package:*` URIs are returned as-is.
//        - Relative imports are resolved against the importing file's directory,
//          then rewritten to `package:<own_package>/<rest>` form when they land
//          under `lib/`.
//   4. For each canonicalized URI, check whether it starts with any prefix in
//      the from-layer's `forbid_imports` list. On match: emit one `blocker`
//      issue and move on to the next import.
//
// Severity is always `blocker` here; consumers that want it demoted use
// `analyzers.severity_overrides.layer_integrity: <severity>` in `.alea.yaml`,
// applied by the runner — not by this analyzer.
//
// Dependencies (declared in alea/pubspec.yaml, created during step 12 of MIGRATION):
//   - package:analyzer  — Dart source AST parsing
//   - package:path      — cross-platform path normalization

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../../contracts/analyzer.dart';
import '../../contracts/project_config.dart';
import '../../contracts/run_journal.dart';

class LayerIntegrityAnalyzer extends Analyzer {
  @override
  String get name => 'layer_integrity';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    await ctx.journal?.record(
      JournalEvent(
        source: 'analyzer:$name',
        kind: JournalEventKind.started,
        payload: {'file_count': ctx.filePaths.length},
      ),
    );

    final issues = <AnalysisIssue>[];
    final layers = ctx.config.architecture.layers;
    final packageName = ctx.config.project.packageName;
    final projectRoot = ctx.projectRoot;

    // Step 1 — bucket files by layer; drop files not in any layer.
    final byLayer = <String, String>{}; // absolute filePath -> layer name
    for (final filePath in ctx.filePaths) {
      final layer = _layerOf(filePath, layers, projectRoot);
      if (layer != null) byLayer[filePath] = layer;
    }
    if (byLayer.isEmpty) return issues;

    final layeredPaths = byLayer.keys.map(p.normalize).toList();
    final collection = AnalysisContextCollection(includedPaths: layeredPaths);

    // Step 2-4 — parse and check imports per file.
    for (final entry in byLayer.entries) {
      final normalizedPath = p.normalize(entry.key);
      final fromLayerName = entry.value;
      final fromLayer = layers[fromLayerName]!;

      final context = collection.contextFor(normalizedPath);
      final parseResult = context.currentSession.getParsedUnit(normalizedPath);
      if (parseResult is! ParsedUnitResult) continue;

      for (final directive in parseResult.unit.directives) {
        if (directive is! ImportDirective) continue;
        final rawUri = directive.uri.stringValue ?? '';
        if (rawUri.isEmpty) continue;

        final canonical = _canonicalize(
          rawUri,
          fromFile: normalizedPath,
          packageName: packageName,
          projectRoot: projectRoot,
        );

        for (final forbidden in fromLayer.forbidImports) {
          if (canonical.startsWith(forbidden)) {
            final line = parseResult.lineInfo
                .getLocation(directive.offset)
                .lineNumber;
            issues.add(
              AnalysisIssue(
                file: _projectRelative(normalizedPath, projectRoot),
                line: line,
                rule:
                    'Layer integrity: $fromLayerName must not import $forbidden',
                ruleId:
                    'layer_integrity/${fromLayerName}_imports_${_slugForbid(forbidden)}',
                message:
                    '$fromLayerName must not import from forbidden layer: $rawUri',
                suggestedFix:
                    'Move the imported symbol to $fromLayerName, or invert the '
                    'dependency via an interface owned by $fromLayerName.',
                severity: Severity.blocker,
              ),
            );
            break; // one issue per import directive
          }
        }
      }
    }

    await ctx.journal?.record(
      JournalEvent(
        source: 'analyzer:$name',
        kind: JournalEventKind.completed,
        payload: {
          'issues_found': issues.length,
          'files_evaluated': byLayer.length,
        },
      ),
    );

    return issues;
  }

  /// Find the layer that contains [filePath]. Returns the layer name (e.g.
  /// `domain`) or null when no layer's `paths` match.
  ///
  /// Path matching is prefix-based on the project-relative form, with the
  /// layer path's trailing slash enforced so that `lib/src/domain/` does NOT
  /// match `lib/src/domain_helpers/foo.dart`.
  String? _layerOf(
    String filePath,
    Map<String, LayerConfig> layers,
    String projectRoot,
  ) {
    final relative = _projectRelative(
      filePath,
      projectRoot,
    ).replaceAll(r'\', '/');
    for (final entry in layers.entries) {
      for (final layerPath in entry.value.paths) {
        final lp = layerPath.replaceAll(r'\', '/');
        final lpWithSlash = lp.endsWith('/') ? lp : '$lp/';
        if (relative.startsWith(lpWithSlash)) return entry.key;
      }
    }
    return null;
  }

  /// Convert an import URI to a canonical form suitable for prefix-matching
  /// against `forbid_imports`.
  ///
  /// `dart:*` and `package:*` URIs are returned unchanged. Relative imports
  /// are resolved against [fromFile]'s directory and, when the result lands
  /// under `lib/`, rewritten as `package:<packageName>/<rest>`. Anything else
  /// (e.g. a relative import that escapes `lib/`) is returned as a
  /// project-relative path — usually it won't match any forbid prefix, which
  /// is the correct outcome.
  String _canonicalize(
    String uri, {
    required String fromFile,
    required String packageName,
    required String projectRoot,
  }) {
    if (uri.startsWith('dart:') || uri.startsWith('package:')) return uri;
    final absolute = p.normalize(p.join(p.dirname(fromFile), uri));
    final relative = _projectRelative(
      absolute,
      projectRoot,
    ).replaceAll(r'\', '/');
    if (relative.startsWith('lib/')) {
      return 'package:$packageName/${relative.substring('lib/'.length)}';
    }
    return relative;
  }

  /// If [path] is absolute, return its project-relative form. Otherwise return
  /// [path] unchanged. Path separators are normalized to forward slashes by
  /// the caller as needed.
  String _projectRelative(String path, String projectRoot) {
    if (!p.isAbsolute(path)) return path;
    try {
      return p.relative(path, from: projectRoot);
    } catch (_) {
      return path;
    }
  }

  /// Build a stable slug for ruleId from a forbid prefix.
  /// `package:my_app/src/infrastructure/` → `package_my_app_src_infrastructure`.
  /// `package:flutter/` → `package_flutter`.
  String _slugForbid(String forbid) {
    final s = forbid
        .replaceAll('package:', 'package_')
        .replaceAll('/', '_')
        .replaceAll(':', '_')
        .replaceAll('-', '_')
        .toLowerCase();
    return s.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'_$'), '');
  }
}
