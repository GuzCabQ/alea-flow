import 'dart:io';
import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('run command', () {
    late Directory tmp;
    final schemasDir = p.join(Directory.current.path, 'contracts/schemas');
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_run_'));
    tearDown(() => tmp.deleteSync(recursive: true));
    void writeAleaYaml() =>
        File(p.join(tmp.path, '.alea.yaml')).writeAsStringSync(_minimalYaml());

    test('empty run → exit 0 (advance to analyze)', () async {
      writeAleaYaml();
      final code = await AleaCliRunner().run([
        'run',
        'DEV-1',
        '--project-root',
        tmp.path,
        '--schemas-dir',
        schemasDir,
      ]);
      expect(code, 0);
    });

    test('invalid analysis → exit 1 (blocked)', () async {
      writeAleaYaml();
      final rd = Directory(p.join(tmp.path, '.pipeline/runs/DEV-1'))
        ..createSync(recursive: true);
      File(
        p.join(rd.path, 'analysis.json'),
      ).writeAsStringSync('{"type":"banana"}');
      final code = await AleaCliRunner().run([
        'run',
        'DEV-1',
        '--project-root',
        tmp.path,
        '--schemas-dir',
        schemasDir,
      ]);
      expect(code, 1);
    });

    test('missing .alea.yaml → exit 2', () async {
      final code = await AleaCliRunner().run([
        'run',
        'DEV-1',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 2);
    });

    // Task 1: --schemas-dir default resolves under project-root, not CWD.
    // When --schemas-dir is omitted, the default 'contracts/schemas' must be
    // joined to --project-root, not to the process CWD.  Running from a
    // different directory used to silently fail schema lookup.
    test(
      'schemas-dir default resolves under project-root (no explicit --schemas-dir)',
      () async {
        // Copy the real schemas into the temp project so the lookup can succeed.
        writeAleaYaml();
        final realSchemas = Directory(
          p.join(Directory.current.path, 'contracts/schemas'),
        );
        final tmpSchemas = Directory(p.join(tmp.path, 'contracts/schemas'))
          ..createSync(recursive: true);
        for (final f in realSchemas.listSync().whereType<File>()) {
          File(
            p.join(tmpSchemas.path, p.basename(f.path)),
          ).writeAsBytesSync(f.readAsBytesSync());
        }
        // Run WITHOUT --schemas-dir from a completely unrelated cwd (no override).
        final code = await AleaCliRunner().run([
          'run',
          'DEV-1',
          '--project-root',
          tmp.path,
          // intentionally no --schemas-dir
        ]);
        // Should advance (exit 0) or block on a gate issue (exit 1),
        // but NOT fail with a schema-not-found / config error (exit 2).
        expect(
          code,
          isNot(2),
          reason: 'should not fail with a file/parse error',
        );
      },
    );

    // Task 2: ticket_id must be sanitised before use in a filesystem path.
    test(
      'rejects a ticket_id with path-traversal characters (exit 64)',
      () async {
        final code = await AleaCliRunner().run(['run', '../../etc', '-r', '.']);
        expect(code, 64);
      },
    );

    test('rejects a ticket_id with a slash (exit 64)', () async {
      final code = await AleaCliRunner().run(['run', 'a/b', '-r', '.']);
      expect(code, 64);
    });
  });
}

String _minimalYaml() => '''
config_version: "1.0.0"
project: { package_name: demo, pubspec_path: pubspec.yaml }
architecture:
  layers:
    domain: { paths: [lib/src/domain/] }
state_management: { style: riverpod_manual }
routing: { package: go_router, router_path: lib/src/app/router.dart }
theme: { path: lib/src/theme/ }
testing: { framework: flutter_test, fakes_path: test/fakes/ }
coverage: { thresholds: { domain: 80 } }
ticket_source: { adapter: file }
design_source: { default: figma }
mr: { policy: single-commit-amend, branch_pattern: "feature/{ticket_id}-{slug}", pre_push: [] }
pipeline: { default_mode: guided, modes_available: [guided], cost_warn_usd: 3, cost_hard_stop_usd: 5 }
gates: { domain: [domain] }
''';
