import 'dart:io';

import 'package:alea_flow/src/adapters/platform_commands/claude/adapter.dart';
import 'package:alea_flow/src/cli/install/installer.dart';
import 'package:alea_flow/src/contracts/platform_command_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const prompt = CommandPrompt(
    id: 'aflow-pipeline',
    description: 'Runs.',
    body: '# body',
  );

  test('installCommands writes files and reports them', () async {
    final tmp = Directory.systemTemp.createTempSync('aflow_inst_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final report = await installCommands(
      prompts: [prompt],
      adapters: [ClaudeCommandAdapter()],
      projectRoot: tmp.path,
    );

    final f = File(
      p.join(tmp.path, '.claude', 'commands', 'aflow-pipeline.md'),
    );
    expect(f.existsSync(), isTrue);
    expect(f.readAsStringSync(), contains('# body'));
    expect(report.files.single.existed, isFalse);
    expect(report.files.single.platformId, 'claude');
  });

  test('dryRun writes nothing but still reports intended files', () async {
    final tmp = Directory.systemTemp.createTempSync('aflow_inst_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final report = await installCommands(
      prompts: [prompt],
      adapters: [ClaudeCommandAdapter()],
      projectRoot: tmp.path,
      dryRun: true,
    );

    expect(report.files, isNotEmpty);
    expect(
      File(
        p.join(tmp.path, '.claude', 'commands', 'aflow-pipeline.md'),
      ).existsSync(),
      isFalse,
    );
  });

  test(
    'reports existed=true and overwrites when the file already exists',
    () async {
      final tmp = Directory.systemTemp.createTempSync('aflow_inst_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final path = p.join(tmp.path, '.claude', 'commands', 'aflow-pipeline.md');
      final f = File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('OLD CONTENT');

      final report = await installCommands(
        prompts: [prompt],
        adapters: [ClaudeCommandAdapter()],
        projectRoot: tmp.path,
      );

      expect(report.files.single.existed, isTrue);
      expect(f.readAsStringSync(), isNot(contains('OLD CONTENT')));
      expect(f.readAsStringSync(), contains('# body'));
    },
  );
}
