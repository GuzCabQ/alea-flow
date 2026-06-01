import 'package:alea_flow/src/adapters/platform_commands/codex/adapter.dart';
import 'package:alea_flow/src/contracts/platform_command_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const prompt = CommandPrompt(
    id: 'aflow-pipeline',
    description: 'Runs the pipeline.',
    body: '# body',
  );

  test('targetPath honors CODEX_HOME', () {
    final a = CodexCommandAdapter(codexHome: '/home/u/.codex');
    expect(
      a.targetPath('aflow-pipeline', projectRoot: '/proj'),
      p.join('/home/u/.codex', 'prompts', 'aflow-pipeline.md'),
    );
  });

  test('render emits description + argument-hint frontmatter', () {
    final a = CodexCommandAdapter(codexHome: '/x');
    final out = a.render(prompt);
    expect(out, contains('description: Runs the pipeline.'));
    expect(out, contains('argument-hint:'));
    expect(out, contains('# body'));
  });

  test('quotes a description containing a colon-space', () {
    const p = CommandPrompt(
      id: 'x',
      description: 'Reads ticket: then writes',
      body: 'b',
    );
    expect(
      CodexCommandAdapter(codexHome: '/x').render(p),
      contains('description: "Reads ticket: then writes"'),
    );
  });
}
