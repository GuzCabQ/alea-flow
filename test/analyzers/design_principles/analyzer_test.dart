// Tests for the design_principles analyzer.
//
// Covers:
//   (a) 8 public methods → no issue (default limit 10).
//   (b) 12 public methods → SRP violation issue.
//   (c) config override max_public_methods:15 → 12-method class passes.
//   (d) 9 constructor params → coupling issue (default 7).
//   (e) config override max_constructor_params:12 → 9-param constructor passes.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DesignPrinciplesAnalyzer', () {
    late String fixtureRoot;

    setUp(() {
      fixtureRoot = p.normalize(
        p.join(
          Directory.current.path,
          'test/analyzers/design_principles/fixtures',
        ),
      );
    });

    test('(a) 8 public methods → no issue with default config', () async {
      final result = await _run(
        analyzer: DesignPrinciplesAnalyzer(),
        config: _buildConfig(),
        projectRoot: fixtureRoot,
        files: ['eight_methods.dart'],
      );
      expect(result.issues, isEmpty);
    });

    test('(b) 12 public methods → SRP violation with default config', () async {
      final result = await _run(
        analyzer: DesignPrinciplesAnalyzer(),
        config: _buildConfig(),
        projectRoot: fixtureRoot,
        files: ['twelve_methods.dart'],
      );
      expect(
        result.issues.where((i) => i.rule == 'class_too_many_methods'),
        isNotEmpty,
      );
    });

    test(
      '(c) config override max_public_methods:15 → 12-method class passes',
      () async {
        final result = await _run(
          analyzer: DesignPrinciplesAnalyzer(),
          config: _buildConfig(
            analyzerOptions: {
              'design_principles': {'max_public_methods': 15},
            },
          ),
          projectRoot: fixtureRoot,
          files: ['twelve_methods.dart'],
        );
        expect(
          result.issues.where((i) => i.rule == 'class_too_many_methods'),
          isEmpty,
        );
      },
    );

    test(
      '(d) 9 constructor params → coupling issue with default config',
      () async {
        final result = await _run(
          analyzer: DesignPrinciplesAnalyzer(),
          config: _buildConfig(),
          projectRoot: fixtureRoot,
          files: ['nine_params.dart'],
        );
        expect(
          result.issues.where((i) => i.rule == 'constructor_too_many_params'),
          isNotEmpty,
        );
      },
    );

    test(
      '(e) config override max_constructor_params:12 → 9-param ctor passes',
      () async {
        final result = await _run(
          analyzer: DesignPrinciplesAnalyzer(),
          config: _buildConfig(
            analyzerOptions: {
              'design_principles': {'max_constructor_params': 12},
            },
          ),
          projectRoot: fixtureRoot,
          files: ['nine_params.dart'],
        );
        expect(
          result.issues.where((i) => i.rule == 'constructor_too_many_params'),
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
