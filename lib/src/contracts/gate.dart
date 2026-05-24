// ALEA — Gate contract.
//
// Every gate under alea/gates/<name>/ implements [Gate].
//
// A gate composes [Analyzer]s and external metrics (coverage %, fidelity score, format check)
// into a pass/fail decision per configurable thresholds. Gates do NOT call other gates;
// composition of gates is the responsibility of `core/commands/run-gates`.

import 'analyzer.dart';
import 'project_config.dart';

/// Context passed to every gate invocation.
class GateContext {
  /// Files produced or modified by the current pipeline phase.
  final List<String> changedFiles;

  /// Path to the run directory (`.pipeline/runs/<ticket_id>/`). Gates read prior
  /// artifacts (analysis.json, spec.json, nds.yaml, *_impl.md) from here and may
  /// write their own gate-specific outputs into subfolders.
  final String runDirectory;

  final ProjectConfig config;

  /// Layer label this gate is scoped to (`domain`, `infrastructure`, `presentation`,
  /// `bugfix`). May be null for gates that span layers.
  final String? layer;

  const GateContext({
    required this.changedFiles,
    required this.runDirectory,
    required this.config,
    this.layer,
  });
}

/// Base contract for every gate.
abstract class Gate {
  /// Stable, snake_case name (e.g. `domain`, `presentation`, `fidelity`).
  /// Matches the folder name under `alea/gates/<name>/`.
  String get name;

  /// Returns the list of analyzer names this gate runs. `core/commands/run-gates`
  /// resolves these against the registered [Analyzer] implementations.
  List<String> analyzersFor(GateContext ctx);

  /// Runs the gate. Implementations:
  ///   1. Resolve analyzers via [analyzersFor], run them concurrently.
  ///   2. Optionally compute external metrics (coverage, fidelity).
  ///   3. Apply thresholds from [ctx.config] to decide pass/fail.
  ///   4. Return a [GateReport] including any metrics captured.
  Future<GateReport> run(GateContext ctx);
}
