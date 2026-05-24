// Tests for `aflow metrics` — exit-code + history-file glue.
// Aggregation correctness is covered in test/core/metrics/.

import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('metrics command', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_metrics_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String writeHistory(String jsonl) {
      final f = File(p.join(tmp.path, 'history.jsonl'))
        ..writeAsStringSync(jsonl);
      return f.path;
    }

    test('reports on an existing history, exit 0', () async {
      final h = writeHistory(
        '{"manual_code_corrections":6}\n'
        '{"manual_code_corrections":7}\n'
        '{"manual_code_corrections":8}\n',
      );
      final code = await AleaCliRunner().run([
        'metrics',
        '--history',
        h,
        '--format',
        'json',
      ]);
      expect(code, 0);
    });

    test('missing history exits 2', () async {
      final code = await AleaCliRunner().run([
        'metrics',
        '--history',
        p.join(tmp.path, 'nope.jsonl'),
      ]);
      expect(code, 2);
    });
  });
}
