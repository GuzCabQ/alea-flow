// ALEA — Analyzer runner.
//
// Composes a list of analyzers, runs them concurrently against a file set,
// applies severity overrides from [ProjectConfig.analyzers.severityOverrides],
// and produces a [GateReport].

import '../contracts/analyzer.dart';
import '../contracts/design_token_catalog.dart';
import '../contracts/project_config.dart';
import '../contracts/run_journal.dart';

class AnalyzerRunner {
  AnalyzerRunner(this.registry);

  /// Every analyzer ALEA knows how to invoke. Typically built from
  /// [registeredAnalyzers] but tests can inject a smaller set.
  final List<Analyzer> registry;

  /// Run the analyzers that match [config.analyzers.enabled] (or all of
  /// [registry] when [config.analyzers.enabled] is empty), against the given
  /// file paths. Returns the assembled [GateReport].
  Future<GateReport> run({
    required String gate,
    required List<String> filePaths,
    required String projectRoot,
    String? runDirectory,
    required ProjectConfig config,
    RunJournal? journal,
    DesignTokenCatalog? tokenCatalog,
  }) async {
    final enabledNames = config.analyzers.enabled.toSet();
    final selected = enabledNames.isEmpty
        ? registry
        : registry.where((a) => enabledNames.contains(a.name)).toList();

    final ctx = AnalyzerContext(
      filePaths: filePaths,
      projectRoot: projectRoot,
      runDirectory: runDirectory,
      config: config,
      gate: gate,
      journal: journal,
      tokenCatalog: tokenCatalog,
    );

    await journal?.record(
      JournalEvent(
        source: 'runner',
        kind: JournalEventKind.started,
        payload: {
          'gate': gate,
          'analyzers': selected.map((a) => a.name).toList(growable: false),
          'file_count': filePaths.length,
        },
      ),
    );

    final results = await Future.wait(selected.map((a) => a.analyze(ctx)));
    final overridden = results
        .map((r) => _applyOverrides(r, config.analyzers.severityOverrides))
        .toList(growable: false);

    final report = GateReport(gate: gate, results: overridden);

    await journal?.record(
      JournalEvent(
        source: 'runner',
        kind: report.passed
            ? JournalEventKind.completed
            : JournalEventKind.warning,
        payload: {
          'gate': gate,
          'passed': report.passed,
          'total_issues': overridden.fold<int>(
            0,
            (s, r) => s + r.issues.length,
          ),
        },
      ),
    );

    return report;
  }

  AnalysisResult _applyOverrides(
    AnalysisResult r,
    Map<String, String> overrides,
  ) {
    final override = overrides[r.analyzer];
    if (override == null) return r;
    final coerced = _parseSeverity(override);
    if (coerced == null) return r;
    final newIssues = r.issues
        .map(
          (i) => AnalysisIssue(
            file: i.file,
            line: i.line,
            rule: i.rule,
            ruleId: i.ruleId,
            message: i.message,
            suggestedFix: i.suggestedFix,
            severity: coerced,
          ),
        )
        .toList(growable: false);
    return AnalysisResult(analyzer: r.analyzer, issues: newIssues);
  }

  static Severity? _parseSeverity(String s) {
    switch (s.toLowerCase()) {
      case 'minor':
        return Severity.minor;
      case 'major':
        return Severity.major;
      case 'critical':
        return Severity.critical;
      case 'blocker':
        return Severity.blocker;
      default:
        return null;
    }
  }
}
