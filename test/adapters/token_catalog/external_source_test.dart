// External token catalog source — ADR-0011 Part 2.
//
// The factory at `lib/src/adapters/token_catalog/factory.dart` resolves
// `theme.token_catalog.source` against the project root, so a path like
// `../design_system/lib/` resolves to a sibling Dart package in a monorepo.
// This test pins that behavior and verifies (a) the catalog returned by
// the factory loads tokens from the sibling package, (b) an external source
// whose target doesn't exist surfaces a clear ProjectConfigException at
// factory time, and (c) intra-project sources stay lazy.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('token catalog with external monorepo source', () {
    test(
      'feature package resolves catalog from sibling design_system',
      () async {
        final monorepo = Directory.systemTemp.createTempSync('alea_mono_');
        addTearDown(() => monorepo.deleteSync(recursive: true));

        // packages/design_system/lib/colors.dart — the shared catalog.
        final dsLib = Directory(
          p.join(monorepo.path, 'packages/design_system/lib'),
        )..createSync(recursive: true);
        File(p.join(dsLib.path, 'colors.dart')).writeAsStringSync('''
class AppColors {
  static const Color primary = Color(0xFFDA1884);
  static const Color secondary = Color(0xFFE0F5F5);
  static const Color tertiary = Color(0xFF4A0E2B);
}
''');

        // packages/feature_wallet/ — the consumer that points at the sibling.
        final feature = Directory(
          p.join(monorepo.path, 'packages/feature_wallet'),
        )..createSync(recursive: true);
        Directory(
          p.join(feature.path, 'lib/src/domain'),
        ).createSync(recursive: true);

        final config = _config(
          tokenCatalog: const TokenCatalogConfig(
            adapter: 'dart_source',
            source: '../design_system/lib/',
            conventions: {'color_class': 'AppColors'},
          ),
        );

        final catalog = buildTokenCatalog(config, projectRoot: feature.path);
        expect(
          catalog,
          isNotNull,
          reason: 'factory should return a catalog when spec is present',
        );

        final colors = await catalog!.colors();
        final names = colors.map((c) => c.qualifiedName).toSet();
        expect(names, contains('AppColors.primary'));
        expect(names, contains('AppColors.secondary'));
        expect(names, contains('AppColors.tertiary'));
      },
    );

    test(
      'external source pointing at missing path throws clear error',
      () async {
        final feature = Directory.systemTemp.createTempSync(
          'alea_mono_missing_',
        );
        addTearDown(() => feature.deleteSync(recursive: true));

        final config = _config(
          tokenCatalog: const TokenCatalogConfig(
            adapter: 'dart_source',
            source: '../does_not_exist/lib/',
          ),
        );

        expect(
          () => buildTokenCatalog(config, projectRoot: feature.path),
          throwsA(
            isA<ProjectConfigException>().having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('does not exist'),
                contains('does_not_exist'),
                contains('ADR-0011'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'intra-project source stays lazy (no eager existence check)',
      () async {
        // Within-project paths must NOT be validated at factory time — that
        // preserves the existing contract (first I/O on first method call).
        final feature = Directory.systemTemp.createTempSync('alea_mono_intra_');
        addTearDown(() => feature.deleteSync(recursive: true));

        // Note: lib/src/theme/ does NOT exist on disk inside `feature`.
        // Factory must still return a catalog (lazy); failure would only
        // happen on catalog.colors().
        final config = _config(
          tokenCatalog: const TokenCatalogConfig(
            adapter: 'dart_source',
            source: 'lib/src/theme/',
          ),
        );

        // Should NOT throw at factory time.
        final catalog = buildTokenCatalog(config, projectRoot: feature.path);
        expect(catalog, isNotNull);
      },
    );
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

ProjectConfig _config({TokenCatalogConfig? tokenCatalog}) => ProjectConfig(
  configVersion: '1.0.0',
  project: const ProjectInfo(
    packageName: 'feature_wallet',
    pubspecPath: 'pubspec.yaml',
  ),
  architecture: const ArchitectureConfig(
    layers: {
      'domain': LayerConfig(paths: ['lib/src/domain/']),
    },
  ),
  stateManagement: const StateManagementConfig(style: 'riverpod_manual'),
  routing: const RoutingConfig(package: 'none', routerPath: ''),
  theme: ThemeConfig(path: 'lib/src/theme/', tokenCatalog: tokenCatalog),
  testing: const TestingConfig(
    framework: 'dart_test',
    fakesPath: 'test/fakes/',
  ),
  coverage: const CoverageConfig(thresholds: {'domain': 80}),
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
