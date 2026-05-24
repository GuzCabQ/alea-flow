// ALEA — ScaffoldVerifier.
//
// Runs a fixed slice of analyzers over the files that were just
// created/modified and reports whether the scaffold passes. The caller
// (typically `CodeGenOrchestrator`) decides whether to roll back; the
// verifier itself never touches disk.
//
// Default verifier slice — the two analyzers that catch the most common
// post-gen breakages:
//   - `layer_integrity`  → catches forbidden cross-layer imports the
//                          template might have introduced.
//   - `wiring_cohesion`  → catches a generated screen/service that wasn't
//                          wired into the manifest by a follow-up patch.
//
// Consumers wanting a stricter check can pass their own list; the verifier
// runs whatever analyzer set it receives.

import 'dart:async';

import 'package:path/path.dart' as p;

import '../analyzers/layer_integrity/analyzer.dart';
import '../analyzers/wiring_cohesion/analyzer.dart';
import '../contracts/analyzer.dart';
import '../contracts/project_config.dart';
import '../contracts/run_journal.dart';
import '../contracts/scaffolding.dart';

class ScaffoldVerifier {
  final List<Analyzer> analyzers;
  final ProjectConfig config;
  final String projectRoot;
  final RunJournal? journal;

  ScaffoldVerifier({
    required this.config,
    required this.projectRoot,
    List<Analyzer>? analyzers,
    this.journal,
  }) : analyzers =
           analyzers ??
           <Analyzer>[LayerIntegrityAnalyzer(), WiringCohesionAnalyzer()];

  /// Run [analyzers] against the files touched by [outcomes] and decide
  /// whether the scaffold passes.
  ///
  /// Pass criteria:
  ///   - Zero `blocker`-severity issues.
  ///   - Zero `critical`-severity issues.
  /// Anything `major` or `minor` is reported but does not block.
  Future<ScaffoldVerification> verify(
    List<ScaffoldOutcome> outcomes, {
    String? runDirectory,
  }) async {
    final sw = Stopwatch()..start();
    final paths = outcomes
        .where(
          (o) =>
              o.action == ScaffoldAction.create ||
              o.action == ScaffoldAction.modify,
        )
        .map((o) => p.join(projectRoot, o.relativePath))
        .toList(growable: false);

    await journal?.record(
      JournalEvent(
        source: 'scaffold:verifier',
        kind: JournalEventKind.started,
        payload: {
          'analyzers': analyzers.map((a) => a.name).toList(),
          'files': paths.length,
        },
      ),
    );

    final ctx = AnalyzerContext(
      filePaths: paths,
      projectRoot: projectRoot,
      runDirectory: runDirectory,
      config: config,
      journal: journal,
    );

    final allIssues = <AnalysisIssue>[];
    for (final analyzer in analyzers) {
      final result = await analyzer.analyze(ctx);
      allIssues.addAll(result.issues);
    }

    final blockers = allIssues
        .where(
          (i) =>
              i.severity == Severity.blocker || i.severity == Severity.critical,
        )
        .toList();
    final passed = blockers.isEmpty;
    sw.stop();

    await journal?.record(
      JournalEvent(
        source: 'scaffold:verifier',
        kind: passed ? JournalEventKind.completed : JournalEventKind.error,
        payload: {
          'passed': passed,
          'issues': allIssues.length,
          'blockers': blockers.length,
          'elapsed_ms': sw.elapsedMilliseconds,
        },
      ),
    );

    return ScaffoldVerification(
      passed: passed,
      issues: List.unmodifiable(allIssues),
      elapsed: sw.elapsed,
    );
  }
}
