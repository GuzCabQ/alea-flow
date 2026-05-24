// Tests for WidgetInventoryAnalyzer.

import 'dart:convert';
import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('WidgetInventoryAnalyzer', () {
    late String fixtureRoot;

    setUp(() {
      fixtureRoot = p.normalize(
        p.join(Directory.current.path, 'test/inventory/fixtures/widgets'),
      );
    });

    test('emits no issues — analyzer is artifact-producing only', () async {
      final tmpRun = Directory.systemTemp.createTempSync('alea_wi_an_');
      addTearDown(() => tmpRun.deleteSync(recursive: true));

      final result = await WidgetInventoryAnalyzer().analyze(
        _ctx(fixtureRoot, tmpRun),
      );
      expect(result.issues, isEmpty);
    });

    test('writes widget_inventory.json under runDirectory', () async {
      final tmpRun = Directory.systemTemp.createTempSync('alea_wi_artifact_');
      addTearDown(() => tmpRun.deleteSync(recursive: true));

      await WidgetInventoryAnalyzer().analyze(_ctx(fixtureRoot, tmpRun));
      final file = File(p.join(tmpRun.path, 'widget_inventory.json'));
      expect(file.existsSync(), isTrue);

      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect(json['source'], 'dart_source');
      expect((json['entries'] as List), hasLength(6));
    });

    test('emits journal events with widget count', () async {
      final tmpRun = Directory.systemTemp.createTempSync('alea_wi_journal_');
      addTearDown(() => tmpRun.deleteSync(recursive: true));
      final journal = JsonlRunJournal.forRunDirectory(tmpRun.path);

      await WidgetInventoryAnalyzer().analyze(
        _ctx(fixtureRoot, tmpRun, journal: journal),
      );
      final events = await journal.readAll().toList();
      await journal.close();

      final completed = events.firstWhere(
        (e) =>
            e.source == 'analyzer:widget_inventory' &&
            e.kind == JournalEventKind.completed,
      );
      expect(completed.payload['widgets'], 6);
    });

    test(
      'absent options falls back to scanning every architecture layer path',
      () async {
        final tmpRun = Directory.systemTemp.createTempSync('alea_wi_layers_');
        addTearDown(() => tmpRun.deleteSync(recursive: true));

        await WidgetInventoryAnalyzer().analyze(_ctx(fixtureRoot, tmpRun));
        final json =
            jsonDecode(
                  File(
                    p.join(tmpRun.path, 'widget_inventory.json'),
                  ).readAsStringSync(),
                )
                as Map<String, Object?>;
        expect((json['entries'] as List), isNotEmpty);
      },
    );

    test('explicit token_classes restricts which references count', () async {
      final tmpRun = Directory.systemTemp.createTempSync('alea_wi_restrict_');
      addTearDown(() => tmpRun.deleteSync(recursive: true));

      await WidgetInventoryAnalyzer().analyze(
        _ctx(
          fixtureRoot,
          tmpRun,
          analyzerOptions: {
            'widget_inventory': {
              'token_classes': ['StyleColors'], // ignore Fonts and Size
            },
          },
        ),
      );
      final json =
          jsonDecode(
                File(
                  p.join(tmpRun.path, 'widget_inventory.json'),
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final card = (json['entries'] as List)
          .cast<Map<String, Object?>>()
          .firstWhere((e) => e['class_name'] == 'CardSummaryComponent');
      final tokens = (card['tokens_used'] as List).cast<String>();
      expect(tokens.every((t) => t.startsWith('StyleColors.')), isTrue);
    });
  });
}

AnalyzerContext _ctx(
  String fixtureRoot,
  Directory runDir, {
  RunJournal? journal,
  Map<String, Map<String, Object?>> analyzerOptions = const {},
}) {
  return AnalyzerContext(
    filePaths: const [],
    projectRoot: fixtureRoot,
    runDirectory: runDir.path,
    config: ProjectConfig(
      configVersion: '1.0.0',
      project: const ProjectInfo(
        packageName: 'fixture_pkg',
        pubspecPath: 'pubspec.yaml',
      ),
      architecture: const ArchitectureConfig(
        layers: {
          // The fixture root IS the layer path, relative to projectRoot.
          // ANY existing directory under projectRoot will do here — the
          // analyzer normalizes to absolute and skips missing entries.
          'package': LayerConfig(paths: ['']),
        },
      ),
      stateManagement: const StateManagementConfig(style: 'none'),
      routing: const RoutingConfig(package: 'none', routerPath: ''),
      theme: const ThemeConfig(path: ''),
      testing: const TestingConfig(
        framework: 'dart_test',
        fakesPath: 'test/fakes/',
      ),
      coverage: const CoverageConfig(thresholds: {'package': 0}),
      ticketSource: const TicketSourceConfig(adapter: 'file'),
      designSource: const DesignSourceConfig(defaultAdapter: 'figma'),
      mr: const MrConfig(
        policy: 'single-commit-amend',
        branchPattern: 'feature/{ticket_id}-{slug}',
        prePush: [],
      ),
      pipeline: const PipelineOpsConfig(
        defaultMode: 'guided',
        modesAvailable: ['guided'],
        costWarnUsd: 0,
        costHardStopUsd: 0,
        unreliableThreshold: UnreliableThresholdConfig(
          runsWindow: 5,
          badRunsRequired: 3,
          manualCorrectionsPerRun: 5,
        ),
      ),
      gates: const GatesConfig(perLayer: {}),
      analyzers: AnalyzersConfig(options: analyzerOptions),
    ),
    journal: journal,
  );
}
