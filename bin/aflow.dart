// alea_flow — `aflow` CLI entry point.
//
// Thin shim that delegates every subcommand to `AleaCliRunner`. All actual
// logic lives in `lib/src/cli/` so it can be exercised by smoke tests
// without spawning a subprocess.
//
// Subcommands (run `aflow --help` for the full list):
//   - init       Bootstrap a project or feature-package skeleton.
//   - analyze    Run analyzers and produce a gate report.
//   - match      Resolve a hex/size/weight/metric against the catalog.
//   - scaffold   Generate a feature scaffold via the code-gen adapter.
//   - inventory  Scan widget classes and emit a JSON inventory.
//   - journal    Inspect a run's JSONL journal.
//   - context    Build (or reuse) the context-packet.md.

import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';

Future<void> main(List<String> args) async {
  final runner = AleaCliRunner();
  final code = await runner.run(args);
  exit(code);
}
