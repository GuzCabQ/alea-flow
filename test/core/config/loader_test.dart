// Tests for the .alea.yaml loader.
//
// The canonical fixture is the sample_app config at config/examples/sample_app.yaml,
// which doubles as a parity check: every value declared there must round-trip
// through the loader without loss.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('loadProjectConfig — sample_app fixture', () {
    late ProjectConfig config;

    setUpAll(() {
      final fixturePath = p.normalize(
        p.join(Directory.current.path, 'config/examples/sample_app.yaml'),
      );
      config = parseProjectConfigYaml(File(fixturePath).readAsStringSync());
    });

    test('top-level required fields', () {
      expect(config.configVersion, '1.0.0');
      expect(config.project.packageName, 'sample_app');
      expect(config.project.pubspecPath, 'pubspec.yaml');
      expect(config.project.displayName, 'Sample App');
    });

    test('architecture has three layers with correct paths', () {
      expect(config.architecture.layers.keys.toSet(), {
        'domain',
        'infrastructure',
        'presentation',
      });
      expect(config.architecture.layers['domain']!.paths, ['lib/src/domain/']);
      expect(config.architecture.layers['infrastructure']!.paths, [
        'lib/src/infrastructure/',
      ]);
      expect(config.architecture.layers['presentation']!.paths, [
        'lib/src/presentation/',
      ]);
    });

    test('domain forbids flutter, infrastructure, presentation', () {
      final forbid = config.architecture.layers['domain']!.forbidImports;
      expect(forbid, contains('package:flutter/'));
      expect(forbid, contains('package:sample_app/src/infrastructure/'));
      expect(forbid, contains('package:sample_app/src/presentation/'));
    });

    test('state management is riverpod_manual', () {
      expect(config.stateManagement.style, 'riverpod_manual');
      expect(config.stateManagement.rules['forbid_codegen'], true);
      expect(config.stateManagement.rules['forbid_sealed_state'], true);
    });

    test('routing config', () {
      expect(config.routing.package, 'go_router');
      expect(config.routing.routerPath, 'lib/app/router/app_router.dart');
    });

    test('theme brand colors', () {
      expect(config.theme.path, 'lib/app/theme/app_theme.dart');
      expect(config.theme.brandColors['primary'], '#0066CC');
      expect(config.theme.brandColors['tertiary'], '#004C99');
      expect(config.theme.brandColors['secondary'], '#E0F5F5');
      expect(config.theme.brandColors['primary_light'], '#FCEDF6');
    });

    test('testing config', () {
      expect(config.testing.framework, 'flutter_test');
      expect(config.testing.fakesPath, 'test/fakes/');
      expect(config.testing.overrideTarget, 'repository');
      expect(config.testing.preferFakesOverMocks, true);
      expect(config.testing.missingTestSeverity, 'major');
    });

    test('coverage thresholds', () {
      expect(config.coverage.thresholds['domain'], 95);
      expect(config.coverage.thresholds['infrastructure'], 80);
      expect(config.coverage.thresholds['presentation'], 70);
    });

    test('ticket source is asana with PII sanitization on', () {
      expect(config.ticketSource.adapter, 'asana');
      expect(config.ticketSource.config['pii_sanitize'], true);
    });

    test('design source defaults to figma; image+markup stubbed', () {
      expect(config.designSource.defaultAdapter, 'figma');
      expect(config.designSource.adapters['figma']?.enabled, true);
      expect(config.designSource.adapters['image']?.enabled, false);
      expect(config.designSource.adapters['markup']?.enabled, false);
    });

    test('mr policy + pre-push commands', () {
      expect(config.mr.policy, 'single-commit-amend');
      expect(config.mr.prePush, [
        'dart format .',
        'dart analyze',
        'flutter test',
      ]);
    });

    test('pipeline operational settings', () {
      expect(config.pipeline.defaultMode, 'guided');
      expect(config.pipeline.modesAvailable, ['guided', 'semi', 'auto']);
      expect(config.pipeline.costWarnUsd, 3.0);
      expect(config.pipeline.costHardStopUsd, 5.0);
      expect(config.pipeline.unreliableThreshold.runsWindow, 5);
      expect(config.pipeline.unreliableThreshold.badRunsRequired, 3);
      expect(config.pipeline.unreliableThreshold.manualCorrectionsPerRun, 5);
    });

    test('gates per layer', () {
      expect(config.gates.perLayer['domain'], ['domain']);
      expect(config.gates.perLayer['infrastructure'], ['infra']);
      expect(config.gates.perLayer['presentation'], [
        'presentation',
        'fidelity',
      ]);
    });

    test('analyzers enabled list (snake_case)', () {
      // Confirms the rename from kebab to snake propagated through.
      expect(config.analyzers.enabled, contains('layer_integrity'));
      expect(config.analyzers.enabled, contains('visual_fidelity'));
      // None of the snake names should retain hyphens.
      for (final n in config.analyzers.enabled) {
        expect(n, isNot(contains('-')));
      }
    });
  });

  group('graph config parsing', () {
    test('parses graph.exclude and graph.roles; defaults when absent', () {
      const yaml = '''
config_version: "1"
project: { package_name: demo }
architecture:
  layers:
    presentation: { paths: [lib/src/presentation/] }
state_management: { style: riverpod }
routing: { package: go_router, router_path: lib/router.dart }
theme: { path: lib/theme/ }
testing: { framework: flutter_test, fakes_path: test/fakes/ }
coverage: { thresholds: { presentation: 80 } }
ticket_source: { adapter: markdown }
design_source: { default: none }
mr: { policy: pr, branch_pattern: "feat/{id}", pre_push: [] }
pipeline:
  default_mode: standard
  modes_available: [standard]
  cost_warn_usd: 1
  cost_hard_stop_usd: 5
  unreliable_threshold: { runs_window: 10, bad_runs_required: 3, manual_corrections_per_run: 5 }
gates: { per_layer: {} }
graph:
  exclude: ["lib/legacy/**"]
  roles: { MyBase: custom.role }
''';
      final c = parseProjectConfigYaml(yaml);
      expect(c.graph.exclude, contains('lib/legacy/**'));
      expect(
        c.graph.exclude,
        contains('**/*.g.dart'),
      ); // default still merged in
      expect(c.graph.roleOverrides['MyBase'], 'custom.role');
    });

    test('graph section absent → sensible defaults', () {
      const yaml = '''
config_version: "1"
project: { package_name: demo }
architecture:
  layers:
    presentation: { paths: [lib/src/presentation/] }
state_management: { style: riverpod }
routing: { package: go_router, router_path: lib/router.dart }
theme: { path: lib/theme/ }
testing: { framework: flutter_test, fakes_path: test/fakes/ }
coverage: { thresholds: { presentation: 80 } }
ticket_source: { adapter: markdown }
design_source: { default: none }
mr: { policy: pr, branch_pattern: "feat/{id}", pre_push: [] }
pipeline:
  default_mode: standard
  modes_available: [standard]
  cost_warn_usd: 1
  cost_hard_stop_usd: 5
  unreliable_threshold: { runs_window: 10, bad_runs_required: 3, manual_corrections_per_run: 5 }
gates: { per_layer: {} }
''';
      final c = parseProjectConfigYaml(yaml);
      expect(c.graph.exclude, contains('**/*.g.dart'));
      expect(c.graph.roleOverrides, isEmpty);
    });
  });

  group('loadProjectConfig — error handling', () {
    test('throws when YAML top-level is not a map', () {
      expect(
        () => parseProjectConfigYaml('- just-a-list\n'),
        throwsA(isA<ProjectConfigException>()),
      );
    });

    test('throws when required field is missing', () {
      expect(
        () => parseProjectConfigYaml('config_version: "1.0.0"\n'),
        throwsA(isA<ProjectConfigException>()),
      );
    });

    test('throws when a layer is malformed', () {
      const yaml = '''
config_version: "1.0.0"
project: { package_name: x }
architecture:
  layers:
    domain: "not-a-map"
state_management: { style: riverpod_manual }
routing: { package: go_router, router_path: x.dart }
theme: { path: x.dart }
testing: { framework: flutter_test, fakes_path: test/fakes/ }
coverage: { thresholds: {} }
ticket_source: { adapter: file }
design_source: { default: figma, adapters: {} }
mr: { policy: x, branch_pattern: x, pre_push: [] }
pipeline: { default_mode: guided, modes_available: [guided] }
gates: {}
''';
      expect(
        () => parseProjectConfigYaml(yaml),
        throwsA(isA<ProjectConfigException>()),
      );
    });
  });

  group('graph section (slice-2 WS-A)', () {
    const baseYaml = '''
config_version: "1"
project: { package_name: demo }
architecture:
  layers:
    presentation: { paths: [lib/src/presentation/] }
state_management: { style: riverpod }
routing: { package: go_router, router_path: lib/router.dart }
theme: { path: lib/theme/ }
testing: { framework: flutter_test, fakes_path: test/fakes/ }
coverage: { thresholds: { presentation: 80 } }
ticket_source: { adapter: markdown }
design_source: { default: none, adapters: {} }
mr: { policy: pr, branch_pattern: "feat/{id}", pre_push: [] }
pipeline:
  default_mode: standard
  modes_available: [standard]
  cost_warn_usd: 1
  cost_hard_stop_usd: 5
  unreliable_threshold: { runs_window: 10, bad_runs_required: 3, manual_corrections_per_run: 5 }
gates: { per_layer: {} }
''';

    test('parses graph.exclude (merged onto defaults) and graph.roles', () {
      final c = parseProjectConfigYaml('''
$baseYaml
graph:
  exclude: ["lib/legacy/**"]
  roles: { MyBase: custom.role }
''');
      expect(c.graph.exclude, contains('lib/legacy/**'));
      expect(
        c.graph.exclude,
        contains('**/*.g.dart'),
      ); // default still merged in
      expect(c.graph.roleOverrides['MyBase'], 'custom.role');
    });

    test('graph section absent → sensible defaults', () {
      final c = parseProjectConfigYaml(baseYaml);
      expect(c.graph.exclude, contains('**/*.g.dart'));
      expect(c.graph.roleOverrides, isEmpty);
    });
  });
}
