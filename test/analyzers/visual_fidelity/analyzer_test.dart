// Tests for the visual_fidelity analyzer.
//
// Strategy: synthetic fixture .dart files under fixtures/, each documenting
// its expected issues in a header comment. A minimal ProjectConfig is built
// in-code (same approach as layer_integrity tests). For the figma-escalation
// test, a fake NDS document at fixtures/nds_runs/figma_run/figma/nds.yaml
// supplies `document.source.adapter: figma`.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('VisualFidelityAnalyzer', () {
    late String fixtureRoot;
    late ProjectConfig config;

    setUp(() {
      fixtureRoot = p.normalize(
        p.join(
          Directory.current.path,
          'test/analyzers/visual_fidelity/fixtures',
        ),
      );
      config = _buildTestConfig();
    });

    // ── missing_image_fit ────────────────────────────────────────────────

    test('flags every image-widget call without fit:', () async {
      final result = await _run(
        files: ['violation_missing_fit.dart'],
        config: config,
        projectRoot: fixtureRoot,
      );
      final fit = _byRule(result, 'visual_fidelity/missing_image_fit');
      expect(fit, hasLength(3));
      for (final issue in fit) {
        // Advisory (non-blocking): a missing `fit:` is a layout/fidelity
        // concern, not broken UX or a runtime crash. See VF-3 calibration.
        expect(issue.severity, Severity.major);
      }
      expect(fit.map((i) => i.line).toSet(), {15, 16, 17});
    });

    test('emits no missing_image_fit issues when fit: is set', () async {
      final result = await _run(
        files: ['valid_with_fit.dart'],
        config: config,
        projectRoot: fixtureRoot,
      );
      expect(_byRule(result, 'visual_fidelity/missing_image_fit'), isEmpty);
    });

    // ── emoji_as_icon ────────────────────────────────────────────────────

    test('flags Text("emoji") as major without NDS', () async {
      final result = await _run(
        files: ['violation_emoji_as_icon.dart'],
        config: config,
        projectRoot: fixtureRoot,
        runDirectory: null,
      );
      final emoji = _byRule(result, 'visual_fidelity/emoji_as_icon');
      expect(emoji, hasLength(2));
      for (final issue in emoji) {
        expect(issue.severity, Severity.major);
      }
    });

    test(
      'escalates emoji_as_icon to critical when NDS source is figma',
      () async {
        final ndsRunDir = p.join(fixtureRoot, 'nds_runs', 'figma_run');
        final result = await _run(
          files: ['violation_emoji_as_icon.dart'],
          config: config,
          projectRoot: fixtureRoot,
          runDirectory: ndsRunDir,
        );
        final emoji = _byRule(result, 'visual_fidelity/emoji_as_icon');
        expect(emoji, hasLength(2));
        for (final issue in emoji) {
          expect(issue.severity, Severity.critical);
        }
      },
    );

    test('does not flag emoji embedded in real text', () async {
      final result = await _run(
        files: ['valid_intentional_emoji.dart'],
        config: config,
        projectRoot: fixtureRoot,
      );
      expect(_byRule(result, 'visual_fidelity/emoji_as_icon'), isEmpty);
    });

    // ── button_without_content ───────────────────────────────────────────

    test('flags buttons with no visible content', () async {
      final result = await _run(
        files: ['violation_empty_button.dart'],
        config: config,
        projectRoot: fixtureRoot,
      );
      final empty = _byRule(result, 'visual_fidelity/button_without_content');
      expect(empty, hasLength(2));
      for (final issue in empty) {
        expect(issue.severity, Severity.blocker);
      }
    });

    test('does not flag buttons with Text, Icon, or icon+label', () async {
      final result = await _run(
        files: ['valid_button_with_content.dart'],
        config: config,
        projectRoot: fixtureRoot,
      );
      expect(
        _byRule(result, 'visual_fidelity/button_without_content'),
        isEmpty,
      );
    });

    // ── asset_path_broken ────────────────────────────────────────────────

    test('flags asset paths that do not exist (no TODO escape)', () async {
      final result = await _run(
        files: ['violation_broken_asset.dart'],
        config: config,
        projectRoot: fixtureRoot,
      );
      final broken = _byRule(result, 'visual_fidelity/asset_path_broken');
      expect(broken, hasLength(3));
      for (final issue in broken) {
        expect(issue.severity, Severity.critical);
      }
    });

    test('does not flag existing assets', () async {
      final result = await _run(
        files: ['valid_existing_asset.dart'],
        config: config,
        projectRoot: fixtureRoot,
      );
      expect(_byRule(result, 'visual_fidelity/asset_path_broken'), isEmpty);
    });

    // ── Issue shape ──────────────────────────────────────────────────────

    test(
      'every issue includes file, line, rule, ruleId, suggestedFix',
      () async {
        final result = await _run(
          files: ['violation_missing_fit.dart'],
          config: config,
          projectRoot: fixtureRoot,
        );
        for (final issue in result.issues) {
          expect(issue.file, isNotEmpty);
          expect(issue.line, isNotNull);
          expect(issue.rule, isNotEmpty);
          expect(issue.ruleId, isNotNull);
          expect(issue.ruleId, startsWith('visual_fidelity/'));
          expect(issue.suggestedFix, isNotNull);
        }
      },
    );
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

Future<AnalysisResult> _run({
  required List<String> files,
  required ProjectConfig config,
  required String projectRoot,
  String? runDirectory,
}) {
  final absolutePaths = files.map((f) => p.join(projectRoot, f)).toList();
  return VisualFidelityAnalyzer().analyze(
    AnalyzerContext(
      filePaths: absolutePaths,
      projectRoot: projectRoot,
      runDirectory: runDirectory,
      config: config,
    ),
  );
}

List<AnalysisIssue> _byRule(AnalysisResult result, String ruleId) =>
    result.issues.where((i) => i.ruleId == ruleId).toList();

ProjectConfig _buildTestConfig() => ProjectConfig(
  configVersion: '1.0.0',
  project: const ProjectInfo(
    packageName: 'sample_app',
    pubspecPath: 'pubspec.yaml',
  ),
  architecture: const ArchitectureConfig(
    layers: {
      'presentation': LayerConfig(paths: ['lib/src/presentation/']),
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
  coverage: const CoverageConfig(thresholds: {'presentation': 70}),
  ticketSource: const TicketSourceConfig(adapter: 'file'),
  designSource: const DesignSourceConfig(defaultAdapter: 'figma'),
  mr: const MrConfig(
    policy: 'single-commit-amend',
    branchPattern: 'feature/{ticket_id}',
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
  gates: const GatesConfig(
    perLayer: {
      'presentation': ['presentation'],
    },
  ),
  analyzers: const AnalyzersConfig(),
);
