// Tests for the dry_detection analyzer.
//
// Covers:
//   (a) a file with a string repeated 3× → DRY issue (default min_occurrences 3).
//   (b) config override min_occurrences:5 → the same 3× repetition passes.
//   (c) config override min_length:30 → a 23-char string repeated 3× passes.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DryDetectionAnalyzer', () {
    late String fixtureRoot;

    setUp(() {
      fixtureRoot = p.normalize(
        p.join(Directory.current.path, 'test/analyzers/dry_detection/fixtures'),
      );
    });

    test('(a) string repeated 3× → DRY issue with default config', () async {
      final result = await _run(
        analyzer: DryDetectionAnalyzer(),
        config: _buildConfig(),
        projectRoot: fixtureRoot,
        files: ['repeated_three_times.dart'],
      );
      expect(
        result.issues.where((i) => i.rule == 'dry_string_literal'),
        isNotEmpty,
      );
    });

    test(
      '(b) config override min_occurrences:5 → 3× repetition passes',
      () async {
        final result = await _run(
          analyzer: DryDetectionAnalyzer(),
          config: _buildConfig(
            analyzerOptions: {
              'dry_detection': {'min_occurrences': 5},
            },
          ),
          projectRoot: fixtureRoot,
          files: ['repeated_three_times.dart'],
        );
        expect(
          result.issues.where((i) => i.rule == 'dry_string_literal'),
          isEmpty,
        );
      },
    );

    test(
      '(c) config override min_length:30 → 23-char repeated string passes',
      () async {
        // The fixture literal 'my_repeated_literal_key' has length 23, which is
        // below min_length 30, so no issue should be raised.
        final result = await _run(
          analyzer: DryDetectionAnalyzer(),
          config: _buildConfig(
            analyzerOptions: {
              'dry_detection': {'min_length': 30},
            },
          ),
          projectRoot: fixtureRoot,
          files: ['repeated_three_times.dart'],
        );
        expect(
          result.issues.where((i) => i.rule == 'dry_string_literal'),
          isEmpty,
        );
      },
    );
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

Future<AnalysisResult> _run({
  required Analyzer analyzer,
  required ProjectConfig config,
  required String projectRoot,
  required List<String> files,
}) async {
  final absolutePaths = files.map((f) => p.join(projectRoot, f)).toList();
  return analyzer.analyze(
    AnalyzerContext(
      filePaths: absolutePaths,
      projectRoot: projectRoot,
      config: config,
    ),
  );
}

ProjectConfig _buildConfig({
  Map<String, Map<String, Object?>> analyzerOptions = const {},
}) {
  return ProjectConfig(
    configVersion: '1.0.0',
    project: const ProjectInfo(
      packageName: 'sample_app',
      pubspecPath: 'pubspec.yaml',
    ),
    architecture: const ArchitectureConfig(layers: {}),
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
    coverage: const CoverageConfig(thresholds: {}),
    ticketSource: const TicketSourceConfig(adapter: 'asana'),
    designSource: const DesignSourceConfig(defaultAdapter: 'figma'),
    mr: const MrConfig(
      policy: 'single-commit-amend',
      branchPattern: 'feature/{ticket_id}-{slug}',
      prePush: [],
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
    analyzers: AnalyzersConfig(options: analyzerOptions),
  );
}
