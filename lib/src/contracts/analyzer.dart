// ALEA — Analyzer contract.
//
// Every analyzer under alea/analyzers/<name>/ implements [Analyzer].
// Every gate under alea/gates/<name>/ consumes [AnalysisResult] and aggregates into [GateReport].
//
// Ported from tools/pipeline/lib/src/models/analysis_result.dart and base_analyzer.dart.
// Differences from the original:
//   - Analyzer receives an [AnalyzerContext] (file paths + ProjectConfig) instead of bare
//     file paths, so analyzers can read project-specific layer paths from config.
//   - AnalysisIssue gains optional `ruleId` and `suggestedFix` fields (non-breaking — both
//     default to null).
//   - GateReport gains optional `metrics` map for non-issue metrics (coverage %, fidelity score).

import 'design_token_catalog.dart';
import 'project_config.dart';
import 'run_journal.dart';

/// Severity ordering: minor < major < critical < blocker.
///
/// An [AnalysisResult] passes when it contains no `critical` and no `blocker` issues.
/// A [GateReport] passes when every [AnalysisResult] in it passes AND every metric
/// threshold declared by the gate is met.
enum Severity { minor, major, critical, blocker }

class AnalysisIssue {
  final String file;
  final int? line;
  final String rule;
  final String? ruleId;
  final String message;
  final String? suggestedFix;
  final Severity severity;

  const AnalysisIssue({
    required this.file,
    this.line,
    required this.rule,
    this.ruleId,
    required this.message,
    this.suggestedFix,
    required this.severity,
  });

  Map<String, Object?> toJson() => {
    'file': file,
    if (line != null) 'line': line,
    'rule': rule,
    if (ruleId != null) 'rule_id': ruleId,
    'message': message,
    if (suggestedFix != null) 'suggested_fix': suggestedFix,
    'severity': severity.name,
  };
}

class AnalysisResult {
  final String analyzer;
  final List<AnalysisIssue> issues;

  const AnalysisResult({required this.analyzer, required this.issues});

  bool get passed => !issues.any(
    (i) => i.severity == Severity.blocker || i.severity == Severity.critical,
  );

  Map<String, Object?> toJson() => {
    'analyzer': analyzer,
    'passed': passed,
    'issues': issues.map((i) => i.toJson()).toList(),
  };
}

class GateReport {
  final String gate;
  final DateTime timestamp;
  final List<AnalysisResult> results;
  final Map<String, Object?> metrics;
  final bool passed;

  GateReport({
    required this.gate,
    required this.results,
    this.metrics = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now(),
       passed = results.every((r) => r.passed);

  Map<String, Object?> toJson() => {
    'gate': gate,
    'timestamp': timestamp.toIso8601String(),
    'passed': passed,
    'results': results.map((r) => r.toJson()).toList(),
    if (metrics.isNotEmpty) 'metrics': metrics,
    'summary': {
      'total_issues': results.fold<int>(0, (s, r) => s + r.issues.length),
      'blockers': _count(Severity.blocker),
      'criticals': _count(Severity.critical),
      'majors': _count(Severity.major),
      'minors': _count(Severity.minor),
    },
  };

  int _count(Severity s) => results.fold<int>(
    0,
    (acc, r) => acc + r.issues.where((i) => i.severity == s).length,
  );
}

/// Context passed to every analyzer invocation.
///
/// Carries the file set to analyze plus the parsed [ProjectConfig] so analyzers
/// can resolve project-specific paths (`architecture.layers.domain.paths`),
/// import rules, framework presets, etc., without hardcoding. [projectRoot] is
/// the absolute path to the consumer project root (the directory containing
/// pubspec.yaml); analyzers use it to convert absolute file paths to
/// project-relative for issue reporting and to resolve relative imports.
///
/// [runDirectory] is the optional `.pipeline/runs/<ticket_id>/` path. Most
/// analyzers ignore it. The `visual_fidelity` analyzer (and any future analyzer
/// comparing generated code against run-scoped artifacts like NDS or
/// `widget_map.yaml`) reads it to locate the design-source adapter's output
/// under `<runDirectory>/<adapter>/nds.yaml`. Null when the analyzer is invoked
/// outside a pipeline run (e.g. ad-hoc CLI use).
class AnalyzerContext {
  final List<String> filePaths;
  final String projectRoot;
  final String? runDirectory;
  final ProjectConfig config;
  final String? gate; // optional: which gate is invoking us (for scoping)

  /// Optional event journal for this run. Analyzers should emit observability
  /// events via `ctx.journal?.record(...)`. When null (default for ad-hoc
  /// invocations and most existing tests) the call is a no-op — analyzers
  /// must not branch on whether a journal exists.
  final RunJournal? journal;

  /// Optional pre-built design-token catalog. Analyzers that need to validate
  /// generated code or NDS against the consumer's design system (e.g.
  /// `visual_fidelity`) read tokens through this contract; null means the
  /// caller did not configure a catalog and catalog-dependent checks are
  /// skipped (not a failure — analyzers must degrade gracefully).
  ///
  /// Built by the caller (CLI / consumer code) via
  /// `buildTokenCatalog(config, projectRoot:)`. Kept out of [config] so the
  /// boundary rules that prevent `lib/src/core/` from importing adapters
  /// still hold: the runner ferries an opaque [DesignTokenCatalog] through
  /// the context without ever importing its concrete implementation.
  final DesignTokenCatalog? tokenCatalog;

  const AnalyzerContext({
    required this.filePaths,
    required this.projectRoot,
    this.runDirectory,
    required this.config,
    this.gate,
    this.journal,
    this.tokenCatalog,
  });
}

/// Base contract for every analyzer.
///
/// Implements the Template Method pattern: callers invoke [analyze], subclasses
/// implement [doAnalyze] with the actual detection logic. Concurrency-safe:
/// analyzers must be stateless beyond their constructor-time configuration.
abstract class Analyzer {
  /// Stable, snake_case name (e.g. `layer_integrity`, `visual_fidelity`).
  /// Matches the folder name under `alea/analyzers/<name>/`.
  String get name;

  Future<AnalysisResult> analyze(AnalyzerContext ctx) async {
    final issues = await doAnalyze(ctx);
    return AnalysisResult(analyzer: name, issues: issues);
  }

  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx);
}
