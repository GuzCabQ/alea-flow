// ALEA — `aflow run <ticket>` — the referee. Verifies the prior phase + runs
// its gate, then emits next_action (exit 0), BLOCKED/awaiting (exit 1), or
// error (exit 2). `--check` is reserved for the future verify-complete gate;
// for the slice it behaves like a normal run.
import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../contracts/project_config.dart';
import '../../core/config/loader.dart';
import '../../core/driver/pipeline_driver.dart';

class RunCommand extends Command<int> {
  RunCommand() {
    argParser
      ..addOption('project-root', abbr: 'r', defaultsTo: '.')
      ..addOption('schemas-dir', defaultsTo: 'contracts/schemas')
      ..addOption('mode', allowed: ['guided', 'semi', 'auto'])
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['text', 'json'],
        defaultsTo: 'text',
      )
      ..addFlag(
        'check',
        negatable: false,
        help: 'Verify-only (reserved for the future verify-complete gate).',
      );
  }

  @override
  String get name => 'run';
  @override
  String get description =>
      'Referee: verify the prior phase, run its gate, emit the next action.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final rest = res.rest;
    if (rest.isEmpty) {
      stderr.writeln('Usage: aflow run <ticket_id>');
      return 64;
    }
    final ticketId = rest.first;
    final projectRoot = p.canonicalize(res['project-root'] as String);

    final ProjectConfig config;
    try {
      config = loadProjectConfig(projectRoot);
    } on ProjectConfigException catch (e) {
      stderr.writeln('Error loading config: $e');
      return 2;
    }

    final runDir = p.join(projectRoot, '.pipeline/runs/$ticketId');
    final decision = decideRun(
      ticketId: ticketId,
      runDir: runDir,
      config: config,
      projectRoot: projectRoot,
      schemasDir: res['schemas-dir'] as String,
      requestedMode: (res['mode'] as String?) ?? config.pipeline.defaultMode,
    );

    if (res['format'] == 'json') {
      stdout.writeln(jsonEncode(decision.toJson()));
    } else {
      _printText(decision);
    }

    switch (decision.status) {
      case DriverStatus.advance:
      case DriverStatus.done:
        return 0;
      case DriverStatus.blocked:
      case DriverStatus.awaitingHuman:
        return 1;
    }
  }

  void _printText(RunDecision d) {
    stdout.writeln(
      'Run ${d.ticketId} — completed: ${d.completedPhase ?? "(none)"} · mode: ${d.mode}',
    );
    if (d.gate.violations.isNotEmpty) {
      stdout.writeln('  ✗ gate violations:');
      for (final v in d.gate.violations) {
        stdout.writeln('     - $v');
      }
    }
    for (final a in d.gate.advisories) {
      stdout.writeln('  ⚠ $a');
    }
    switch (d.status) {
      case DriverStatus.advance:
        stdout.writeln(
          '  → next: ${d.nextAction!.command}  (produces ${d.nextAction!.produces})',
        );
      case DriverStatus.awaitingHuman:
        stdout.writeln('  ⏸ awaiting human: ${d.reason}');
      case DriverStatus.blocked:
        stdout.writeln('  ⛔ BLOCKED: ${d.reason ?? "gate failed"}');
      case DriverStatus.done:
        stdout.writeln('  ✓ done: ${d.reason ?? ""}');
    }
  }
}
