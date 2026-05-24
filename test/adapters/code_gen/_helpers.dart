// Shared helpers for code_gen adapter tests.

import 'package:alea_flow/alea_flow.dart';

ProjectConfig buildScaffoldTestConfig({
  required String packageName,
  String stateManagementStyle = 'riverpod_manual',
}) {
  return ProjectConfig(
    configVersion: '1.0.0',
    project: ProjectInfo(packageName: packageName, pubspecPath: 'pubspec.yaml'),
    architecture: const ArchitectureConfig(
      layers: {
        'domain': LayerConfig(
          paths: ['lib/src/domain/'],
          forbidImports: ['package:flutter/'],
        ),
        'infrastructure': LayerConfig(
          paths: ['lib/src/infrastructure/'],
          mayImport: ['domain'],
        ),
        'presentation': LayerConfig(
          paths: ['lib/src/presentation/'],
          mayImport: ['domain'],
        ),
      },
    ),
    stateManagement: StateManagementConfig(style: stateManagementStyle),
    routing: const RoutingConfig(
      package: 'go_router',
      routerPath: 'lib/src/app/router.dart',
    ),
    theme: const ThemeConfig(path: 'lib/src/theme/'),
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
}
