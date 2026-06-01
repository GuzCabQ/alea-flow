// Tests for `aflow scaffold` command.
//
// Covers:
//   - --dry-run happy path (exit 0, no files written)
//   - missing feature name → exit 64
//   - unsupported --style → exit 2
//   - missing .alea.yaml → exit 2
//   - --layer domain with riverpod_manual adapter (dry-run)
//   - --layer infrastructure (unsupported by riverpod_manual adapter, dry-run)
//   - actual scaffold run writes files, exit 0 on success
//
// WP10 FIX NOTE:
//   When --layer is unsupported by the selected adapter, the command now exits 2
//   with a clear "does not support layer" message, instead of silently exiting 0.

import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('scaffold command', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_scaffold_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    // ── helpers ──────────────────────────────────────────────────────────────

    void writeConfig({String style = 'riverpod_manual'}) {
      Directory(p.join(tmp.path, 'lib/src/domain')).createSync(recursive: true);
      Directory(
        p.join(tmp.path, 'lib/src/presentation'),
      ).createSync(recursive: true);
      Directory(
        p.join(tmp.path, 'lib/src/infrastructure'),
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
    infrastructure:
      paths: [lib/src/infrastructure/]
      may_import: [domain]
    presentation:
      paths: [lib/src/presentation/]
      may_import: [domain]
state_management:
  style: $style
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

    // ── missing feature name → exit 64 ───────────────────────────────────────

    test('missing feature name returns EX_USAGE (64)', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'scaffold',
        '--project-root',
        tmp.path,
        '--dry-run',
      ]);
      expect(code, 64);
    });

    // ── missing .alea.yaml → exit 2 ─────────────────────────────────────────

    test('missing .alea.yaml exits 2', () async {
      final emptyDir = Directory.systemTemp.createTempSync('alea_scaffold_nc_');
      addTearDown(() => emptyDir.deleteSync(recursive: true));
      final code = await AleaCliRunner().run([
        'scaffold',
        'myfeature',
        '--project-root',
        emptyDir.path,
      ]);
      expect(code, 2);
    });

    // ── unsupported --style → exit 2 ─────────────────────────────────────────

    test('unsupported --style returns exit 2', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'scaffold',
        'myfeature',
        '--project-root',
        tmp.path,
        '--style',
        'getx',
        '--dry-run',
      ]);
      expect(code, 2);
    });

    // ── --dry-run happy path (presentation layer) ─────────────────────────────

    test(
      '--dry-run with riverpod_manual + presentation layer exits 0',
      () async {
        writeConfig();
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
        // Dry-run must NOT write any feature files.
        expect(
          Directory(
            p.join(tmp.path, 'lib/src/domain/feature/demo'),
          ).existsSync(),
          isFalse,
        );
        expect(
          Directory(
            p.join(tmp.path, 'lib/src/presentation/feature/demo'),
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('--dry-run with riverpod_manual + domain layer exits 0', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'scaffold',
        'login',
        '--project-root',
        tmp.path,
        '--style',
        'riverpod_manual',
        '--layer',
        'domain',
        '--dry-run',
      ]);
      expect(code, 0);
    });

    test(
      '--dry-run adapter reads style from .alea.yaml when --style omitted',
      () async {
        writeConfig(style: 'riverpod_manual');
        final code = await AleaCliRunner().run([
          'scaffold',
          'wallet',
          '--project-root',
          tmp.path,
          '--layer',
          'domain',
          '--dry-run',
        ]);
        expect(code, 0);
      },
    );

    // ── actual scaffold run writes files ──────────────────────────────────────

    test(
      'actual scaffold (no --dry-run) writes feature files, exits 0',
      () async {
        writeConfig();
        final code = await AleaCliRunner().run([
          'scaffold',
          'payment',
          '--project-root',
          tmp.path,
          '--style',
          'riverpod_manual',
          '--layer',
          'presentation',
        ]);
        expect(code, 0);
        // At least one feature file must have been written.
        final domainFeatureDir = Directory(
          p.join(tmp.path, 'lib/src/domain/feature/payment'),
        );
        final presentationFeatureDir = Directory(
          p.join(tmp.path, 'lib/src/presentation/feature/payment'),
        );
        expect(
          domainFeatureDir.existsSync() || presentationFeatureDir.existsSync(),
          isTrue,
          reason: 'scaffold should have written at least one feature directory',
        );
      },
    );

    // ── FIX: --layer bugfix → exit 2 with "does not support layer" message ───
    //
    // riverpod_manual adapter's supports() returns false for the 'bugfix' layer.
    // The command now checks adapter.supports() before calling generate() and
    // exits 2 with a descriptive error message — no silent success.
    test(
      '--layer bugfix with riverpod_manual adapter exits 2 (unsupported layer)',
      () async {
        writeConfig();
        final code = await AleaCliRunner().run([
          'scaffold',
          'myfix',
          '--project-root',
          tmp.path,
          '--style',
          'riverpod_manual',
          '--layer',
          'bugfix',
          '--dry-run',
        ]);
        // Fixed behavior: exits 2 — unsupported layer is an error, not silent success.
        expect(code, 2);
      },
    );

    // ── bloc adapter ──────────────────────────────────────────────────────────

    test('bloc adapter dry-run exits 0', () async {
      writeConfig(style: 'bloc');
      final code = await AleaCliRunner().run([
        'scaffold',
        'cart',
        '--project-root',
        tmp.path,
        '--style',
        'bloc',
        '--layer',
        'presentation',
        '--dry-run',
      ]);
      expect(code, 0);
    });
  });
}
