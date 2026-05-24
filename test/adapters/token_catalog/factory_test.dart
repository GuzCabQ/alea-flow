// Tests for the token-catalog factory.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

void main() {
  group('buildTokenCatalog', () {
    test('returns null when theme.token_catalog is absent', () {
      final config = _baseConfig();
      expect(
        buildTokenCatalog(config, projectRoot: Directory.current.path),
        isNull,
      );
    });

    test('selects DartSourceTokenCatalogAdapter when adapter=dart_source', () {
      final config = _baseConfig(
        tokenCatalog: const TokenCatalogConfig(
          adapter: 'dart_source',
          source:
              'test/adapters/token_catalog/dart_source/fixtures/'
              'sample_app/',
        ),
      );
      final catalog = buildTokenCatalog(
        config,
        projectRoot: Directory.current.path,
      );
      expect(catalog, isNotNull);
      expect(catalog!.sourceId, 'dart_source');
    });

    test('selects JsonTokenCatalogAdapter when adapter=json', () {
      final config = _baseConfig(
        tokenCatalog: const TokenCatalogConfig(
          adapter: 'json',
          source:
              'test/adapters/token_catalog/json/fixtures/design_tokens.json',
        ),
      );
      final catalog = buildTokenCatalog(
        config,
        projectRoot: Directory.current.path,
      );
      expect(catalog, isNotNull);
      expect(catalog!.sourceId, 'json');
    });

    test('accepts case-insensitive adapter names', () {
      final config = _baseConfig(
        tokenCatalog: const TokenCatalogConfig(
          adapter: 'Dart_Source',
          source: 'test/adapters/token_catalog/dart_source/fixtures/empty/',
        ),
      );
      expect(
        buildTokenCatalog(config, projectRoot: Directory.current.path),
        isNotNull,
      );
    });

    test('resolves relative source against projectRoot', () {
      final config = _baseConfig(
        tokenCatalog: const TokenCatalogConfig(
          adapter: 'dart_source',
          source:
              'test/adapters/token_catalog/dart_source/fixtures/'
              'sample_app/',
        ),
      );
      final catalog = buildTokenCatalog(
        config,
        projectRoot: Directory.current.path,
      );
      expect(catalog, isA<DesignTokenCatalog>());
      // Construction must not have thrown. Source resolution is verified end
      // to end via the parent test (the catalog is usable downstream).
    });

    test('throws when adapter is unknown', () {
      final config = _baseConfig(
        tokenCatalog: const TokenCatalogConfig(
          adapter: 'does_not_exist',
          source: 'whatever',
        ),
      );
      expect(
        () => buildTokenCatalog(config, projectRoot: Directory.current.path),
        throwsA(isA<ProjectConfigException>()),
      );
    });

    test('end-to-end: dart_source then JSON, both yield 5+ colors', () async {
      final dartConfig = _baseConfig(
        tokenCatalog: const TokenCatalogConfig(
          adapter: 'dart_source',
          source:
              'test/adapters/token_catalog/dart_source/fixtures/'
              'sample_app/',
        ),
      );
      final jsonConfig = _baseConfig(
        tokenCatalog: const TokenCatalogConfig(
          adapter: 'json',
          source:
              'test/adapters/token_catalog/json/fixtures/design_tokens.json',
        ),
      );

      final dartCatalog = buildTokenCatalog(
        dartConfig,
        projectRoot: Directory.current.path,
      )!;
      final jsonCatalog = buildTokenCatalog(
        jsonConfig,
        projectRoot: Directory.current.path,
      )!;

      final dartColors = await dartCatalog.colors();
      final jsonColors = await jsonCatalog.colors();

      expect(dartColors.length, 5);
      expect(jsonColors.length, greaterThanOrEqualTo(5));
    });

    test(
      'supportedTokenCatalogAdapters lists exactly the impls we support',
      () {
        expect(supportedTokenCatalogAdapters, ['dart_source', 'json']);
      },
    );
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

ProjectConfig _baseConfig({TokenCatalogConfig? tokenCatalog}) => ProjectConfig(
  configVersion: '1.0.0',
  project: const ProjectInfo(packageName: 'alea', pubspecPath: 'pubspec.yaml'),
  architecture: const ArchitectureConfig(
    layers: {
      'package': LayerConfig(paths: ['lib/']),
    },
  ),
  stateManagement: const StateManagementConfig(style: 'none'),
  routing: const RoutingConfig(package: 'none', routerPath: ''),
  theme: ThemeConfig(path: 'lib/src/theme/', tokenCatalog: tokenCatalog),
  testing: const TestingConfig(
    framework: 'dart_test',
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
    costWarnUsd: 0,
    costHardStopUsd: 0,
    unreliableThreshold: UnreliableThresholdConfig(
      runsWindow: 5,
      badRunsRequired: 3,
      manualCorrectionsPerRun: 5,
    ),
  ),
  gates: const GatesConfig(perLayer: {}),
  analyzers: const AnalyzersConfig(),
);
