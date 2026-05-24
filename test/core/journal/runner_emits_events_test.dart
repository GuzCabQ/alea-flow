// Integration test — confirms that AnalyzerRunner threads a journal through
// to analyzers and that an instrumented analyzer (LayerIntegrityAnalyzer)
// emits started/completed events for every run.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('runner + instrumented analyzer emit start/end events', () async {
    final tmp = Directory.systemTemp.createTempSync('alea_runner_journal_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final fixtureRoot = p.normalize(
      p.join(Directory.current.path, 'test/analyzers/layer_integrity/fixtures'),
    );

    final config = ProjectConfig(
      configVersion: '1.0.0',
      project: const ProjectInfo(
        packageName: 'sample_app',
        pubspecPath: 'pubspec.yaml',
      ),
      architecture: const ArchitectureConfig(
        layers: {
          'domain': LayerConfig(
            paths: ['lib/src/domain/'],
            forbidImports: ['package:flutter/'],
          ),
        },
      ),
      stateManagement: const StateManagementConfig(style: 'riverpod_manual'),
      routing: const RoutingConfig(
        package: 'go_router',
        routerPath: 'lib/app/router/app_router.dart',
      ),
      theme: const ThemeConfig(path: 'lib/app/theme/app_theme.dart'),
      testing: const TestingConfig(
        framework: 'flutter_test',
        fakesPath: 'test/fakes/',
      ),
      coverage: const CoverageConfig(thresholds: {'domain': 95}),
      ticketSource: const TicketSourceConfig(adapter: 'file'),
      designSource: const DesignSourceConfig(defaultAdapter: 'figma'),
      mr: const MrConfig(
        policy: 'single-commit-amend',
        branchPattern: 'feature/{ticket_id}-{slug}',
        prePush: ['dart format .'],
      ),
      pipeline: const PipelineOpsConfig(
        defaultMode: 'guided',
        modesAvailable: ['guided'],
        costWarnUsd: 3.0,
        costHardStopUsd: 5.0,
        unreliableThreshold: UnreliableThresholdConfig(
          runsWindow: 5,
          badRunsRequired: 3,
          manualCorrectionsPerRun: 5,
        ),
      ),
      gates: const GatesConfig(perLayer: {}),
      analyzers: const AnalyzersConfig(enabled: ['layer_integrity']),
    );

    final journal = JsonlRunJournal.forRunDirectory(tmp.path);
    final runner = AnalyzerRunner([LayerIntegrityAnalyzer()]);

    final report = await runner.run(
      gate: 'domain',
      filePaths: [
        p.join(fixtureRoot, 'lib/src/domain/violation_imports_flutter.dart'),
      ],
      projectRoot: fixtureRoot,
      config: config,
      journal: journal,
    );

    expect(report.results.single.issues, hasLength(1));

    final events = await journal.readAll().toList();
    await journal.close();

    final sources = events.map((e) => e.source).toList();
    final kinds = events.map((e) => e.kind).toList();

    expect(
      sources,
      containsAllInOrder([
        'runner',
        'analyzer:layer_integrity',
        'analyzer:layer_integrity',
        'runner',
      ]),
    );
    expect(kinds.first, JournalEventKind.started);
    expect(
      kinds.last,
      anyOf(JournalEventKind.completed, JournalEventKind.warning),
    );

    final analyzerCompleted = events.firstWhere(
      (e) =>
          e.source == 'analyzer:layer_integrity' &&
          e.kind == JournalEventKind.completed,
    );
    expect(analyzerCompleted.payload['issues_found'], 1);
  });
}
