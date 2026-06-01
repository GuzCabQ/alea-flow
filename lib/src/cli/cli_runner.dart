// ALEA — CLI runner.
//
// Single dispatch point for every subcommand. `bin/alea.dart` is a thin
// shim over this class; tests instantiate it directly and capture stdout/
// stderr via `IOOverrides.runZoned` to verify behaviour without spawning
// subprocesses.
//
// Adding a new subcommand:
//   1. Create `lib/src/cli/commands/<name>_command.dart` implementing
//      `Command<int>`.
//   2. Register it in [AleaCliRunner._wire] alongside the existing ones.
//   3. Add a smoke test under `test/cli/<name>_command_test.dart`.

import 'package:args/command_runner.dart';

import 'commands/analyze_command.dart';
import 'commands/check_files_changed_command.dart';
import 'commands/commands_path_command.dart';
import 'commands/context_command.dart';
import 'commands/graph_command.dart';
import 'commands/graph_query_command.dart';
import 'commands/init_command.dart';
import 'commands/install_commands_command.dart';
import 'commands/inventory_command.dart';
import 'commands/journal_command.dart';
import 'commands/match_command.dart';
import 'commands/metrics_command.dart';
import 'commands/redact_command.dart';
import 'commands/run_command.dart';
import 'commands/scaffold_command.dart';
import 'commands/validate_artifact_command.dart';

class AleaCliRunner extends CommandRunner<int> {
  AleaCliRunner()
    : super(
        'aflow',
        'Flutter pipeline CLI from the ALEA suite — '
            'init, analyze, match, scaffold, inventory, journal, context, '
            'redact, check-files-changed, validate-artifact, metrics, run, '
            'graph, graph-query, commands-path.',
      ) {
    _wire();
  }

  void _wire() {
    addCommand(InitCommand());
    addCommand(AnalyzeCommand());
    addCommand(MatchCommand());
    addCommand(ScaffoldCommand());
    addCommand(InventoryCommand());
    addCommand(JournalCommand());
    addCommand(ContextCommand());
    addCommand(RedactCommand());
    addCommand(CheckFilesChangedCommand());
    addCommand(ValidateArtifactCommand());
    addCommand(MetricsCommand());
    addCommand(RunCommand());
    addCommand(GraphCommand());
    addCommand(GraphQueryCommand());
    addCommand(CommandsPathCommand());
    addCommand(InstallCommandsCommand());
  }

  /// Execute [args] and return the process exit code without ever calling
  /// `exit()` directly. Tests rely on this — production code in
  /// `bin/alea.dart` forwards the return value to `exit(...)`.
  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final result = await super.run(args);
      return result ?? 0;
    } on UsageException catch (e) {
      // Mirror CommandRunner's default behaviour but DON'T exit — let the
      // caller decide.
      // ignore: avoid_print
      print(e.message);
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print(e.usage);
      return 64; // EX_USAGE
    }
  }
}
