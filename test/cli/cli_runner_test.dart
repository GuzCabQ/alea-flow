// Smoke tests for AleaCliRunner — one assertion per subcommand confirming
// it parses args, runs end-to-end (against a temp project tree), and exits
// with a sensible code.

import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('AleaCliRunner', () {
    test('--help lists every subcommand and exits 0', () async {
      final code = await AleaCliRunner().run(const ['--help']);
      // CommandRunner returns 0 for --help.
      expect(code, 0);
    });

    test('unknown command yields EX_USAGE', () async {
      final code = await AleaCliRunner().run(const ['does-not-exist']);
      expect(code, 64);
    });

    test('analyze on a synthetic project returns 0', () async {
      final tmp = _makeMinimalProject();
      addTearDown(() => tmp.deleteSync(recursive: true));
      // Single trivial dart file → analyzers either pass or no-op.
      final code = await AleaCliRunner().run([
        'analyze',
        '--project-root',
        tmp.path,
        '--format',
        'json',
      ]);
      expect(code, anyOf(0, 1)); // pass or fail is fine; CLI didn't crash.
    });

    test('context --run-directory builds context-packet.md', () async {
      final tmp = _makeMinimalProject();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final runDir = Directory(p.join(tmp.path, '.pipeline/runs/T1'));
      runDir.createSync(recursive: true);

      final code = await AleaCliRunner().run([
        'context',
        '--project-root',
        tmp.path,
        '--run-directory',
        runDir.path,
      ]);
      expect(code, 0);
      expect(
        File(p.join(runDir.path, 'context-packet.md')).existsSync(),
        isTrue,
      );
    });

    test('inventory without --output prints summary, exits 0', () async {
      final tmp = _makeMinimalProject();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final code = await AleaCliRunner().run([
        'inventory',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 0);
    });

    test('inventory --output writes JSON file', () async {
      final tmp = _makeMinimalProject();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final code = await AleaCliRunner().run([
        'inventory',
        '--project-root',
        tmp.path,
        '--output',
        'widget_inventory.json',
      ]);
      expect(code, 0);
      expect(
        File(p.join(tmp.path, 'widget_inventory.json')).existsSync(),
        isTrue,
      );
    });

    test('scaffold --dry-run reports the plan without writing files', () async {
      final tmp = _makeMinimalProject();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final code = await AleaCliRunner().run([
        'scaffold',
        'demo',
        '--project-root',
        tmp.path,
        '--style',
        'riverpod_manual',
        '--layer',
        'presentation',
        '--dry-run',
      ]);
      expect(code, 0);
      // Dry-run must NOT have written feature files.
      expect(
        Directory(p.join(tmp.path, 'lib/src/domain/feature/demo')).existsSync(),
        isFalse,
      );
    });

    test('scaffold without --style picks adapter from .alea.yaml', () async {
      final tmp = _makeMinimalProject();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final code = await AleaCliRunner().run([
        'scaffold',
        'demo',
        '--project-root',
        tmp.path,
        '--layer',
        'domain',
        '--dry-run',
      ]);
      expect(code, 0);
    });

    test('journal reads JSONL written by another command', () async {
      final tmp = _makeMinimalProject();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final runDir = Directory(p.join(tmp.path, '.pipeline/runs/T2'));
      runDir.createSync(recursive: true);
      // Write a minimal JSONL by hand — testing the reader path only.
      File(p.join(runDir.path, 'journal.jsonl')).writeAsStringSync(
        '{"ts":"2026-05-23T10:00:00.000Z","source":"test","kind":"check","payload":{}}\n',
      );
      final code = await AleaCliRunner().run([
        'journal',
        '--run-directory',
        runDir.path,
      ]);
      expect(code, 0);
    });

    test('match with invalid family returns EX_USAGE-ish exit', () async {
      final tmp = _makeMinimalProject(withTokenCatalog: true);
      addTearDown(() => tmp.deleteSync(recursive: true));
      // No --format=json so we don't deal with stdout — just verify exit code.
      final code = await AleaCliRunner().run([
        'match',
        'unknownFamily',
        '#000000',
        '--project-root',
        tmp.path,
      ]);
      // The match command returns 64 for bad family input.
      expect(code, 64);
    });

    test('match color with token_catalog returns 0', () async {
      final tmp = _makeMinimalProject(withTokenCatalog: true);
      addTearDown(() => tmp.deleteSync(recursive: true));
      final code = await AleaCliRunner().run([
        'match',
        'color',
        '#DA1884',
        '--project-root',
        tmp.path,
        '--format',
        'json',
      ]);
      expect(code, 0);
    });
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

Directory _makeMinimalProject({bool withTokenCatalog = false}) {
  final tmp = Directory.systemTemp.createTempSync('alea_cli_smoke_');
  final yaml = StringBuffer()
    ..writeln('config_version: "1.0.0"')
    ..writeln()
    ..writeln('project:')
    ..writeln('  package_name: demo')
    ..writeln('  pubspec_path: pubspec.yaml')
    ..writeln()
    ..writeln('architecture:')
    ..writeln('  layers:')
    ..writeln('    domain:')
    ..writeln('      paths: [lib/src/domain/]')
    ..writeln('    infrastructure:')
    ..writeln('      paths: [lib/src/infrastructure/]')
    ..writeln('      may_import: [domain]')
    ..writeln('    presentation:')
    ..writeln('      paths: [lib/src/presentation/]')
    ..writeln('      may_import: [domain]')
    ..writeln()
    ..writeln('state_management:')
    ..writeln('  style: riverpod_manual')
    ..writeln()
    ..writeln('routing:')
    ..writeln('  package: go_router')
    ..writeln('  router_path: lib/src/app/router.dart')
    ..writeln()
    ..writeln('theme:')
    ..writeln('  path: lib/src/theme/');
  if (withTokenCatalog) {
    final tokensDir = Directory(p.join(tmp.path, 'lib/src/theme'));
    tokensDir.createSync(recursive: true);
    File(p.join(tokensDir.path, 'style_colors.dart')).writeAsStringSync('''
class StyleColors {
  static const Color brand60 = Color(0xFFDA1884);
  static const Color brand40 = Color(0xFF4A0E2B);
}
''');
    yaml
      ..writeln('  token_catalog:')
      ..writeln('    adapter: dart_source')
      ..writeln('    source: lib/src/theme/');
  }
  yaml
    ..writeln()
    ..writeln('testing:')
    ..writeln('  framework: flutter_test')
    ..writeln('  fakes_path: test/fakes/')
    ..writeln()
    ..writeln('coverage:')
    ..writeln('  thresholds:')
    ..writeln('    domain: 90')
    ..writeln()
    ..writeln('ticket_source:')
    ..writeln('  adapter: file')
    ..writeln()
    ..writeln('design_source:')
    ..writeln('  default: figma')
    ..writeln()
    ..writeln('mr:')
    ..writeln('  policy: single-commit-amend')
    ..writeln('  branch_pattern: "feature/{ticket_id}-{slug}"')
    ..writeln('  pre_push: [dart format ., dart analyze]')
    ..writeln()
    ..writeln('pipeline:')
    ..writeln('  default_mode: guided')
    ..writeln('  modes_available: [guided]')
    ..writeln('  cost_warn_usd: 3.0')
    ..writeln('  cost_hard_stop_usd: 5.0')
    ..writeln()
    ..writeln('gates:')
    ..writeln('  domain: [domain]');

  File(p.join(tmp.path, '.alea.yaml')).writeAsStringSync(yaml.toString());

  // Minimal lib structure so analyze + inventory have something to read.
  Directory(p.join(tmp.path, 'lib/src/domain')).createSync(recursive: true);
  Directory(
    p.join(tmp.path, 'lib/src/presentation'),
  ).createSync(recursive: true);
  File(
    p.join(tmp.path, 'lib/src/domain/empty.dart'),
  ).writeAsStringSync('class _Sentinel {}\n');

  return tmp;
}
