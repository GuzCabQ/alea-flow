import 'package:alea_flow/src/cli/install/prompt_loader.dart';
import 'package:test/test.dart';

void main() {
  const src = '''---
description: Runs the full ALEA pipeline.
---
# `/aflow-pipeline` — Orchestrator

Body text with \$ARGUMENTS.
''';

  test('parseCommandPrompt extracts id, description, stripped body', () {
    final p = parseCommandPrompt('aflow-pipeline.md', src);
    expect(p.id, 'aflow-pipeline');
    expect(p.description, 'Runs the full ALEA pipeline.');
    expect(p.body, startsWith('# `/aflow-pipeline`'));
    expect(p.body, isNot(contains('description:')));
  });

  test('parseCommandPrompt throws when there is no frontmatter block', () {
    const noDesc = '# `/aflow-x` — X\n\nbody';
    expect(
      () => parseCommandPrompt('aflow-x.md', noDesc),
      throwsA(isA<FormatException>()),
    );
  });

  test('throws when frontmatter has no description key', () {
    const noDesc = '---\ntitle: X\n---\n# `/aflow-x` — X\n\nbody';
    expect(
      () => parseCommandPrompt('aflow-x.md', noDesc),
      throwsA(isA<FormatException>()),
    );
  });
}
