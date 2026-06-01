// Tests for the security analyzer.
//
// Covers:
//   (a) const refreshToken = '...' (16 chars) → flagged (new keyword).
//   (b) const jwtToken = '...' (16 chars) → flagged (new keyword).
//   (c) const encryptionKey = '...' (16 chars) → flagged (new keyword).
//   (d) const greeting = 'hello world here!' → NOT flagged (clean name).
//   (e) config override min_secret_value_length:64 → a 16-char secret value
//       no longer flags.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('SecurityAnalyzer', () {
    late String fixtureRoot;

    setUp(() {
      fixtureRoot = p.normalize(
        p.join(Directory.current.path, 'test/analyzers/security/fixtures'),
      );
    });

    test('(a) refreshToken with long value → flagged', () async {
      final result = await _run(
        analyzer: SecurityAnalyzer(),
        config: _buildConfig(),
        projectRoot: fixtureRoot,
        files: ['new_keywords.dart'],
      );
      expect(
        result.issues
            .where(
              (i) =>
                  i.rule == 'hardcoded_secret' &&
                  i.message.contains('refreshToken'),
            )
            .length,
        1,
      );
    });

    test('(b) jwtToken with long value → flagged', () async {
      final result = await _run(
        analyzer: SecurityAnalyzer(),
        config: _buildConfig(),
        projectRoot: fixtureRoot,
        files: ['new_keywords.dart'],
      );
      expect(
        result.issues
            .where(
              (i) =>
                  i.rule == 'hardcoded_secret' &&
                  i.message.contains('jwtToken'),
            )
            .length,
        1,
      );
    });

    test('(c) encryptionKey with long value → flagged', () async {
      final result = await _run(
        analyzer: SecurityAnalyzer(),
        config: _buildConfig(),
        projectRoot: fixtureRoot,
        files: ['new_keywords.dart'],
      );
      expect(
        result.issues
            .where(
              (i) =>
                  i.rule == 'hardcoded_secret' &&
                  i.message.contains('encryptionKey'),
            )
            .length,
        1,
      );
    });

    test('(d) greeting field → NOT flagged', () async {
      final result = await _run(
        analyzer: SecurityAnalyzer(),
        config: _buildConfig(),
        projectRoot: fixtureRoot,
        files: ['new_keywords.dart'],
      );
      expect(
        result.issues.where(
          (i) => i.rule == 'hardcoded_secret' && i.message.contains('greeting'),
        ),
        isEmpty,
      );
    });

    test(
      '(e) config override min_secret_value_length:64 → 16-char secret passes',
      () async {
        final result = await _run(
          analyzer: SecurityAnalyzer(),
          config: _buildConfig(
            analyzerOptions: {
              'security': {'min_secret_value_length': 64},
            },
          ),
          projectRoot: fixtureRoot,
          files: ['short_value.dart'],
        );
        expect(
          result.issues.where((i) => i.rule == 'hardcoded_secret'),
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
