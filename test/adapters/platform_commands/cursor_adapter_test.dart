import 'package:alea_flow/src/adapters/platform_commands/cursor/adapter.dart';
import 'package:alea_flow/src/contracts/platform_command_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final a = CursorCommandAdapter();
  const prompt = CommandPrompt(
    id: 'aflow-pipeline',
    description: 'Runs the pipeline.',
    body: '# body',
  );

  test('targetPath under .cursor/commands', () {
    expect(
      a.targetPath('aflow-pipeline', projectRoot: '/proj'),
      p.join('/proj', '.cursor', 'commands', 'aflow-pipeline.md'),
    );
  });

  test('render emits name + description frontmatter', () {
    final out = a.render(prompt);
    expect(out, contains('name: aflow-pipeline'));
    expect(out, contains('description: Runs the pipeline.'));
    expect(out, contains('# body'));
  });

  test('quotes a description containing a colon-space', () {
    const p = CommandPrompt(
      id: 'x',
      description: 'Reads ticket: then writes',
      body: 'b',
    );
    expect(
      CursorCommandAdapter().render(p),
      contains('description: "Reads ticket: then writes"'),
    );
  });
}
