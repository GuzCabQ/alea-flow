// ALEA — Platform command adapter contract.
//
// The pipeline prompts in `core/commands/*.md` are platform-agnostic. Each
// folder under `lib/src/adapters/platform_commands/<platform>/` implements
// [PlatformCommandAdapter]: it knows WHERE a command file goes for that
// platform and in WHAT format to render it. Writing to disk and prompting the
// user are the CLI's job (`lib/src/cli/install/`), not the adapter's.

/// Agnostic, parsed representation of one `aflow-*.md` command prompt.
class CommandPrompt {
  /// Filename without extension, e.g. `aflow-pipeline`. Becomes the command
  /// name (`/aflow-pipeline`) on every platform.
  final String id;

  /// One-line summary, from the source frontmatter `description:`.
  final String description;

  /// Markdown body with the frontmatter block stripped.
  final String body;

  const CommandPrompt({
    required this.id,
    required this.description,
    required this.body,
  });
}

/// Returns [value] formatted as a YAML scalar safe to emit after `key: `.
/// Plain scalars with no YAML-significant constructs are returned unchanged;
/// anything risky (leading indicator, `": "`, trailing `:`, ` #`, surrounding
/// whitespace, or empty) is double-quoted with `\` and `"` escaped.
String yamlScalar(String value) {
  final needsQuote =
      value.isEmpty ||
      value != value.trim() ||
      RegExp(r'''^[-?:,\[\]{}#&*!|>'"%@`]''').hasMatch(value) ||
      value.contains(': ') ||
      value.endsWith(':') ||
      value.contains(' #');
  if (!needsQuote) return value;
  return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

/// The `$ARGUMENTS` placeholder used in the agnostic prompt bodies.
const String kAgnosticArgumentsToken = r'$ARGUMENTS';

/// Rewrites the agnostic `$ARGUMENTS` placeholder to [token]. A no-op when
/// [token] equals [kAgnosticArgumentsToken].
String applyArgumentsToken(String body, String token) {
  if (token == kAgnosticArgumentsToken) return body;
  return body.replaceAll(kAgnosticArgumentsToken, token);
}

/// Per-platform strategy: where a command file goes and how it is formatted.
abstract interface class PlatformCommandAdapter {
  /// Stable identifier used by `--platform` and the factory (`claude`,
  /// `gemini`, `codex`, `cursor`).
  String get platformId;

  /// Label shown in the interactive menu and final report.
  String get displayName;

  /// The platform's argument placeholder. Defaults to [kAgnosticArgumentsToken]
  /// (leave `$ARGUMENTS` untouched).
  String get argumentsToken => kAgnosticArgumentsToken;

  /// Absolute path where [commandId]'s file is written for this platform.
  String targetPath(String commandId, {required String projectRoot});

  /// Complete file content (platform frontmatter/format + body).
  ///
  /// Implementations MUST apply [applyArgumentsToken] to `prompt.body` (with
  /// their [argumentsToken]) before embedding it, so the agnostic `$ARGUMENTS`
  /// placeholder becomes the platform's own argument token.
  String render(CommandPrompt prompt);
}
