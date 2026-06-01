// ALEA — `aflow install-commands`. Writes the bundled pipeline prompts into
// the selected agent platforms (Claude, Gemini, Codex, Cursor) deterministically.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../adapters/platform_commands/factory.dart';
import '../../contracts/platform_command_adapter.dart';
import '../install/installer.dart';
import '../install/prompt_loader.dart';
import 'commands_path_command.dart' show locateCommandsDir;

class InstallCommandsCommand extends Command<int> {
  InstallCommandsCommand() {
    argParser
      ..addOption(
        'platform',
        help:
            'Comma-separated platforms (claude,gemini,codex,cursor) or '
            '"all". Non-interactive when set.',
      )
      ..addOption(
        'project-root',
        defaultsTo: '.',
        help: 'Project root to install into.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Show what would be written; touch no disk.',
      );
  }

  @override
  String get name => 'install-commands';

  @override
  String get description =>
      'Install the aflow-* pipeline commands into your AI agent platform '
      '(Claude Code, Gemini CLI, Codex, Cursor).';

  @override
  Future<int> run() async {
    final projectRoot = p.canonicalize(argResults!['project-root'] as String);
    final dryRun = argResults!['dry-run'] as bool;

    final dir = await locateCommandsDir();
    if (dir == null) {
      stderr.writeln(
        'Could not locate core/commands/. Install alea-flow first.',
      );
      return 2;
    }
    final List<CommandPrompt> prompts;
    try {
      prompts = await loadCommandPrompts(dir);
    } on FormatException catch (e) {
      stderr.writeln('Command prompt parse error: ${e.message}');
      return 2;
    }

    final selection = _resolveSelection();
    if (selection == null) return 64;
    if (selection.isEmpty) {
      stdout.writeln('No platforms selected; nothing to do.');
      return 0;
    }

    final InstallReport report;
    try {
      report = await installCommands(
        prompts: prompts,
        adapters: selection,
        projectRoot: projectRoot,
        dryRun: dryRun,
      );
    } on FileSystemException catch (e) {
      stderr.writeln('Failed to write command files: ${e.message}');
      return 2;
    }

    final verb = dryRun ? 'Would write' : 'Wrote';
    for (final a in selection) {
      final count = report.files
          .where((f) => f.platformId == a.platformId)
          .length;
      stdout.writeln('$verb $count command(s) for ${a.displayName}');
    }
    stdout.writeln('Invoke them as /aflow-pipeline, /aflow-analyze-ticket, …');
    return 0;
  }

  /// Selected adapters, an empty list (nothing chosen), or null on usage error.
  List<PlatformCommandAdapter>? _resolveSelection() {
    final flag = argResults!['platform'] as String?;

    if (flag != null) {
      final sel = resolvePlatformSpec(flag);
      if (sel.unknown.isNotEmpty) {
        stderr.writeln(
          'Unknown platform(s): ${sel.unknown.join(', ')}. '
          'Valid: claude, gemini, codex, cursor, all.',
        );
        return null; // -> exit 64
      }
      return sel.adapters;
    }

    if (!stdin.hasTerminal) {
      stderr.writeln(
        'Not a TTY and no --platform given. '
        'Use --platform claude,gemini,codex,cursor (or "all").',
      );
      return null;
    }
    return _promptSelection();
  }

  /// Numbered stdin multi-select over all adapters.
  List<PlatformCommandAdapter> _promptSelection() {
    final all = allAdapters();
    stdout.writeln('Select platforms to install (comma-separated numbers):');
    for (var i = 0; i < all.length; i++) {
      stdout.writeln('  ${i + 1}) ${all[i].displayName}');
    }
    stdout.write('> ');
    final line = stdin.readLineSync() ?? '';
    final picked = <PlatformCommandAdapter>[];
    for (final tok in line.split(',')) {
      final n = int.tryParse(tok.trim());
      if (n != null && n >= 1 && n <= all.length) picked.add(all[n - 1]);
    }
    return picked;
  }
}
