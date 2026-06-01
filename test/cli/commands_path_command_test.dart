// Tests for `aflow commands-path` — locating the bundled core/commands/ dir.

import 'dart:io';

import 'package:alea_flow/src/cli/commands/commands_path_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('locateCommandsDir finds an existing core/commands directory', () async {
    final dir = await locateCommandsDir();
    expect(dir, isNotNull, reason: 'should resolve via the package config');
    expect(p.basename(dir!), 'commands');
    expect(Directory(dir).existsSync(), isTrue);
  });

  test('the located dir contains the pipeline command markdown', () async {
    final dir = await locateCommandsDir();
    expect(dir, isNotNull);
    expect(
      File(p.join(dir!, 'aflow-pipeline.md')).existsSync(),
      isTrue,
      reason: 'core/commands/ must hold the agnostic pipeline prompts',
    );
  });
}
