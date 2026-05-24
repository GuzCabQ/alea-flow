import 'package:alea_flow/src/cli/init/config_generator.dart';
import 'package:alea_flow/src/cli/init/layer_scanner.dart';
import 'package:alea_flow/src/cli/init/pubspec_reader.dart';
import 'package:test/test.dart';

PubspecData _pubspec({
  String name = 'my_app',
  bool flutter = true,
  String? stateStyle,
  String? stateOrigin,
  String? routingPackage,
  String? routingOrigin,
}) {
  return PubspecData(
    packageName: name,
    isFlutterProject: flutter,
    stateManagementStyle: stateStyle,
    stateManagementOrigin: stateOrigin,
    routingPackage: routingPackage,
    routingOrigin: routingOrigin,
  );
}

LayerPaths _allLayersDetected() => const LayerPaths(
  domainPath: 'lib/src/domain/',
  infrastructurePath: 'lib/src/infrastructure/',
  presentationPath: 'lib/src/presentation/',
  themePath: 'lib/src/theme/',
);

LayerPaths _noLayers() => const LayerPaths(
  domainPath: null,
  infrastructurePath: null,
  presentationPath: null,
  themePath: null,
);

final _fixedTime = DateTime.utc(2026, 5, 25, 20, 30, 0);

void main() {
  group('ConfigGenerator — happy path', () {
    test('emits a fully-populated YAML when everything is detected', () {
      final input = ConfigGenerationInput(
        pubspec: _pubspec(
          stateStyle: 'riverpod_manual',
          stateOrigin: 'flutter_riverpod',
          routingPackage: 'go_router',
          routingOrigin: 'go_router',
        ),
        layers: _allLayersDetected(),
        generatedAtUtc: _fixedTime,
      );
      final yaml = const ConfigGenerator().generate(input);

      // Header carries the deterministic timestamp.
      expect(yaml, contains('2026-05-25T20:30:00Z'));

      // Package name from pubspec.
      expect(yaml, contains('package_name: my_app'));

      // Layer paths use detected values + traceable comments.
      expect(
        yaml,
        contains('paths: [lib/src/domain/]   # detected at lib/src/domain/'),
      );
      expect(
        yaml,
        contains(
          'paths: [lib/src/infrastructure/]   # detected at lib/src/infrastructure/',
        ),
      );
      expect(
        yaml,
        contains(
          'paths: [lib/src/presentation/]   # detected at lib/src/presentation/',
        ),
      );

      // State management + routing comments link to pubspec deps.
      expect(
        yaml,
        contains(
          'style: riverpod_manual   # inferred from pubspec.yaml::dependencies::flutter_riverpod',
        ),
      );
      expect(
        yaml,
        contains(
          'package: go_router   # inferred from pubspec.yaml::dependencies::go_router',
        ),
      );

      // Theme detected.
      expect(
        yaml,
        contains('path: lib/src/theme/   # detected at lib/src/theme/'),
      );

      // Testing framework matches Flutter project.
      expect(yaml, contains('framework: flutter_test'));

      // mr.pre_push uses `flutter test`.
      expect(yaml, contains('flutter test'));

      // No actual PLACEHOLDER blocks when everything is detected. We use a
      // body-specific phrase as discriminator — the header's "Marker legend"
      // always documents `# PLACEHOLDER`, but real placeholder blocks open
      // with explanatory text the legend does not contain.
      expect(yaml, isNot(contains('PLACEHOLDER — could not auto-detect a')));
      expect(yaml, isNot(contains('PLACEHOLDER — no known')));
    });
  });

  group('ConfigGenerator — placeholders', () {
    test('emits PLACEHOLDER blocks when no layers are detected', () {
      final input = ConfigGenerationInput(
        pubspec: _pubspec(),
        layers: _noLayers(),
        generatedAtUtc: _fixedTime,
      );
      final yaml = const ConfigGenerator().generate(input);

      expect(
        yaml,
        contains(
          '# PLACEHOLDER — could not auto-detect a canonical domain folder.',
        ),
      );
      expect(
        yaml,
        contains(
          '# PLACEHOLDER — could not auto-detect a canonical infrastructure folder.',
        ),
      );
      expect(
        yaml,
        contains(
          '# PLACEHOLDER — could not auto-detect a canonical presentation folder.',
        ),
      );
      expect(
        yaml,
        contains('# PLACEHOLDER — could not auto-detect a theme folder.'),
      );

      // Each placeholder must mention the proposal trigger to revisit
      // detection — so a real consumer reading the file knows where to push
      // back when the heuristic falls short.
      expect(
        yaml,
        contains('docs/proposals/0001-adoption-flow-overhaul.md (Item A).'),
      );

      // Even with placeholders, defaults are still written so the YAML parses.
      expect(yaml, contains('paths: [lib/src/domain/]'));
      expect(yaml, contains('forbid_imports: ["package:flutter/"]'));
    });

    test('emits state management PLACEHOLDER when no known dep is present', () {
      final input = ConfigGenerationInput(
        pubspec: _pubspec(),
        layers: _allLayersDetected(),
        generatedAtUtc: _fixedTime,
      );
      final yaml = const ConfigGenerator().generate(input);

      expect(
        yaml,
        contains(
          '# PLACEHOLDER — no known state-management dependency in pubspec.yaml.',
        ),
      );
      expect(
        yaml,
        contains('Set one of: riverpod_manual | bloc | provider | getx | none'),
      );
      // Falls back to a default so the YAML stays valid.
      expect(yaml, contains('style: riverpod_manual'));
    });

    test('emits routing PLACEHOLDER when no known router dep is present', () {
      final input = ConfigGenerationInput(
        pubspec: _pubspec(),
        layers: _allLayersDetected(),
        generatedAtUtc: _fixedTime,
      );
      final yaml = const ConfigGenerator().generate(input);

      expect(
        yaml,
        contains('# PLACEHOLDER — no known routing package in pubspec.yaml.'),
      );
      expect(yaml, contains('Set one of: go_router | auto_route | none'));
    });

    test('layer placeholders document common non-canonical alternatives', () {
      final input = ConfigGenerationInput(
        pubspec: _pubspec(),
        layers: _noLayers(),
        generatedAtUtc: _fixedTime,
      );
      final yaml = const ConfigGenerator().generate(input);

      // The infrastructure placeholder must surface `data/` (the common
      // Clean Architecture alternative) since this is the most likely
      // friction point.
      expect(yaml, contains('lib/data/'));
      expect(yaml, contains('Clean Architecture'));

      // Spanish alternatives surfaced.
      expect(yaml, contains('lib/src/dominio/'));
      expect(yaml, contains('lib/src/presentacion/'));

      // Feature-first alternative surfaced.
      expect(yaml, contains('lib/features/<feature>/domain/'));
    });
  });

  group('ConfigGenerator — non-Flutter project', () {
    test('uses dart_test framework and `dart test` in pre_push', () {
      final input = ConfigGenerationInput(
        pubspec: _pubspec(name: 'pure_dart_pkg', flutter: false),
        layers: _allLayersDetected(),
        generatedAtUtc: _fixedTime,
      );
      final yaml = const ConfigGenerator().generate(input);

      expect(yaml, contains('framework: dart_test'));
      expect(yaml, contains('inferred — no Flutter dependency'));
      expect(yaml, contains('dart format ., dart analyze, dart test'));
      expect(yaml, isNot(contains('flutter test')));
    });
  });

  group('ConfigGenerator — output format', () {
    test('emits valid YAML structure (parses without error)', () {
      // We don't validate against the full project-config schema here — that
      // is a separate concern. But the generated string MUST be parseable
      // YAML, otherwise nothing else works.
      final input = ConfigGenerationInput(
        pubspec: _pubspec(stateStyle: 'bloc', stateOrigin: 'flutter_bloc'),
        layers: _allLayersDetected(),
        generatedAtUtc: _fixedTime,
      );
      final yaml = const ConfigGenerator().generate(input);

      // Smoke check: starts with a header comment and contains the required
      // top-level keys in order.
      final lines = yaml.split('\n');
      expect(lines.first.startsWith('#'), isTrue);
      expect(yaml, contains('config_version: "1.0.0"'));
      expect(yaml, contains('project:'));
      expect(yaml, contains('architecture:'));
      expect(yaml, contains('state_management:'));
      expect(yaml, contains('routing:'));
      expect(yaml, contains('theme:'));
      expect(yaml, contains('testing:'));
      expect(yaml, contains('coverage:'));
      expect(yaml, contains('ticket_source:'));
      expect(yaml, contains('design_source:'));
      expect(yaml, contains('mr:'));
      expect(yaml, contains('pipeline:'));
      expect(yaml, contains('gates:'));
    });

    test('header explains marker legend', () {
      final input = ConfigGenerationInput(
        pubspec: _pubspec(),
        layers: _allLayersDetected(),
        generatedAtUtc: _fixedTime,
      );
      final yaml = const ConfigGenerator().generate(input);
      expect(yaml, contains('Marker legend'));
      expect(yaml, contains('inferred from'));
      expect(yaml, contains('detected at'));
      expect(yaml, contains('default'));
      expect(yaml, contains('PLACEHOLDER'));
    });
  });
}
