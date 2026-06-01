// Tests for `aflow match` command.
//
// Covers:
//   - color family happy path (exit 0)
//   - typography family happy path (exit 0)
//   - spacing family happy path (exit 0)
//   - unknown family → exit 64
//   - missing positional args → exit 64
//   - no token_catalog in config → exit 2
//   - invalid color hex → exit 64
//   - --format json output

import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('match command', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_match_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    // ── helpers ──────────────────────────────────────────────────────────────

    void writeConfig({bool withCatalog = true}) {
      final tokensDir = Directory(p.join(tmp.path, 'lib/src/theme'))
        ..createSync(recursive: true);

      if (withCatalog) {
        // Dart-source catalog with one color, one typography, one spacing entry.
        File(p.join(tokensDir.path, 'tokens.dart')).writeAsStringSync('''
class AppColors {
  static const Color primary = Color(0xFF0066CC);
}
class AppTypography {
  static const TextStyle bodyMedium = TextStyle(fontSize: 16, fontWeight: FontWeight.w400);
}
class AppSpacing {
  static const double gutter = 16.0;
}
''');
      }

      final tokenCatalogBlock = withCatalog
          ? '''
  token_catalog:
    adapter: dart_source
    source: lib/src/theme/
'''
          : '';

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
$tokenCatalogBlock
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

    // ── missing positional args → exit 64 ────────────────────────────────────

    test('missing both positional args returns EX_USAGE (64)', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'match',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 64);
    });

    test('missing query (only family given) returns EX_USAGE (64)', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'match',
        'color',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 64);
    });

    // ── no token_catalog in config → exit 2 ─────────────────────────────────

    test('no token_catalog in config exits 2', () async {
      writeConfig(withCatalog: false);
      final code = await AleaCliRunner().run([
        'match',
        'color',
        '#0066CC',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 2);
    });

    // ── missing .alea.yaml → exit 2 ─────────────────────────────────────────

    test('missing .alea.yaml exits 2', () async {
      // No config written → ProjectConfigException → exit 2.
      final emptyDir = Directory.systemTemp.createTempSync('alea_match_nocfg_');
      addTearDown(() => emptyDir.deleteSync(recursive: true));
      final code = await AleaCliRunner().run([
        'match',
        'color',
        '#0066CC',
        '--project-root',
        emptyDir.path,
      ]);
      expect(code, 2);
    });

    // ── unknown family → exit 64 ─────────────────────────────────────────────

    test('unknown family returns EX_USAGE (64)', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'match',
        'gradient',
        '#0066CC',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 64);
    });

    // ── color family happy path ───────────────────────────────────────────────

    test('color family happy path exits 0', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'match',
        'color',
        '#0066CC',
        '--project-root',
        tmp.path,
        '--format',
        'json',
      ]);
      expect(code, 0);
    });

    test('color family with invalid hex exits 64', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'match',
        'color',
        'notahex',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 64);
    });

    // ── typography family happy path ─────────────────────────────────────────

    test('typography family happy path exits 0', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'match',
        'typography',
        '16/400',
        '--project-root',
        tmp.path,
        '--format',
        'json',
      ]);
      expect(code, 0);
    });

    test('typography with bad query format exits 64', () async {
      writeConfig();
      // Needs "<size>/<weight>" — bare number fails.
      final code = await AleaCliRunner().run([
        'match',
        'typography',
        '16',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 64);
    });

    // ── spacing family happy path ─────────────────────────────────────────────

    test('spacing family happy path exits 0', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'match',
        'spacing',
        '16',
        '--project-root',
        tmp.path,
        '--format',
        'json',
      ]);
      expect(code, 0);
    });

    test('spacing with non-numeric query exits 64', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'match',
        'spacing',
        'large',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 64);
    });

    // ── human format (default) exits 0 ───────────────────────────────────────

    test('color match with default (human) format exits 0', () async {
      writeConfig();
      final code = await AleaCliRunner().run([
        'match',
        'color',
        '#0066CC',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 0);
    });
  });
}
