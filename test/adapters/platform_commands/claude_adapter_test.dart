import 'package:alea_flow/src/adapters/platform_commands/claude/adapter.dart';
import 'package:alea_flow/src/contracts/platform_command_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final a = ClaudeCommandAdapter();
  const prompt = CommandPrompt(
    id: 'aflow-pipeline',
    description: 'Runs the pipeline.',
    body: '# body\n\$ARGUMENTS',
  );

  test('platformId and targetPath', () {
    expect(a.platformId, 'claude');
    expect(
      a.targetPath('aflow-pipeline', projectRoot: '/proj'),
      p.join('/proj', '.claude', 'commands', 'aflow-pipeline.md'),
    );
  });

  test('render emits description frontmatter + body, keeps \$ARGUMENTS', () {
    final out = a.render(prompt);
    expect(out, startsWith('---\ndescription: Runs the pipeline.\n---\n'));
    expect(out, contains('# body'));
    expect(out, contains('\$ARGUMENTS'));
  });

  test('quotes a description containing a colon-space', () {
    const p = CommandPrompt(
      id: 'x',
      description: 'Reads ticket: then writes',
      body: 'b',
    );
    expect(
      ClaudeCommandAdapter().render(p),
      contains('description: "Reads ticket: then writes"'),
    );
  });
}
