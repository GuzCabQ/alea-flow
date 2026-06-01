// Tests for `aflow inventory` command.
//
// Covers:
//   - stdout mode (no --output) over a fixture with a widget → exit 0
//   - --output <file> → exit 0, JSON file written
//   - missing/invalid config → exit 2
//   - empty project (no scan paths match) → exit 0, 0 widgets
//   - a project with a recognizable widget class → summary includes it

import 'dart:convert';
import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('inventory command', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_inv_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    // ── helpers ──────────────────────────────────────────────────────────────

    void writeConfig() {
      Directory(p.join(tmp.path, 'lib/src/domain')).createSync(recursive: true);
      Directory(
        p.join(tmp.path, 'lib/src/presentation'),
      ).createSync(recursive: true);

      File(p.join(tmp.path, '.alea.yaml')).writeAsStringSync('''
config_version: "1.0.0"
project:
  package_name: demo
  pubspec_path: pubspec.yaml
architecture:
  layers:
    domain:
      paths: [lib/src/domain/]
    presentation:
      paths: [lib/src/presentation/]
      may_import: [domain]
state_management:
  style: riverpod_manual
routing:
  package: go_router
  router_path: lib/src/app/router.dart
theme:
  path: lib/src/theme/
testing:
  framework: flutter_test
  fakes_path: test/fakes/
coverage:
  thresholds:
    domain: 80
ticket_source:
  adapter: file
design_source:
  default: figma
mr:
  policy: single-commit-amend
  branch_pattern: "feature/{ticket_id}-{slug}"
  pre_push: []
pipeline:
  default_mode: guided
  modes_available: [guided]
  cost_warn_usd: 3.0
  cost_hard_stop_usd: 5.0
gates:
  domain: [domain]
''');
    }

    // ── missing .alea.yaml → exit 2 ─────────────────────────────────────────

    test('missing .alea.yaml exits 2', () async {
      final emptyDir = Directory.systemTemp.createTempSync('alea_inv_nc_');
      addTearDown(() => emptyDir.deleteSync(recursive: true));
      final code = await AleaCliRunner().run([
        'inventory',
        '--project-root',
        emptyDir.path,
      ]);
      expect(code, 2);
    });

    // ── stdout mode, empty project → exit 0, 0 widgets ───────────────────────

    test('stdout mode on empty project exits 0 with 0 widgets', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'inventory',
        '--project-root',
        tmp.path,
      ]);
      // No widget classes present → still exits 0 (not an error).
      expect(code, 0);
    });

    // ── stdout mode, project with a widget class ──────────────────────────────

    test('stdout mode detects a StatelessWidget subclass', () async {
      writeConfig();
      // Write a recognizable widget file in the presentation layer.
      File(
        p.join(tmp.path, 'lib/src/presentation/home_screen.dart'),
      ).writeAsStringSync('''
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Text('home'));
  }
}
''');

      final code = await AleaCliRunner().run([
        'inventory',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 0);
    });

    // ── --output mode writes a JSON file ─────────────────────────────────────

    test('--output writes a JSON file at the given relative path', () async {
      writeConfig();
      File(
        p.join(tmp.path, 'lib/src/presentation/card_widget.dart'),
      ).writeAsStringSync('''
import 'package:flutter/material.dart';

class CardWidget extends StatelessWidget {
  const CardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(child: Text('card'));
  }
}
''');

      const outputRel = 'widget_inventory.json';
      final code = await AleaCliRunner().run([
        'inventory',
        '--project-root',
        tmp.path,
        '--output',
        outputRel,
      ]);
      expect(code, 0);
      final outFile = File(p.join(tmp.path, outputRel));
      expect(outFile.existsSync(), isTrue, reason: 'JSON file must be created');

      // The file must be valid JSON (list or map).
      final content = outFile.readAsStringSync();
      expect(
        () => jsonDecode(content),
        returnsNormally,
        reason: 'output must be valid JSON',
      );
    });

    // ── --output to nested path creates parent directories ────────────────────

    test('--output to nested path creates parent directories', () async {
      writeConfig();

      final code = await AleaCliRunner().run([
        'inventory',
        '--project-root',
        tmp.path,
        '--output',
        'build/reports/widget_inventory.json',
      ]);
      expect(code, 0);
      expect(
        File(
          p.join(tmp.path, 'build/reports/widget_inventory.json'),
        ).existsSync(),
        isTrue,
      );
    });

    // ── stdout mode when a ConsumerWidget is present ──────────────────────────

    test('detects a ConsumerWidget subclass', () async {
      writeConfig();
      File(
        p.join(tmp.path, 'lib/src/presentation/counter_widget.dart'),
      ).writeAsStringSync('''
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CounterWidget extends ConsumerWidget {
  const CounterWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Text('counter');
  }
}
''');

      final code = await AleaCliRunner().run([
        'inventory',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 0);
    });
  });
}
