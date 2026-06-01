import 'package:alea_flow/src/contracts/platform_command_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('CommandPrompt', () {
    test('holds id/description/body', () {
      const p = CommandPrompt(
        id: 'aflow-pipeline',
        description: 'Runs the full ALEA pipeline.',
        body: '# body\n\$ARGUMENTS',
      );
      expect(p.id, 'aflow-pipeline');
      expect(p.description, 'Runs the full ALEA pipeline.');
      expect(p.body, contains('\$ARGUMENTS'));
    });
  });

  group('applyArgumentsToken', () {
    test('rewrites \$ARGUMENTS to the platform token', () {
      expect(
        applyArgumentsToken('do \$ARGUMENTS now', '{{args}}'),
        'do {{args}} now',
      );
    });

    test('with the default token is a no-op', () {
      expect(
        applyArgumentsToken('do \$ARGUMENTS', r'$ARGUMENTS'),
        'do \$ARGUMENTS',
      );
    });

    test('replaces every occurrence', () {
      expect(
        applyArgumentsToken('\$ARGUMENTS and \$ARGUMENTS', '{{a}}'),
        '{{a}} and {{a}}',
      );
    });
  });
}
