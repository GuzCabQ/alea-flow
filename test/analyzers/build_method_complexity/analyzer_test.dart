// Tests for the build_method_complexity analyzer.
//
// Covers:
//   (a) clean build (depth 2, 10 lines) → no issues.
//   (b) deeply-nested build (depth 6) with default config → nesting issue.
//   (c) config override max_children_depth: 8 → the depth-6 build passes.
//   (d) two separate over-deep sibling branches → TWO nesting issues.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('BuildMethodComplexityAnalyzer', () {
    late String fixtureRoot;

    setUp(() {
      fixtureRoot = p.normalize(
        p.join(
          Directory.current.path,
          'test/analyzers/build_method_complexity/fixtures',
        ),
      );
    });

    test('(a) emits no issues for a clean shallow build', () async {
      final result = await _run(
        analyzer: BuildMethodComplexityAnalyzer(),
        config: _buildConfig(),
        projectRoot: fixtureRoot,
        files: ['clean_build.dart'],
      );
      expect(result.issues, isEmpty);
    });

    test('(b) flags deeply-nested build with default config', () async {
      final result = await _run(
        analyzer: BuildMethodComplexityAnalyzer(),
        config: _buildConfig(),
        projectRoot: fixtureRoot,
        files: ['deep_nesting.dart'],
      );
      expect(
        result.issues.where((i) => i.rule == 'build_nesting_too_deep'),
        isNotEmpty,
      );
    });

    test(
      '(c) config override max_children_depth:8 → depth-6 build passes',
      () async {
        final result = await _run(
          analyzer: BuildMethodComplexityAnalyzer(),
          config: _buildConfig(
            analyzerOptions: {
              'build_method_complexity': {'max_children_depth': 8},
            },
          ),
          projectRoot: fixtureRoot,
          files: ['deep_nesting.dart'],
        );
        expect(
          result.issues.where((i) => i.rule == 'build_nesting_too_deep'),
          isEmpty,
        );
      },
    );

    test('(d) two sibling over-deep branches → two nesting issues', () async {
      final result = await _run(
        analyzer: BuildMethodComplexityAnalyzer(),
        config: _buildConfig(),
        projectRoot: fixtureRoot,
        files: ['two_sibling_violations.dart'],
      );
      final nestingIssues = result.issues
          .where((i) => i.rule == 'build_nesting_too_deep')
          .toList();
      expect(nestingIssues, hasLength(2));
    });
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
