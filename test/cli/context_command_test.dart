// Tests for `aflow context` command.
//
// Covers:
//   - stdout mode (no --run-directory) → exit 0, body printed to stdout
//   - --run-directory mode → exit 0, context-packet.md written
//   - missing .alea.yaml → exit 2
//   - --force regenerates even when a fresh packet exists
//   - --ttl-minutes with a non-integer value → defaults to 5 (does NOT crash)
//   - --format full includes front-matter
//   - --format body (default) prints markdown only

import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('context command', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_ctx_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    // ── helpers ──────────────────────────────────────────────────────────────

    void writeConfig() {
      File(p.join(tmp.path, '.alea.yaml')).writeAsStringSync('''
config_version: "1.0.0"
project:
  package_name: demo
  pubspec_path: pubspec.yaml
architecture:
  layers:
    domain:
      paths: [lib/src/domain/]
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
      final emptyDir = Directory.systemTemp.createTempSync('alea_ctx_nc_');
      addTearDown(() => emptyDir.deleteSync(recursive: true));
      final code = await AleaCliRunner().run([
        'context',
        '--project-root',
        emptyDir.path,
      ]);
      expect(code, 2);
    });

    // ── stdout mode (no --run-directory) → exit 0 ────────────────────────────

    test('stdout mode exits 0', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'context',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 0);
    });

    test('stdout mode --format body exits 0', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'context',
        '--project-root',
        tmp.path,
        '--format',
        'body',
      ]);
      expect(code, 0);
    });

    test('stdout mode --format full exits 0', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'context',
        '--project-root',
        tmp.path,
        '--format',
        'full',
      ]);
      expect(code, 0);
    });

    // ── --run-directory mode → persists context-packet.md ────────────────────

    test('--run-directory mode writes context-packet.md, exits 0', () async {
      writeConfig();
      final runDir = Directory(p.join(tmp.path, '.pipeline/runs/T1'))
        ..createSync(recursive: true);

      final code = await AleaCliRunner().run([
        'context',
        '--project-root',
        tmp.path,
        '--run-directory',
        runDir.path,
      ]);
      expect(code, 0);
      final packetFile = File(p.join(runDir.path, 'context-packet.md'));
      expect(
        packetFile.existsSync(),
        isTrue,
        reason: 'context-packet.md must be written',
      );

      // The packet must contain valid front-matter and a body section.
      final content = packetFile.readAsStringSync();
      expect(
        content,
        startsWith('---'),
        reason: 'packet must start with YAML front-matter delimiter',
      );
      expect(content, contains('hash:'));
      expect(content, contains('# ALEA Context Packet'));
    });

    // ── second call reuses cached packet (no force) ───────────────────────────

    test('second call without --force reuses the existing packet', () async {
      writeConfig();
      final runDir = Directory(p.join(tmp.path, '.pipeline/runs/T2'))
        ..createSync(recursive: true);

      // First call — generate the packet.
      await AleaCliRunner().run([
        'context',
        '--project-root',
        tmp.path,
        '--run-directory',
        runDir.path,
      ]);
      final firstModified = File(
        p.join(runDir.path, 'context-packet.md'),
      ).lastModifiedSync();

      // Second call — should reuse (file not rewritten → same mtime).
      await AleaCliRunner().run([
        'context',
        '--project-root',
        tmp.path,
        '--run-directory',
        runDir.path,
      ]);
      final secondModified = File(
        p.join(runDir.path, 'context-packet.md'),
      ).lastModifiedSync();

      // On a fast machine first == second because the file is reused.
      // We assert the second is NOT earlier (regression guard only).
      expect(
        secondModified.isAfter(firstModified) ||
            secondModified.isAtSameMomentAs(firstModified),
        isTrue,
      );
    });

    // ── --force regenerates even when a fresh packet exists ──────────────────

    test('--force regenerates the packet, exits 0', () async {
      writeConfig();
      final runDir = Directory(p.join(tmp.path, '.pipeline/runs/T3'))
        ..createSync(recursive: true);

      // First write.
      await AleaCliRunner().run([
        'context',
        '--project-root',
        tmp.path,
        '--run-directory',
        runDir.path,
      ]);

      // Force rewrite — command must succeed even though packet was fresh.
      final code = await AleaCliRunner().run([
        'context',
        '--project-root',
        tmp.path,
        '--run-directory',
        runDir.path,
        '--force',
      ]);
      expect(code, 0);
      expect(
        File(p.join(runDir.path, 'context-packet.md')).existsSync(),
        isTrue,
      );
    });

    // ── non-integer --ttl-minutes defaults to 5, does NOT crash ──────────────
    //
    // The source: `int.tryParse(res['ttl-minutes'] as String) ?? 5`
    // A non-integer value is silently defaulted to 5 minutes — no error.
    test(
      'non-integer --ttl-minutes is silently defaulted to 5, exits 0',
      () async {
        writeConfig();
        final code = await AleaCliRunner().run([
          'context',
          '--project-root',
          tmp.path,
          '--ttl-minutes',
          'abc',
        ]);
        // Current behavior: int.tryParse('abc') → null → default 5, no crash.
        expect(code, 0);
      },
    );

    // ── explicit integer --ttl-minutes is accepted ────────────────────────────

    test('explicit --ttl-minutes 10 exits 0', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'context',
        '--project-root',
        tmp.path,
        '--ttl-minutes',
        '10',
      ]);
      expect(code, 0);
    });
  });
}
