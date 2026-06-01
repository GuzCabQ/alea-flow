import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<int> runAflow(List<String> args) => AleaCliRunner().run(args);

void main() {
  test('--platform writes Claude commands into the target project', () async {
    final tmp = Directory.systemTemp.createTempSync('aflow_cmd_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final code = await runAflow([
      'install-commands',
      '--platform',
      'claude',
      '--project-root',
      tmp.path,
    ]);

    expect(code, 0);
    expect(
      Directory(
        p.join(tmp.path, '.claude', 'commands'),
      ).listSync().whereType<File>().isNotEmpty,
      isTrue,
    );
  });

  test('invalid --platform exits 64', () async {
    final code = await runAflow(['install-commands', '--platform', 'bogus']);
    expect(code, 64);
  });

  test(
    '--platform with a comma list installs each project-scoped platform',
    () async {
      final tmp = Directory.systemTemp.createTempSync('aflow_multi_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final code = await runAflow([
        'install-commands',
        '--platform',
        'claude,gemini,cursor',
        '--project-root',
        tmp.path,
      ]);
      expect(code, 0);

      for (final dir in [
        '.claude/commands',
        '.gemini/commands',
        '.cursor/commands',
      ]) {
        expect(
          Directory(p.join(tmp.path, dir)).existsSync(),
          isTrue,
          reason: '$dir should exist after multi-platform install',
        );
      }
    },
  );

  test('--dry-run writes nothing', () async {
    final tmp = Directory.systemTemp.createTempSync('aflow_dry_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final code = await runAflow([
      'install-commands',
      '--platform',
      'claude',
      '--project-root',
      tmp.path,
      '--dry-run',
    ]);
    expect(code, 0);
    expect(Directory(p.join(tmp.path, '.claude')).existsSync(), isFalse);
  });
}
