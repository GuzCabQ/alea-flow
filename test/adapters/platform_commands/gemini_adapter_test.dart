import 'package:alea_flow/src/adapters/platform_commands/gemini/adapter.dart';
import 'package:alea_flow/src/contracts/platform_command_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final a = GeminiCommandAdapter();
  const prompt = CommandPrompt(
    id: 'aflow-pipeline',
    description: 'Runs the pipeline.',
    body: r'Do $ARGUMENTS now.',
  );

  test('targetPath is a .toml under .gemini/commands', () {
    expect(
      a.targetPath('aflow-pipeline', projectRoot: '/proj'),
      p.join('/proj', '.gemini', 'commands', 'aflow-pipeline.toml'),
    );
  });

  test(
    'render wraps body in TOML prompt and rewrites \$ARGUMENTS to {{args}}',
    () {
      final out = a.render(prompt);
      expect(out, contains('description = "Runs the pipeline."'));
      expect(out, contains('prompt = """'));
      expect(out, contains('Do {{args}} now.'));
      expect(out, isNot(contains(r'$ARGUMENTS')));
    },
  );

  test('escapes double-quotes in the description', () {
    const p = CommandPrompt(id: 'x', description: 'Say "hi"', body: 'b');
    expect(a.render(p), contains(r'description = "Say \"hi\""'));
  });

  test(
    'escapes backslashes and quotes in the body (no stray triple-quote)',
    () {
      const p = CommandPrompt(
        id: 'x',
        description: 'd',
        body: r'path C:\re "x" """',
      );
      final out = a.render(p);
      // backslash escaped first, then quotes — so the body region contains no
      // unescaped " and no accidental closing delimiter.
      expect(out, contains(r'path C:\\re \"x\" \"\"\"'));
    },
  );
}
