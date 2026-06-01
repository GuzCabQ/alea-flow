// ALEA — `aflow commands-path` subcommand.
//
// Prints the absolute path to the bundled, platform-agnostic pipeline prompts
// (`core/commands/`). This is the "WHERE" half of command distribution: the CLI
// (deterministic) tells you where the prompts live regardless of how `aflow`
// was installed; your AI agent does the "HOW" (installs them into its own
// platform's command/skill directory — see core/commands/INSTALL.md).

import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// Locate the package's `core/commands/` directory regardless of install method
/// (`dart pub global activate`, git-clone + compile + symlink, or `dart run`).
/// Returns the absolute, normalized path, or null if it cannot be found.
Future<String?> locateCommandsDir() async {
  // Strategy 1: package URI resolution — works for `dart run` and
  // `dart pub global activate` (both keep a package config at runtime).
  try {
    final libUri = await Isolate.resolvePackageUri(
      Uri.parse('package:alea_flow/alea_flow.dart'),
    );
    if (libUri != null && libUri.scheme == 'file') {
      final libDir = p.dirname(p.fromUri(libUri)); // <root>/lib
      final candidate = p.normalize(p.join(libDir, '..', 'core', 'commands'));
      if (Directory(candidate).existsSync()) return candidate;
    }
  } catch (_) {
    // resolvePackageUri can throw in some embeddings; fall through.
  }

  // Strategy 2: relative to the resolved executable — for an AOT binary
  // (possibly symlinked into PATH; resolvedExecutable points at the real file,
  // e.g. <root>/bin/aflow → <root>/core/commands).
  final exe = Platform.resolvedExecutable;
  final exeDir = p.dirname(exe);
  for (final rel in [
    p.join(exeDir, '..', 'core', 'commands'),
    p.join(exeDir, 'core', 'commands'),
  ]) {
    final candidate = p.normalize(rel);
    if (Directory(candidate).existsSync()) return candidate;
  }

  // Strategy 3: relative to the entry script — `dart run bin/aflow.dart`.
  if (Platform.script.scheme == 'file') {
    final scriptDir = p.dirname(p.fromUri(Platform.script)); // <root>/bin
    final candidate = p.normalize(p.join(scriptDir, '..', 'core', 'commands'));
    if (Directory(candidate).existsSync()) return candidate;
  }

  return null;
}

class CommandsPathCommand extends Command<int> {
  @override
  String get name => 'commands-path';

  @override
  String get description =>
      'Print the absolute path to the bundled pipeline prompts (core/commands/), '
      'so your AI agent can install them. Works regardless of how aflow was installed.';

  @override
  Future<int> run() async {
    final dir = await locateCommandsDir();
    if (dir == null) {
      stderr.writeln(
        'Could not locate core/commands/. If you installed via `git clone`, run '
        'aflow from inside the repo; if via pub, ensure the published package '
        'includes core/commands/.',
      );
      return 2;
    }
    stdout.writeln(dir);
    return 0;
  }
}
