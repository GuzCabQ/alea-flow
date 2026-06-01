// ALEA — Claude Code platform adapter. Files: .claude/commands/<id>.md.

import 'package:path/path.dart' as p;

import '../../../contracts/platform_command_adapter.dart';

class ClaudeCommandAdapter implements PlatformCommandAdapter {
  @override
  String get platformId => 'claude';

  @override
  String get displayName => 'Claude Code (.claude/commands/)';

  @override
  String get argumentsToken => kAgnosticArgumentsToken;

  @override
  String targetPath(String commandId, {required String projectRoot}) =>
      p.join(projectRoot, '.claude', 'commands', '$commandId.md');

  @override
  String render(CommandPrompt prompt) {
    final body = applyArgumentsToken(prompt.body, argumentsToken);
    return '---\ndescription: ${yamlScalar(prompt.description)}\n---\n\n$body\n';
  }
}
