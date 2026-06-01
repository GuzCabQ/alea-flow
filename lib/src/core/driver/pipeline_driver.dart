// ALEA — referee state-machine.
// Given a run dir, decide what just completed, run its gate (added later), and
// emit the next action — or BLOCKED. Never calls the AI.
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../../contracts/project_config.dart';
import '../metrics/metrics_aggregator.dart';
import '../schema/schema_validator.dart';
import '../git/changed_files.dart';

enum DriverStatus { advance, awaitingHuman, blocked, done }

class NextAction {
  final String phase;
  final String command;
  final String produces;
  final bool requiresApproval;
  const NextAction({
    required this.phase,
    required this.command,
    required this.produces,
    this.requiresApproval = false,
  });
  Map<String, Object?> toJson() => {
    'phase': phase,
    'command': command,
    'produces': produces,
    'requires_approval': requiresApproval,
  };
}

class GateOutcome {
  final bool passed;
  final List<String> violations; // blocking
  final List<String> advisories; // non-blocking
  const GateOutcome({
    this.passed = true,
    this.violations = const [],
    this.advisories = const [],
  });
  Map<String, Object?> toJson() => {
    'passed': passed,
    'violations': violations,
    if (advisories.isNotEmpty) 'advisories': advisories,
  };
}

class RunDecision {
  final String ticketId;
  final String? completedPhase;
  final DriverStatus status;
  final GateOutcome gate;
  final NextAction? nextAction;
  final String mode;
  final String? reason;
  const RunDecision({
    required this.ticketId,
    required this.completedPhase,
    required this.status,
    required this.gate,
    required this.nextAction,
    required this.mode,
    this.reason,
  });
  Map<String, Object?> toJson() => {
    'ticket_id': ticketId,
    'current_phase': completedPhase,
    'status': status.name,
    'gate': gate.toJson(),
    'next_action': nextAction?.toJson(),
    'mode': mode,
    if (reason != null) 'reason': reason,
  };
}

RunDecision decideRun({
  required String ticketId,
  required String runDir,
  required ProjectConfig config,
  required String projectRoot,
  required String schemasDir,
  String requestedMode = 'guided',
  bool runGates = true,
}) {
  bool has(String f) => File(p.join(runDir, f)).existsSync();

  // Effective mode: the unreliable flag forces guided.
  var mode = requestedMode;
  final historyFile = File(
    p.join(projectRoot, '.pipeline/metrics/history.jsonl'),
  );
  if (historyFile.existsSync()) {
    final parsed = parseHistory(historyFile.readAsStringSync());
    final ut = config.pipeline.unreliableThreshold;
    final summary = aggregateMetrics(
      parsed.entries,
      MetricsThresholds(
        window: ut.runsWindow,
        manualThreshold: ut.manualCorrectionsPerRun,
        badRuns: ut.badRunsRequired,
      ),
      malformedLines: parsed.malformed,
    );
    if (summary.unreliableFlag) mode = 'guided';
  }

  // Cost gate.
  final metricsFile = File(p.join(runDir, 'metrics.json'));
  if (metricsFile.existsSync()) {
    try {
      final m = jsonDecode(metricsFile.readAsStringSync());
      final cost = (m is Map && m['estimated_cost_usd'] is num)
          ? (m['estimated_cost_usd'] as num).toDouble()
          : 0.0;
      if (cost >= config.pipeline.costHardStopUsd) {
        return RunDecision(
          ticketId: ticketId,
          completedPhase: null,
          status: DriverStatus.blocked,
          gate: const GateOutcome(passed: false),
          nextAction: null,
          mode: mode,
          reason: 'cost_limit: \$$cost >= \$${config.pipeline.costHardStopUsd}',
        );
      }
    } on FormatException {
      // malformed metrics.json → skip the cost gate (no false block)
    }
  }

  RunDecision advance(String? completed, NextAction next, GateOutcome gate) =>
      RunDecision(
        ticketId: ticketId,
        completedPhase: completed,
        status: DriverStatus.advance,
        gate: gate,
        nextAction: next,
        mode: mode,
      );

  // In guided mode every advance asks the human to confirm before the AI runs
  // the next command (the guided checkpoints from pipeline.md); semi/auto
  // advance without per-phase approval.
  NextAction action(String phase, String cmd, String produces) => NextAction(
    phase: phase,
    command: cmd,
    produces: produces,
    requiresApproval: mode == 'guided',
  );

  if (!has('analysis.json')) {
    return advance(
      null,
      action(
        'analyze',
        '/analyze-ticket $ticketId',
        '.pipeline/runs/$ticketId/analysis.json',
      ),
      const GateOutcome(),
    );
  }
  final ticketType = _readType(p.join(runDir, 'analysis.json'));
  if (ticketType == 'bugfix') {
    final aGate = runGates
        ? _validateArtifactGate(
            p.join(runDir, 'analysis.json'),
            'analysis',
            schemasDir,
            advisory: false,
          )
        : const GateOutcome();
    if (!aGate.passed) return _blocked(ticketId, 'analyze', aGate, mode);

    if (!has('implementation.md')) {
      // Gate-0 (bugfix): human checkpoint via analysis.json::approved.
      final approved = _readApproved(p.join(runDir, 'analysis.json'));
      final gate0Needed = mode == 'guided' || mode == 'semi';
      if (gate0Needed && approved != true) {
        return RunDecision(
          ticketId: ticketId,
          completedPhase: 'analyze',
          status: DriverStatus.awaitingHuman,
          gate: aGate,
          nextAction: null,
          mode: mode,
          reason:
              'set analysis.json::approved = true to proceed (Gate-0, bugfix)',
        );
      }
      return advance(
        'analyze',
        action(
          'implement-bugfix',
          '/implement-bugfix $ticketId',
          '.pipeline/runs/$ticketId/implementation.md',
        ),
        aGate,
      );
    }
    // implementation.md present → changed-files gate → done.
    final bugGate = runGates
        ? _changedFilesGate(
            projectRoot,
            _readFilesChanged(p.join(runDir, 'implementation.md')),
          )
        : const GateOutcome();
    if (!bugGate.passed) {
      return _blocked(ticketId, 'implement-bugfix', bugGate, mode);
    }
    return RunDecision(
      ticketId: ticketId,
      completedPhase: 'implement-bugfix',
      status: DriverStatus.done,
      gate: bugGate,
      nextAction: null,
      mode: mode,
      reason: 'bugfix implemented; code-review/MR are future',
    );
  }
  // === feature flow continues below (spec.json …) ===
  if (!has('spec.json')) {
    final gate = runGates
        ? _validateArtifactGate(
            p.join(runDir, 'analysis.json'),
            'analysis',
            schemasDir,
            advisory: false,
          )
        : const GateOutcome();
    if (!gate.passed) return _blocked(ticketId, 'analyze', gate, mode);
    return advance(
      'analyze',
      action(
        'design',
        '/design-feature $ticketId',
        '.pipeline/runs/$ticketId/spec.json',
      ),
      gate,
    );
  }
  final specApproved = _readApproved(p.join(runDir, 'spec.json'));
  if (specApproved != true) {
    final specGate = runGates
        ? _validateArtifactGate(
            p.join(runDir, 'spec.json'),
            'spec',
            schemasDir,
            advisory: true,
          )
        : const GateOutcome();
    final gate0Needed = mode == 'guided' || mode == 'semi';
    if (gate0Needed) {
      return RunDecision(
        ticketId: ticketId,
        completedPhase: 'design',
        status: DriverStatus.awaitingHuman,
        gate: specGate,
        nextAction: null,
        mode: mode,
        reason: 'set spec.json::approved = true to proceed (Gate-0)',
      );
    }
    // auto: Gate-0 skipped → fall through to layer loop below.
  }
  // Feature implementation — iterate layers in config order. The changed-files
  // gate compares the UNION of all present layers' declared files against the
  // working tree, so a later layer does not flag an earlier layer's files.
  final layers = config.architecture.layers.keys.toList();
  final declaredUnion = <String>{};
  for (var i = 0; i < layers.length; i++) {
    final layer = layers[i];
    if (!has('${layer}_impl.md')) {
      // Gate the cumulative prior work before advancing (nothing to gate at i==0).
      final gate = (runGates && i > 0)
          ? _changedFilesGate(projectRoot, declaredUnion)
          : const GateOutcome();
      if (!gate.passed) {
        return _blocked(ticketId, 'implement-${layers[i - 1]}', gate, mode);
      }
      final completed = i == 0 ? 'design' : 'implement-${layers[i - 1]}';
      return advance(
        completed,
        action(
          'implement-$layer',
          '/implement-$layer $ticketId',
          '.pipeline/runs/$ticketId/${layer}_impl.md',
        ),
        gate,
      );
    }
    declaredUnion.addAll(_readFilesChanged(p.join(runDir, '${layer}_impl.md')));
  }
  // All layers implemented → gate the cumulative work, then done.
  final finalGate = runGates
      ? _changedFilesGate(projectRoot, declaredUnion)
      : const GateOutcome();
  if (!finalGate.passed) {
    return _blocked(ticketId, 'implement-${layers.last}', finalGate, mode);
  }
  return RunDecision(
    ticketId: ticketId,
    completedPhase: 'implement-${layers.last}',
    status: DriverStatus.done,
    gate: finalGate,
    nextAction: null,
    mode: mode,
    reason: 'all layers implemented; review/validate/MR are future',
  );
}

GateOutcome _validateArtifactGate(
  String artifactPath,
  String schemaName,
  String schemasDir, {
  required bool advisory,
}) {
  final schemaFile = File(p.join(schemasDir, '$schemaName.schema.yaml'));
  if (!schemaFile.existsSync()) {
    return GateOutcome(
      advisories: ['schema $schemaName not found at ${schemaFile.path}'],
    );
  }
  final Object? artifact;
  try {
    artifact = jsonDecode(File(artifactPath).readAsStringSync());
  } on FormatException catch (e) {
    return GateOutcome(
      passed: false,
      violations: ['invalid JSON: ${e.message}'],
    );
  }
  final SchemaValidationResult r;
  try {
    r = validateArtifact(parseSchema(schemaFile.readAsStringSync()), artifact);
  } on Object catch (e) {
    // An unparseable schema must NOT silently pass a hard gate: respect the
    // `advisory` flag (advisory → note; hard → block).
    final msg = 'schema $schemaName could not be parsed: $e';
    return advisory
        ? GateOutcome(advisories: [msg])
        : GateOutcome(passed: false, violations: [msg]);
  }
  final msgs = r.violations.map((v) => v.toString()).toList();
  return advisory
      ? GateOutcome(advisories: msgs)
      : GateOutcome(passed: r.valid, violations: r.valid ? const [] : msgs);
}

Set<String> _readFilesChanged(String implMdPath) {
  final out = <String>{};
  final lines = const LineSplitter().convert(
    File(implMdPath).readAsStringSync(),
  );
  var inSection = false;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('#')) {
      inSection = line.toLowerCase().contains('files_changed');
      continue;
    }
    if (inSection && line.isNotEmpty) {
      out.add(line.replaceFirst(RegExp(r'^[-*]\s*'), ''));
    }
  }
  return out;
}

RunDecision _blocked(
  String ticketId,
  String phase,
  GateOutcome gate,
  String mode,
) => RunDecision(
  ticketId: ticketId,
  completedPhase: phase,
  status: DriverStatus.blocked,
  gate: gate,
  nextAction: null,
  mode: mode,
);

/// Compares the working tree's changed files against [declared] and turns the
/// result into a GateOutcome. Undeclared changes block; stale declarations are
/// advisory; a git failure degrades to advisory (never a false block).
GateOutcome _changedFilesGate(String projectRoot, Set<String> declared) {
  try {
    final cf = compareChangedFiles(
      projectRoot: projectRoot,
      declared: declared,
    );
    return cf.undeclared.isEmpty
        ? GateOutcome(
            advisories: cf.stale.map((f) => 'stale declaration: $f').toList(),
          )
        : GateOutcome(
            passed: false,
            violations: cf.undeclared
                .map((f) => 'changed but not declared: $f')
                .toList(),
          );
  } on ChangedFilesException catch (e) {
    return GateOutcome(
      advisories: ['files-changed gate skipped: ${e.message}'],
    );
  }
}

bool? _readApproved(String path) {
  try {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is Map && decoded['approved'] is bool) {
      return decoded['approved'] as bool;
    }
  } on Object {
    return null;
  }
  return null;
}

String? _readType(String path) {
  try {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is Map && decoded['type'] is String) {
      return decoded['type'] as String;
    }
  } on Object {
    return null;
  }
  return null;
}
