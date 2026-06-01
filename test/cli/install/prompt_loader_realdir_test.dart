// test/cli/install/prompt_loader_realdir_test.dart
import 'package:alea_flow/src/cli/commands/commands_path_command.dart';
import 'package:alea_flow/src/cli/install/prompt_loader.dart';
import 'package:test/test.dart';

void main() {
  test(
    'every bundled aflow-*.md parses and has a non-empty description',
    () async {
      final dir = await locateCommandsDir();
      expect(dir, isNotNull);
      final prompts = await loadCommandPrompts(dir!);
      expect(prompts.length, greaterThanOrEqualTo(18));
      for (final p in prompts) {
        expect(p.id, startsWith('aflow-'));
        expect(
          p.description,
          isNotEmpty,
          reason: '${p.id} needs a description',
        );
      }
    },
  );
}
