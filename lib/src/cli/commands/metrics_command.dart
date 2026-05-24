// ALEA — `aflow metrics` subcommand.
//
// Aggregates `.pipeline/metrics/history.jsonl` into the circuit-breaker signals
// `/pipeline` and `/pipeline-feedback` consume: the unreliable flag and each
// design-source adapter's hallucination rate. Replaces the prose arithmetic
// those commands previously asked the AI to do by hand (and the never-written
// `scripts/pipeline-metrics.sh`) with tested code.
//
// Exit codes: 0 = report produced · 2 = history file missing/unreadable.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../../core/metrics/metrics_aggregator.dart';

class MetricsCommand extends Command<int> {
  MetricsCommand() {
    argParser
      ..addOption(
        'history',
        defaultsTo: '.pipeline/metrics/history.jsonl',
        help: 'Path to the JSONL metrics history.',
      )
      ..addOption('window', defaultsTo: '5', help: 'Recent runs to inspect.')
      ..addOption(
        'manual-threshold',
        defaultsTo: '5',
        help: 'manual_code_corrections that marks a run bad.',
      )
      ..addOption(
        'bad-runs',
        defaultsTo: '3',
        help: 'Bad runs in the window that trip the unreliable flag.',
      )
      ..addOption(
        'circuit-min-runs',
        defaultsTo: '5',
        help: 'Min adapter runs before its breaker can trip.',
      )
      ..addOption(
        'hallucination-pct',
        defaultsTo: '20',
        help: 'Hallucination-rate %% that trips an adapter breaker.',
      )
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['text', 'json'],
        defaultsTo: 'text',
        help: 'Output format.',
      );
  }

  @override
  String get name => 'metrics';

  @override
  String get description =>
      'Aggregate pipeline run history into circuit-breaker signals.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final file = File(res['history'] as String);
    if (!file.existsSync()) {
      stderr.writeln('No metrics history at ${file.path}');
      return 2;
    }

    final thresholds = MetricsThresholds(
      window: int.parse(res['window'] as String),
      manualThreshold: int.parse(res['manual-threshold'] as String),
      badRuns: int.parse(res['bad-runs'] as String),
      circuitMinRuns: int.parse(res['circuit-min-runs'] as String),
      hallucinationPct: int.parse(res['hallucination-pct'] as String),
    );

    final parsed = parseHistory(file.readAsStringSync());
    final summary = aggregateMetrics(
      parsed.entries,
      thresholds,
      malformedLines: parsed.malformed,
    );

    final format = res['format'] as String;
    if (format == 'json') {
      stdout.writeln(jsonEncode(summary.toJson()));
      return 0;
    }

    stdout.writeln(
      'Pipeline metrics (last ${summary.windowRuns} of '
      '${summary.totalRuns} runs)',
    );
    stdout.writeln(
      '  Unreliable flag: ${summary.unreliableFlag ? "ON" : "OFF"} '
      '(${summary.manualBadCount}/${summary.windowRuns} runs '
      '>= ${thresholds.manualThreshold} manual corrections; '
      'trips at ${thresholds.badRuns})',
    );
    if (summary.adapters.isEmpty) {
      stdout.writeln('  Design-source adapters: none used in window.');
    } else {
      stdout.writeln('  Design-source adapters:');
      for (final a in summary.adapters) {
        final state = a.breakerTripped
            ? 'TRIPPED'
            : (a.shouldReset ? 'ok (reset → re-enable)' : 'ok');
        stdout.writeln(
          '    ${a.adapter}: ${(a.rate * 100).round()}% hallucination '
          '(${a.badRuns}/${a.totalRuns}) — breaker $state',
        );
      }
    }
    if (summary.malformedLines > 0) {
      stdout.writeln(
        '  ⚠ ${summary.malformedLines} malformed history line(s) skipped.',
      );
    }
    return 0;
  }
}
