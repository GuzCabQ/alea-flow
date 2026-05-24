// Tests for the catalog-driven rules of VisualFidelityAnalyzer.
//
// Strategy: build a minimal in-memory DesignTokenCatalog, point the analyzer
// at a synthetic NDS document in fixtures/nds_catalog/, run, and assert on
// the resulting issues + journal events.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../resolvers/_fake_catalog.dart';

void main() {
  group('VisualFidelityAnalyzer — catalog rules', () {
    late String fixtureRoot;
    late ProjectConfig config;
    late FakeTokenCatalog catalog;

    setUp(() {
      fixtureRoot = p.normalize(
        p.join(
          Directory.current.path,
          'test/analyzers/visual_fidelity/fixtures/nds_catalog',
        ),
      );
      config = _buildConfig();
      catalog = FakeTokenCatalog(
        colorList: const [
          ColorToken(qualifiedName: 'palette.brand60', argb: 0xFFDA1884),
          ColorToken(qualifiedName: 'palette.brand40', argb: 0xFF4A0E2B),
          ColorToken(qualifiedName: 'palette.secondary', argb: 0xFFE0F5F5),
          ColorToken(qualifiedName: 'palette.text', argb: 0xFF1A1A1A),
        ],
        typographyList: const [
          TypographyToken(
            qualifiedName: 'typography.body2',
            fontSize: 16,
            fontWeight: 600,
          ),
          TypographyToken(
            qualifiedName: 'typography.headline',
            fontSize: 24,
            fontWeight: 700,
          ),
        ],
      );
    });

    test('NDS color outside the catalog → blocker color_not_in_catalog with '
        'suggestedFix naming the closest token + ΔE', () async {
      final issues = await _run(config, fixtureRoot, catalog: catalog);
      final blocker = issues.firstWhere(
        (i) => i.ruleId == 'visual_fidelity/color_not_in_catalog',
      );
      expect(blocker.severity, Severity.blocker);
      expect(blocker.rule, contains('rogue_background.background.value'));
      // Closest token mentioned with ΔE.
      expect(blocker.suggestedFix, contains('palette.'));
      expect(blocker.message, contains('ΔE'));
    });

    test('exact catalog match emits no color issue for that element', () async {
      final issues = await _run(config, fixtureRoot, catalog: catalog);
      final blockedIds = issues
          .where((i) => i.ruleId?.startsWith('visual_fidelity/color_') ?? false)
          .map((i) => i.rule)
          .toList();
      // cta_button.background.value (#DA1884) and title_text.style.color
      // (#1A1A1A) both exactly match the catalog — no blocker for them.
      expect(
        blockedIds.where((r) => r.contains('cta_button.background.value')),
        isEmpty,
      );
      expect(
        blockedIds.where((r) => r.contains('title_text.style.color')),
        isEmpty,
      );
    });

    test('NDS (size,weight) outside the catalog → blocker '
        'typography_not_in_catalog', () async {
      final issues = await _run(config, fixtureRoot, catalog: catalog);
      final blocker = issues.firstWhere(
        (i) => i.ruleId == 'visual_fidelity/typography_not_in_catalog',
      );
      expect(blocker.severity, Severity.blocker);
      expect(blocker.rule, contains('rogue_typography'));
    });

    test('exact (16, w600) → no typography issue for title_text', () async {
      final issues = await _run(config, fixtureRoot, catalog: catalog);
      final typoIssues = issues
          .where(
            (i) => i.ruleId?.startsWith('visual_fidelity/typography_') ?? false,
          )
          .where((i) => i.rule.contains('title_text'))
          .toList();
      expect(typoIssues, isEmpty);
    });

    test('analyzer degrades silently when no catalog is injected', () async {
      // Same NDS, no catalog: AST-only rules still run (irrelevant here —
      // no .dart files passed), but no catalog-driven issues.
      final issues = await _run(config, fixtureRoot, catalog: null);
      expect(
        issues.where(
          (i) => i.ruleId?.startsWith('visual_fidelity/color_') ?? false,
        ),
        isEmpty,
      );
      expect(
        issues.where(
          (i) => i.ruleId?.startsWith('visual_fidelity/typography_') ?? false,
        ),
        isEmpty,
      );
    });

    test(
      'journal records one check event per resolved color/typography',
      () async {
        final tmpDir = Directory.systemTemp.createTempSync('alea_vf_journal_');
        addTearDown(() => tmpDir.deleteSync(recursive: true));
        final journal = JsonlRunJournal.forRunDirectory(tmpDir.path);

        await VisualFidelityAnalyzer().analyze(
          AnalyzerContext(
            filePaths: const [],
            projectRoot: fixtureRoot,
            runDirectory: fixtureRoot,
            config: config,
            tokenCatalog: catalog,
            journal: journal,
          ),
        );
        final events = await journal.readAll().toList();
        await journal.close();

        final checkEvents = events
            .where(
              (e) =>
                  e.source == 'analyzer:visual_fidelity' &&
                  e.kind == JournalEventKind.check,
            )
            .toList();
        // 1 color check per (element, field) where the field is non-null:
        //   cta_button.background.value
        //   title_text.style.color
        //   rogue_background.background.value
        // 2 typography checks: title_text, rogue_typography.
        expect(checkEvents, hasLength(5));
        // Every event carries verdict + recommended (or candidates).
        for (final e in checkEvents) {
          expect(e.payload.containsKey('verdict'), isTrue);
        }
      },
    );

    test(
      'options.check_typography=false disables typography rule only',
      () async {
        final cfg = _buildConfig(
          analyzerOptions: const {
            'visual_fidelity': {'check_typography': false},
          },
        );
        final issues = await _run(cfg, fixtureRoot, catalog: catalog);
        expect(
          issues.where(
            (i) => i.ruleId?.startsWith('visual_fidelity/typography_') ?? false,
          ),
          isEmpty,
        );
        expect(
          issues.where(
            (i) => i.ruleId?.startsWith('visual_fidelity/color_') ?? false,
          ),
          isNotEmpty,
        );
      },
    );
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

Future<List<AnalysisIssue>> _run(
  ProjectConfig config,
  String fixtureRoot, {
  required FakeTokenCatalog? catalog,
}) async {
  final result = await VisualFidelityAnalyzer().analyze(
    AnalyzerContext(
      filePaths: const [],
      projectRoot: fixtureRoot,
      runDirectory: fixtureRoot,
      config: config,
      tokenCatalog: catalog,
    ),
  );
  return result.issues;
}

ProjectConfig _buildConfig({
  Map<String, Map<String, Object?>> analyzerOptions = const {},
}) => ProjectConfig(
  configVersion: '1.0.0',
  project: const ProjectInfo(
    packageName: 'fixture_pkg',
    pubspecPath: 'pubspec.yaml',
  ),
  architecture: const ArchitectureConfig(
    layers: {
      'package': LayerConfig(paths: ['lib/']),
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
  coverage: const CoverageConfig(thresholds: {'package': 80}),
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
    costWarnUsd: 3,
    costHardStopUsd: 5,
    unreliableThreshold: UnreliableThresholdConfig(
      runsWindow: 5,
      badRunsRequired: 3,
      manualCorrectionsPerRun: 5,
    ),
  ),
  gates: const GatesConfig(perLayer: {}),
  analyzers: AnalyzersConfig(options: analyzerOptions),
);
