// ALEA — Package Boundary Analyzer.
//
// Enforces package-level boundary rules declared in
// `architecture.package_boundaries[]` of the consumer's `.alea.yaml`.
//
// Semantics:
//   - Each rule has `applies_to` (path prefixes that select source files) and
//     `forbid` (import URI prefixes that those files must not import).
//   - A single file can match multiple rules; each rule is evaluated
//     independently.
//   - Severity is always `blocker`. Consumers can demote per rule via
//     `analyzers.severity_overrides.package_boundary: <severity>` in
//     `.alea.yaml`, applied uniformly by the runner.
//   - When `package_boundaries` is empty the analyzer is a no-op (default for
//     consumers that have not opted in).
//
// Difference vs `LayerIntegrityAnalyzer`:
//   - LayerIntegrity assigns each file to one layer (first match wins) and
//     applies that layer's forbid list. This is the Clean Architecture model
//     used by app projects.
//   - PackageBoundary applies every matching rule to a file. This is the
//     library-package model used by ALEA itself to enforce contracts purity,
//     analyzer↔adapter separation, and similar orthogonal invariants.

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../../contracts/analyzer.dart';
import '../../contracts/project_config.dart';

class PackageBoundaryAnalyzer extends Analyzer {
  @override
  String get name => 'package_boundary';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final rules = ctx.config.architecture.packageBoundaries;
    if (rules.isEmpty) return const [];

    final packageName = ctx.config.project.packageName;
    final projectRoot = ctx.projectRoot;
    final issues = <AnalysisIssue>[];

    // Step 1 — for each input file, compute the list of rules that apply.
    final byFile = <String, List<PackageBoundary>>{};
    for (final filePath in ctx.filePaths) {
      final applicable = _rulesFor(filePath, rules, projectRoot);
      if (applicable.isNotEmpty) {
        byFile[p.normalize(filePath)] = applicable;
      }
    }
    if (byFile.isEmpty) return const [];

    // Step 2 — open one analysis collection over the affected files.
    final collection = AnalysisContextCollection(
      includedPaths: byFile.keys.toList(),
    );

    // Step 3 — parse each file and check imports against every applicable rule.
    for (final entry in byFile.entries) {
      final filePath = entry.key;
      final applicable = entry.value;

      final context = collection.contextFor(filePath);
      final parseResult = context.currentSession.getParsedUnit(filePath);
      if (parseResult is! ParsedUnitResult) continue;

      for (final directive in parseResult.unit.directives) {
        final UriBasedDirective? uriBased;
        final String directiveKind;
        if (directive is ImportDirective) {
          uriBased = directive;
          directiveKind = 'imports';
        } else if (directive is ExportDirective) {
          // Re-exports can re-introduce a forbidden dependency through the
          // back door (a "pure" library file that exports an I/O module
          // would still leak the dependency to its consumers).
          uriBased = directive;
          directiveKind = 'exports';
        } else {
          continue;
        }
        final rawUri = uriBased.uri.stringValue ?? '';
        if (rawUri.isEmpty) continue;

        final canonical = _canonicalize(
          rawUri,
          fromFile: filePath,
          packageName: packageName,
          projectRoot: projectRoot,
        );

        for (final rule in applicable) {
          for (final forbidden in rule.forbid) {
            if (canonical.startsWith(forbidden)) {
              final line = parseResult.lineInfo
                  .getLocation(directive.offset)
                  .lineNumber;
              issues.add(
                AnalysisIssue(
                  file: _projectRelative(filePath, projectRoot),
                  line: line,
                  rule:
                      'Package boundary "${rule.name}": forbids '
                      '$directiveKind of "$forbidden"',
                  ruleId:
                      'package_boundary/${rule.name}/${_slugForbid(forbidden)}',
                  message: rule.description != null
                      ? '${rule.description} — found: $rawUri'
                      : 'Boundary "${rule.name}" forbids $directiveKind '
                            'of $rawUri',
                  suggestedFix:
                      'Move the offending dependency out of '
                      '"${rule.name}" scope, or invert the dependency via an '
                      'interface owned by the calling layer.',
                  severity: Severity.blocker,
                ),
              );
              break; // at most one issue per (directive, rule)
            }
          }
        }
      }
    }

    return issues;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Rules whose [appliesTo] prefix the project-relative form of [filePath].
  List<PackageBoundary> _rulesFor(
    String filePath,
    List<PackageBoundary> rules,
    String projectRoot,
  ) {
    final relative = _projectRelative(
      filePath,
      projectRoot,
    ).replaceAll(r'\', '/');
    final out = <PackageBoundary>[];
    for (final rule in rules) {
      for (final prefix in rule.appliesTo) {
        final normalized = prefix.replaceAll(r'\', '/');
        final withSlash = normalized.endsWith('/')
            ? normalized
            : '$normalized/';
        if (relative == normalized || relative.startsWith(withSlash)) {
          out.add(rule);
          break;
        }
      }
    }
    return out;
  }

  /// Convert an import URI to the canonical form used for prefix-matching:
  /// `dart:*` and `package:*` are returned unchanged; relative imports are
  /// resolved against the importing file's directory and rewritten as
  /// `package:<packageName>/<rest>` when they land under `lib/`.
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

  String _projectRelative(String path, String projectRoot) {
    if (!p.isAbsolute(path)) return path;
    try {
      return p.relative(path, from: projectRoot);
    } catch (_) {
      return path;
    }
  }

  /// Slug-friendly form of a forbid prefix for use in `ruleId`.
  /// Example: `package:flutter/` → `package_flutter`;
  ///          `dart:io` → `dart_io`;
  ///          `package:alea_flow/src/adapters/` → `package_alea_src_adapters`.
  String _slugForbid(String forbid) {
    final s = forbid
        .replaceAll('package:', 'package_')
        .replaceAll('dart:', 'dart_')
        .replaceAll('/', '_')
        .replaceAll(':', '_')
        .replaceAll('-', '_')
        .toLowerCase();
    return s.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'_$'), '');
  }
}
