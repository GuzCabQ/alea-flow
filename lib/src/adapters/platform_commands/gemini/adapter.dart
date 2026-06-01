// ALEA — Gemini CLI platform adapter. Files: .gemini/commands/<id>.toml.

import 'package:path/path.dart' as p;

import '../../../contracts/platform_command_adapter.dart';

class GeminiCommandAdapter implements PlatformCommandAdapter {
  @override
  String get platformId => 'gemini';

  @override
  String get displayName => 'Gemini CLI (.gemini/commands/)';

  @override
  String get argumentsToken => '{{args}}';

  @override
  String targetPath(String commandId, {required String projectRoot}) =>
      p.join(projectRoot, '.gemini', 'commands', '$commandId.toml');

  @override
  String render(CommandPrompt prompt) {
    final body = applyArgumentsToken(prompt.body, argumentsToken);
    return 'description = "${_escapeToml(prompt.description)}"\n\n'
        'prompt = """\n${_escapeToml(body)}\n"""\n';
  }

  /// Escapes a string for embedding inside a TOML basic string. Backslashes
  /// MUST be escaped before quotes; escaping every `"` also prevents an
  /// accidental `"""` from closing the multiline string early.
  static String _escapeToml(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
