// Tests for the package_boundary analyzer.
//
// Strategy: build a synthetic [ProjectConfig] in code that declares the
// boundaries we want to verify, point at the fixtures under
// `test/analyzers/package_boundary/fixtures/`, run the analyzer, and assert
// on the resulting issues.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PackageBoundaryAnalyzer', () {
    late String fixtureRoot;
    late ProjectConfig config;

    setUp(() {
      fixtureRoot = p.normalize(
        p.join(
          Directory.current.path,
          'test/analyzers/package_boundary/fixtures',
        ),
      );
      config = _buildTestConfig();
    });

    test('emits nothing when no boundaries are configured', () async {
      final empty = _withoutBoundaries(config);
      final result = await _run(
        config: empty,
        projectRoot: fixtureRoot,
        files: [
          'lib/src/contracts/violation_imports_dart_io.dart',
          'lib/src/matching/violation_imports_io.dart',
        ],
      );
      expect(
        result.issues,
        isEmpty,
        reason: 'analyzer must be opt-in: no rules → no issues',
      );
    });

    test('passes for a pure contract', () async {
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/contracts/valid_pure.dart'],
      );
      expect(result.issues, isEmpty);
    });

    test('blocks contracts importing dart:io', () async {
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/contracts/violation_imports_dart_io.dart'],
      );
      expect(result.issues, hasLength(1));
      final issue = result.issues.single;
      expect(issue.severity, Severity.blocker);
      expect(issue.file, endsWith('violation_imports_dart_io.dart'));
      expect(issue.line, 4);
      expect(issue.ruleId, 'package_boundary/contracts_purity/dart_io');
    });

    test('blocks contracts importing from adapters', () async {
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/contracts/violation_imports_adapter.dart'],
      );
      expect(result.issues, hasLength(1));
      final issue = result.issues.single;
      expect(issue.severity, Severity.blocker);
      expect(issue.line, 6);
      expect(issue.ruleId, startsWith('package_boundary/contracts_purity/'));
    });

    test('passes for pure matching math', () async {
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/matching/valid_pure_math.dart'],
      );
      expect(result.issues, isEmpty);
    });

    test('blocks matching importing dart:io', () async {
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/matching/violation_imports_io.dart'],
      );
      expect(result.issues, hasLength(1));
      expect(result.issues.single.severity, Severity.blocker);
      expect(result.issues.single.line, 4);
      expect(
        result.issues.single.ruleId,
        'package_boundary/matching_purity/dart_io',
      );
    });

    test('blocks analyzers importing adapters', () async {
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/analyzers/foo/analyzer.dart'],
      );
      expect(result.issues, hasLength(1));
      final issue = result.issues.single;
      expect(issue.severity, Severity.blocker);
      expect(issue.line, 6);
      expect(issue.ruleId, startsWith('package_boundary/analyzers_isolation/'));
    });

    test('passes adapters that import dart:io and contracts', () async {
      // Adapters are the outer ring — no boundary forbids these imports.
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/adapters/foo/adapter.dart'],
      );
      expect(result.issues, isEmpty);
    });

    test('files outside any applies_to are skipped', () async {
      // Hypothetical bin/ file: no boundary applies → no issue regardless of
      // imports. We don't create the file; the analyzer simply skips.
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['bin/main.dart'],
      );
      expect(result.issues, isEmpty);
    });

    test('ruleId and suggestedFix are populated', () async {
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/matching/violation_imports_io.dart'],
      );
      final issue = result.issues.single;
      expect(issue.ruleId, isNotNull);
      expect(issue.suggestedFix, isNotNull);
      expect(issue.suggestedFix, contains('invert the dependency'));
    });

    test('description is surfaced in the issue message', () async {
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/contracts/violation_imports_dart_io.dart'],
      );
      expect(
        result.issues.single.message,
        contains('Contracts must remain pure'),
      );
    });

    test('blocks contracts re-exporting from adapters', () async {
      final result = await _run(
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/contracts/violation_reexports_io.dart'],
      );
      expect(result.issues, hasLength(1));
      final issue = result.issues.single;
      expect(issue.severity, Severity.blocker);
      expect(issue.line, 7);
      expect(
        issue.rule,
        contains('exports'),
        reason: 'rule text must distinguish exports from imports',
      );
    });

    test('multiple rules can apply to the same file independently', () async {
      // A single contracts/ file that violates BOTH dart:io and adapter
      // rules of the contracts_purity boundary (one boundary, two forbid
      // entries). The analyzer reports one issue per (file, forbid) pair.
      final tmpRel = 'lib/src/contracts/violation_double.dart';
      final tmpAbs = p.join(fixtureRoot, tmpRel);
      File(tmpAbs).writeAsStringSync('''
import 'dart:io';
import 'package:fixture_pkg/src/adapters/foo/adapter.dart';

class C {}
''');
      try {
        final result = await _run(
          config: config,
          projectRoot: fixtureRoot,
          files: [tmpRel],
        );
        expect(result.issues, hasLength(2));
        final lines = result.issues.map((i) => i.line).toSet();
        expect(lines, equals({1, 2}));
      } finally {
        File(tmpAbs).deleteSync();
      }
    });
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

Future<AnalysisResult> _run({
  required ProjectConfig config,
  required String projectRoot,
  required List<String> files,
}) async {
  final absolutePaths = files.map((f) => p.join(projectRoot, f)).toList();
  return PackageBoundaryAnalyzer().analyze(
    AnalyzerContext(
      filePaths: absolutePaths,
      projectRoot: projectRoot,
      config: config,
    ),
  );
}

ProjectConfig _withoutBoundaries(ProjectConfig original) {
  // Re-emit the same config with packageBoundaries cleared.
  return ProjectConfig(
    configVersion: original.configVersion,
    project: original.project,
    architecture: ArchitectureConfig(layers: original.architecture.layers),
    stateManagement: original.stateManagement,
    routing: original.routing,
    theme: original.theme,
    testing: original.testing,
    coverage: original.coverage,
    ticketSource: original.ticketSource,
    designSource: original.designSource,
    mr: original.mr,
    pipeline: original.pipeline,
    gates: original.gates,
    analyzers: original.analyzers,
    docs: original.docs,
  );
}

ProjectConfig _buildTestConfig() {
  return ProjectConfig(
    configVersion: '1.0.0',
    project: const ProjectInfo(
      packageName: 'fixture_pkg',
      pubspecPath: 'pubspec.yaml',
    ),
    architecture: const ArchitectureConfig(
      // At least one layer is required by the schema; the analyzer ignores it.
      layers: {
        'all': LayerConfig(paths: ['lib/']),
      },
      packageBoundaries: [
        PackageBoundary(
          name: 'contracts_purity',
          description:
              'Contracts must remain pure: only dart:core and pub-friendly '
              'annotation libraries; no I/O, no adapter imports.',
          appliesTo: ['lib/src/contracts/'],
          forbid: ['dart:io', 'package:fixture_pkg/src/adapters/'],
        ),
        PackageBoundary(
          name: 'matching_purity',
          description: 'Matching is a pure-math library — no I/O at all.',
          appliesTo: ['lib/src/matching/'],
          forbid: ['dart:io'],
        ),
        PackageBoundary(
          name: 'analyzers_isolation',
          description:
              'Analyzers consume contracts only; adapter dependencies invert '
              'the architecture.',
          appliesTo: ['lib/src/analyzers/'],
          forbid: ['package:fixture_pkg/src/adapters/'],
        ),
      ],
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
    coverage: const CoverageConfig(thresholds: {'all': 80}),
    ticketSource: const TicketSourceConfig(adapter: 'file'),
    designSource: const DesignSourceConfig(defaultAdapter: 'figma'),
    mr: const MrConfig(
      policy: 'single-commit-amend',
      branchPattern: 'feature/{ticket_id}-{slug}',
      prePush: ['dart format .', 'dart analyze'],
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
    analyzers: const AnalyzersConfig(),
  );
}
