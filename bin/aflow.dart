// alea_flow — `aflow` CLI entry point.
//
// Thin shim that delegates every subcommand to `AleaCliRunner`. All actual
// logic lives in `lib/src/cli/` so it can be exercised by smoke tests
// without spawning a subprocess.
//
// Subcommands are registered in `lib/src/cli/cli_runner.dart`
// (`aflow --help` lists them all). As of v0.1.1 the full set is:
//   init, analyze, match, scaffold, inventory, journal, context,
//   redact, check-files-changed, validate-artifact, metrics, run,
//   graph, graph-query.
// To add a new subcommand: one file under `lib/src/cli/commands/` +
// one `addCommand(...)` call in `AleaCliRunner._wire()`.

import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';

Future<void> main(List<String> args) async {
  final runner = AleaCliRunner();
  final code = await runner.run(args);
  exit(code);
}
