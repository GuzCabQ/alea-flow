// ALEA — Cursor platform adapter. Files: .cursor/commands/<id>.md.
//
// Verified facts (cursor.com/docs/reference/plugins, cursor.com/docs/reference/deeplinks):
//   - Project-scoped custom commands live in `.cursor/commands/<id>.md`.
//   - Files support YAML frontmatter with `name` and `description` fields.
//   - No platform-specific argument placeholder token is documented; the
//     agnostic $ARGUMENTS token is left as-is (no translation needed).

import 'package:path/path.dart' as p;

import '../../../contracts/platform_command_adapter.dart';

class CursorCommandAdapter implements PlatformCommandAdapter {
  @override
  String get platformId => 'cursor';

  @override
  String get displayName => 'Cursor (.cursor/commands/)';

  @override
  String get argumentsToken => kAgnosticArgumentsToken;

  @override
  String targetPath(String commandId, {required String projectRoot}) =>
      p.join(projectRoot, '.cursor', 'commands', '$commandId.md');

  @override
  String render(CommandPrompt prompt) {
    final body = applyArgumentsToken(prompt.body, argumentsToken);
    return '---\nname: ${yamlScalar(prompt.id)}\ndescription: ${yamlScalar(prompt.description)}\n'
        '---\n\n$body\n';
  }
}
