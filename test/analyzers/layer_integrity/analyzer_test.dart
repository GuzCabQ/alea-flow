// Tests for the layer_integrity analyzer.
//
// Strategy: build a minimal [ProjectConfig] in code (no YAML loader needed yet),
// point at the fixtures under `test/analyzers/layer_integrity/fixtures/`, run
// the analyzer, and assert on the resulting issues.
//
// Each fixture .dart file documents its own expected outcome in a header
// comment ("Expected: N issue(s), severity ..., line X"). The assertions here
// must stay in sync with those comments.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('LayerIntegrityAnalyzer', () {
    late String fixtureRoot;
    late ProjectConfig config;

    setUp(() {
      // Resolve the fixture root relative to the test file's location.
      fixtureRoot = p.normalize(
        p.join(
          Directory.current.path,
          'test/analyzers/layer_integrity/fixtures',
        ),
      );
      config = _buildTestConfig();
    });

    test('emits no issues for a pure domain file', () async {
      final result = await _run(
        analyzer: LayerIntegrityAnalyzer(),
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/domain/valid_pure.dart'],
      );
      expect(result.issues, isEmpty);
    });

    test('blocks domain → infrastructure import', () async {
      final result = await _run(
        analyzer: LayerIntegrityAnalyzer(),
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/domain/violation_imports_infra.dart'],
      );
      expect(result.issues, hasLength(1));
      expect(result.issues.first.severity, Severity.blocker);
      expect(
        result.issues.first.file,
        endsWith('violation_imports_infra.dart'),
      );
      expect(result.issues.first.line, 4);
    });

    test('blocks domain → package:flutter import', () async {
      final result = await _run(
        analyzer: LayerIntegrityAnalyzer(),
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/domain/violation_imports_flutter.dart'],
      );
      expect(result.issues, hasLength(1));
      expect(result.issues.first.severity, Severity.blocker);
      expect(result.issues.first.line, 4);
    });

    test('blocks domain → presentation via relative import', () async {
      final result = await _run(
        analyzer: LayerIntegrityAnalyzer(),
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/domain/violation_imports_presentation_relative.dart'],
      );
      expect(result.issues, hasLength(1));
      expect(result.issues.first.severity, Severity.blocker);
      expect(result.issues.first.line, 6);
    });

    test('allows infrastructure → domain', () async {
      final result = await _run(
        analyzer: LayerIntegrityAnalyzer(),
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/infrastructure/valid_imports_domain.dart'],
      );
      expect(result.issues, isEmpty);
    });

    test('blocks infrastructure → presentation', () async {
      final result = await _run(
        analyzer: LayerIntegrityAnalyzer(),
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/infrastructure/violation_imports_presentation.dart'],
      );
      expect(result.issues, hasLength(1));
      expect(result.issues.first.severity, Severity.blocker);
      expect(result.issues.first.line, 4);
    });

    test('allows presentation → domain (asymmetric rule)', () async {
      final result = await _run(
        analyzer: LayerIntegrityAnalyzer(),
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/presentation/valid_imports_domain.dart'],
      );
      expect(result.issues, isEmpty);
    });

    test('blocks presentation → infrastructure', () async {
      final result = await _run(
        analyzer: LayerIntegrityAnalyzer(),
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/presentation/violation_imports_infra.dart'],
      );
      expect(result.issues, hasLength(1));
      expect(result.issues.first.severity, Severity.blocker);
      expect(result.issues.first.line, 4);
    });

    test('skips files that are not in any layer', () async {
      // A file outside lib/src/{domain,infra,presentation}/ should be ignored,
      // even if its imports would be forbidden in another layer.
      final result = await _run(
        analyzer: LayerIntegrityAnalyzer(),
        config: config,
        projectRoot: fixtureRoot,
        files: [
          // bin/ is outside any layer; pretend a hypothetical file exists there.
          // (No fixture needed — _run handles non-existent paths by passing them
          //  to the analyzer; the analyzer's _layerOf returns null and skips.)
          'bin/main.dart',
        ],
      );
      expect(result.issues, isEmpty);
    });

    test('rule_id and suggestedFix are populated', () async {
      final result = await _run(
        analyzer: LayerIntegrityAnalyzer(),
        config: config,
        projectRoot: fixtureRoot,
        files: ['lib/src/domain/violation_imports_infra.dart'],
      );
      final issue = result.issues.single;
      expect(issue.ruleId, isNotNull);
      expect(issue.ruleId, startsWith('layer_integrity/domain_imports_'));
      expect(issue.suggestedFix, isNotNull);
      expect(issue.suggestedFix, contains('invert the dependency'));
    });
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

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

ProjectConfig _buildTestConfig() {
  // Minimal config sufficient for this analyzer. Fields not consulted by
  // layer_integrity are left at their (required) defaults.
  return ProjectConfig(
    configVersion: '1.0.0',
    project: const ProjectInfo(
      packageName: 'sample_app',
      pubspecPath: 'pubspec.yaml',
    ),
    architecture: const ArchitectureConfig(
      layers: {
        'domain': LayerConfig(
          paths: ['lib/src/domain/'],
          forbidImports: [
            'package:flutter/',
            'package:sample_app/src/infrastructure/',
            'package:sample_app/src/presentation/',
          ],
        ),
        'infrastructure': LayerConfig(
          paths: ['lib/src/infrastructure/'],
          mayImport: ['domain'],
          forbidImports: ['package:sample_app/src/presentation/'],
        ),
        'presentation': LayerConfig(
          paths: ['lib/src/presentation/'],
          mayImport: ['domain'],
          forbidImports: [
            // Stricter than the legacy analyzer that motivated this
            // package, which allowed presentation → infrastructure. The new
            // analyzer enforces the canonical rule: "presentation consumes
            // domain only".
            'package:sample_app/src/infrastructure/',
          ],
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
    coverage: const CoverageConfig(
      thresholds: {'domain': 95, 'infrastructure': 80, 'presentation': 70},
    ),
    ticketSource: const TicketSourceConfig(adapter: 'asana'),
    designSource: const DesignSourceConfig(defaultAdapter: 'figma'),
    mr: const MrConfig(
      policy: 'single-commit-amend',
      branchPattern: 'feature/{ticket_id}-{slug}',
      prePush: ['dart format .', 'dart analyze', 'flutter test'],
    ),
    pipeline: const PipelineOpsConfig(
      defaultMode: 'guided',
      modesAvailable: ['guided', 'semi', 'auto'],
      costWarnUsd: 3.0,
      costHardStopUsd: 5.0,
      unreliableThreshold: UnreliableThresholdConfig(
        runsWindow: 5,
        badRunsRequired: 3,
        manualCorrectionsPerRun: 5,
      ),
    ),
    gates: const GatesConfig(
      perLayer: {
        'domain': ['domain'],
        'infrastructure': ['infra'],
        'presentation': ['presentation'],
        'bugfix': ['bugfix'],
      },
    ),
    analyzers: const AnalyzersConfig(),
  );
}
