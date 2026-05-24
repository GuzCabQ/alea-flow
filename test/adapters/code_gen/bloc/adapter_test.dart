import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

import '../_helpers.dart';

void main() {
  group('BlocCodeGen', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('alea_bloc_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test(
      'presentation layer emits state + event + bloc + screen at configured paths',
      () async {
        final config = buildScaffoldTestConfig(
          packageName: 'demo',
          stateManagementStyle: 'bloc',
        );
        final adapter = BlocCodeGen();
        final plan = await adapter.generate(
          CodeGenRequest(
            layer: CodeGenLayer.presentation,
            spec: const {
              'feature': {'name': 'profile'},
            },
            projectRoot: root.path,
            config: config,
          ),
        );
        expect(plan.files.map((f) => f.relativePath).toSet(), {
          'lib/src/domain/feature/profile/profile_state.dart',
          'lib/src/domain/feature/profile/profile_event.dart',
          'lib/src/domain/feature/profile/profile_bloc.dart',
          'lib/src/presentation/feature/profile/profile_screen.dart',
        });
      },
    );

    test(
      'identical CodeGenRequest with bloc adapter produces a different file set '
      'from riverpod_manual (config-driven swap, no orchestration change)',
      () async {
        final config = buildScaffoldTestConfig(packageName: 'demo');
        final spec = const {
          'feature': {'name': 'auth'},
        };

        final blocPlan = await BlocCodeGen().generate(
          CodeGenRequest(
            layer: CodeGenLayer.presentation,
            spec: spec,
            projectRoot: root.path,
            config: config,
          ),
        );
        final riverpodPlan = await RiverpodManualCodeGen().generate(
          CodeGenRequest(
            layer: CodeGenLayer.presentation,
            spec: spec,
            projectRoot: root.path,
            config: config,
          ),
        );

        final blocFiles = blocPlan.files.map((f) => f.relativePath).toSet();
        final riverpodFiles = riverpodPlan.files
            .map((f) => f.relativePath)
            .toSet();

        // Bloc adds event + bloc; Riverpod adds notifier.
        expect(
          blocFiles,
          contains('lib/src/domain/feature/auth/auth_bloc.dart'),
        );
        expect(
          riverpodFiles,
          contains('lib/src/domain/feature/auth/auth_notifier.dart'),
        );
        // Same projectRoot, same spec — only the adapter changed.
        expect(blocPlan.adapterName, 'bloc');
        expect(riverpodPlan.adapterName, 'riverpod_manual');
      },
    );

    test('changing architecture.layers.domain.paths changes generated paths '
        'without touching templates', () async {
      // Custom layer paths: `lib/features/<feature>/data` etc.
      final config = ProjectConfig(
        configVersion: '1.0.0',
        project: const ProjectInfo(
          packageName: 'demo',
          pubspecPath: 'pubspec.yaml',
        ),
        architecture: const ArchitectureConfig(
          layers: {
            'domain': LayerConfig(paths: ['lib/features_data/']),
            'infrastructure': LayerConfig(paths: ['lib/features_infra/']),
            'presentation': LayerConfig(paths: ['lib/features_ui/']),
          },
        ),
        stateManagement: const StateManagementConfig(style: 'bloc'),
        routing: const RoutingConfig(package: 'none', routerPath: ''),
        theme: const ThemeConfig(path: ''),
        testing: const TestingConfig(
          framework: 'flutter_test',
          fakesPath: 'test/fakes/',
        ),
        coverage: const CoverageConfig(thresholds: {'domain': 80}),
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
        analyzers: const AnalyzersConfig(),
      );
      final plan = await BlocCodeGen().generate(
        CodeGenRequest(
          layer: CodeGenLayer.presentation,
          spec: const {
            'feature': {'name': 'auth'},
          },
          projectRoot: root.path,
          config: config,
        ),
      );
      expect(
        plan.files.map((f) => f.relativePath),
        containsAll([
          'lib/features_data/feature/auth/auth_bloc.dart',
          'lib/features_ui/feature/auth/auth_screen.dart',
        ]),
      );
    });

    test(
      'generated bloc.dart references the right import path of the state',
      () async {
        final config = buildScaffoldTestConfig(
          packageName: 'demo',
          stateManagementStyle: 'bloc',
        );
        final plan = await BlocCodeGen().generate(
          CodeGenRequest(
            layer: CodeGenLayer.presentation,
            spec: const {
              'feature': {'name': 'profile'},
            },
            projectRoot: root.path,
            config: config,
          ),
        );
        final screen = plan.files.firstWhere(
          (f) => f.relativePath.endsWith('profile_screen.dart'),
        );
        // Cross-layer relative import path from presentation/ to domain/:
        expect(
          screen.content,
          contains("import '../../../domain/feature/profile/profile_bloc.dart"),
        );
      },
    );
  });
}
