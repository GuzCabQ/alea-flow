// ALEA — Codex platform adapter. Codex custom prompts are GLOBAL: they live in
// $CODEX_HOME/prompts/ (default ~/.codex/prompts/), not in the project repo.
//
// Verified facts (openai/codex official docs):
//   - $CODEX_HOME defaults to ~/.codex; prompts are stored as <name>.md files
//     inside the prompts/ subdirectory.
//   - Prompt files support YAML frontmatter with `description` and the optional
//     `argument-hint` field.
//   - $ARGUMENTS is a natively supported Codex placeholder (alongside $1,
//     $FILE, $TICKET_ID). The default agnostic token is therefore correct as-is;
//     no translation is needed.
//   - Custom prompts are deprecated upstream in favor of "skills", but they
//     continue to work in the current Codex release. A future skills-based
//     adapter may supersede this one.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../contracts/platform_command_adapter.dart';

class CodexCommandAdapter implements PlatformCommandAdapter {
  /// Resolved Codex home. Falls back to `$CODEX_HOME`, then `~/.codex`.
  final String codexHome;

  CodexCommandAdapter({String? codexHome})
    : codexHome = codexHome ?? _defaultCodexHome();

  static String _defaultCodexHome() {
    final env = Platform.environment['CODEX_HOME']?.trim();
    if (env != null && env.isNotEmpty) return env;
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.'; // last-resort only; HOME/USERPROFILE is set on all real environments
    return p.join(home, '.codex');
  }

  @override
  String get platformId => 'codex';

  @override
  String get displayName => 'Codex (global → ~/.codex/prompts)';

  // $ARGUMENTS is a supported Codex placeholder, so the agnostic default token
  // is correct and requires no platform-specific translation.
  @override
  String get argumentsToken => kAgnosticArgumentsToken;

  @override
  String targetPath(String commandId, {required String projectRoot}) =>
      p.join(codexHome, 'prompts', '$commandId.md');

  @override
  String render(CommandPrompt prompt) {
    final body = applyArgumentsToken(prompt.body, argumentsToken);
    return '---\ndescription: ${yamlScalar(prompt.description)}\n'
        'argument-hint: command arguments\n---\n\n$body\n';
  }
}
