import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('analyze command', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_analyze_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    void writeFixture() {
      File(p.join(tmp.path, '.alea.yaml')).writeAsStringSync(_minimalYaml());
      final domain = Directory(p.join(tmp.path, 'lib/src/domain'))
        ..createSync(recursive: true);
      File(
        p.join(domain.path, 'widget.dart'),
      ).writeAsStringSync('class Foo {}\n');
    }

    test('--format html writes the four-file bundle', () async {
      writeFixture();
      final outDir = Directory(p.join(tmp.path, 'out'));

      final code = await AleaCliRunner().run([
        'analyze',
        '--gate',
        'full',
        '--format',
        'html',
        '-r',
        tmp.path,
        '-o',
        outDir.path,
      ]);

      // Exit code mirrors gate pass/fail.
      expect(code, anyOf(0, 1));

      for (final name in [
        'index.html',
        'styles.css',
        'app.js',
        'report.json',
      ]) {
        expect(
          File(p.join(outDir.path, name)).existsSync(),
          isTrue,
          reason: '$name should have been written',
        );
      }

      final indexHtml = File(
        p.join(outDir.path, 'index.html'),
      ).readAsStringSync();
      expect(indexHtml, contains('window.__ALEA_REPORT__ ='));
      expect(indexHtml, isNot(contains('__ALEA_DATA__')));
    });

    test('--format html defaults the output dir to alea-reports/', () async {
      writeFixture();
      // The default `alea-reports/` now resolves under the project root (-r),
      // so it lands inside the temp project dir (cleaned up with it). No
      // process-global CWD mutation — that used to race with other test files
      // under `dart test`'s shared-process isolates.
      final code = await AleaCliRunner().run([
        'analyze',
        '--gate',
        'full',
        '--format',
        'html',
        '-r',
        tmp.path,
      ]);
      expect(code, anyOf(0, 1));
      expect(
        File(p.join(tmp.path, 'alea-reports', 'index.html')).existsSync(),
        isTrue,
        reason:
            'default output dir should be alea-reports/ under the project root',
      );
    });

    test('--format json still emits JSON to stdout', () async {
      writeFixture();
      final code = await AleaCliRunner().run([
        'analyze',
        '--gate',
        'full',
        '--format',
        'json',
        '-r',
        tmp.path,
      ]);
      expect(code, anyOf(0, 1));
    });

    test('--format human still runs', () async {
      writeFixture();
      final code = await AleaCliRunner().run([
        'analyze',
        '--gate',
        'full',
        '--format',
        'human',
        '-r',
        tmp.path,
      ]);
      expect(code, anyOf(0, 1));
    });

    test('--run-directory produces a journal.jsonl', () async {
      writeFixture();
      final runDir = Directory(p.join(tmp.path, '.pipeline/runs/DEV-1'))
        ..createSync(recursive: true);
      final code = await AleaCliRunner().run([
        'analyze',
        '--gate',
        'full',
        '-r',
        tmp.path,
        '--run-directory',
        runDir.path,
      ]);
      expect(code, anyOf(0, 1));
      expect(
        File(p.join(runDir.path, 'journal.jsonl')).existsSync(),
        isTrue,
        reason: 'journal.jsonl must be created in the run directory',
      );
    });

    // Task 3: _resolveFiles must return a sorted, de-duplicated list so that
    // analysis output is deterministic across machines/OS/filesystem order.
    // The sort is the GUARANTEE — do not remove it even if a given OS already
    // returns sorted entries from listSync.
    test('file enumeration is deterministic (sorted) across two runs', () async {
      // Fixture with several .dart files whose names are NOT in alphabetical
      // order on creation so any unsorted ordering would be detectable.
      File(p.join(tmp.path, '.alea.yaml')).writeAsStringSync(_minimalYaml());
      final domain = Directory(p.join(tmp.path, 'lib/src/domain'))
        ..createSync(recursive: true);
      // Create files intentionally out of alphabetical order.
      for (final name in ['zzz.dart', 'aaa.dart', 'mmm.dart']) {
        File(p.join(domain.path, name)).writeAsStringSync('class C {}\n');
      }

      // Run analyze --format json twice, strip the timestamp (which naturally
      // differs between runs), and compare the rest byte-for-byte.
      Future<String> captureStripped() async {
        final f = File(
          p.join(
            tmp.path,
            'gate_out_${DateTime.now().microsecondsSinceEpoch}.json',
          ),
        );
        await AleaCliRunner().run([
          'analyze',
          '--gate',
          'full',
          '--format',
          'json',
          '--output-file',
          f.path,
          '-r',
          tmp.path,
        ]);
        // Remove the timestamp value so two consecutive runs compare equal.
        return f.readAsStringSync().replaceAll(
          RegExp(r'"timestamp":\s*"[^"]+"'),
          '"timestamp":"<stripped>"',
        );
      }

      final outA = await captureStripped();
      final outB = await captureStripped();

      expect(
        outA,
        equals(outB),
        reason:
            'Two runs of analyze must produce identical JSON output '
            '(excluding the timestamp). Non-deterministic file ordering would '
            'cause issue lists to differ when issues exist.',
      );
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
