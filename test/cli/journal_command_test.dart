import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'malformed journal.jsonl line exits 2 with a message, no crash',
    () async {
      final tmp = Directory.systemTemp.createTempSync('journal_bad_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File(
        p.join(tmp.path, 'journal.jsonl'),
      ).writeAsStringSync('{"valid": true}\nthis-is-not-json\n');
      final code = await AleaCliRunner().run([
        'journal',
        '--run-directory',
        tmp.path,
      ]);
      expect(code, 2);
    },
  );
}
