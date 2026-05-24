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
