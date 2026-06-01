// ALEA — load and parse the agnostic command prompts (core/commands/*.md).
//
// Reads every `aflow-*.md` file directly under a given commands directory,
// strips the leading YAML frontmatter block, and returns a list of
// [CommandPrompt] values ready for the installer to consume. Sub-directories
// (e.g. `references/`) and any file not matching the `aflow-*` prefix are
// skipped automatically.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../contracts/platform_command_adapter.dart';

/// Parse one source `.md` ([filename] like `aflow-pipeline.md`, [source] its
/// contents) into a [CommandPrompt]. Throws [FormatException] if the leading
/// `---` frontmatter block or its `description:` key is absent.
CommandPrompt parseCommandPrompt(String filename, String source) {
  final id = p.basenameWithoutExtension(filename);

  final fmMatch = RegExp(
    r'^---\r?\n(.*?)\r?\n---\r?\n',
    dotAll: true,
  ).firstMatch(source);
  if (fmMatch == null) {
    throw FormatException('$filename: missing leading --- frontmatter block');
  }
  final frontmatter = fmMatch.group(1)!;
  final body = source.substring(fmMatch.end).trimLeft();

  final descMatch = RegExp(
    r'^description:\s*(.+)$',
    multiLine: true,
  ).firstMatch(frontmatter);
  if (descMatch == null) {
    throw FormatException('$filename: frontmatter has no `description:`');
  }
  final description = descMatch.group(1)!.trim();

  return CommandPrompt(id: id, description: description, body: body);
}

/// Load every `aflow-*.md` directly under [commandsDir], excluding the
/// `references/` subfolder. Throws [FormatException] (surfaced as exit
/// 2 by the caller) if any file fails to parse.
Future<List<CommandPrompt>> loadCommandPrompts(String commandsDir) async {
  // Synchronous I/O is fine here: the command set is tiny (~19 files) and this
  // runs once at install time. The Future signature keeps the call-site async.
  final dir = Directory(commandsDir);
  final prompts = <CommandPrompt>[];
  final entries = dir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in entries) {
    final base = p.basename(f.path);
    if (!base.endsWith('.md')) continue;
    if (!base.startsWith('aflow-')) continue;
    prompts.add(parseCommandPrompt(base, f.readAsStringSync()));
  }
  return prompts;
}
