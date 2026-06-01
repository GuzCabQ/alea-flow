// ALEA — `aflow journal` subcommand.
//
// Reads the JSONL journal produced by analyzers and orchestrators in a
// given run directory and prints a human-readable summary (counts per
// source/kind) or the raw JSONL stream.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../contracts/run_journal.dart';
import '../../core/journal/jsonl_run_journal.dart';

class JournalCommand extends Command<int> {
  JournalCommand() {
    argParser
      ..addOption(
        'run-directory',
        abbr: 'd',
        help:
            'Path to the pipeline run directory '
            '(e.g. .pipeline/runs/DEV-XXXX/).',
        mandatory: true,
      )
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['summary', 'jsonl'],
        defaultsTo: 'summary',
        help: 'Output format.',
      );
  }

  @override
  String get name => 'journal';

  @override
  String get description => 'Inspect the JSONL run journal of a pipeline run.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final runDir = p.canonicalize(res['run-directory'] as String);
    final format = res['format'] as String;

    final journalPath = p.join(runDir, 'journal.jsonl');
    if (!File(journalPath).existsSync()) {
      stderr.writeln('No journal.jsonl at $journalPath');
      return 2;
    }

    final journal = JsonlRunJournal.forRunDirectory(runDir);
    final List<JournalEvent> events;
    try {
      events = await journal.readAll().toList();
    } on FormatException catch (e) {
      stderr.writeln('Error: malformed journal at $journalPath: $e');
      return 2;
    } finally {
      await journal.close();
    }

    if (format == 'jsonl') {
      for (final e in events) {
        stdout.writeln(jsonEncode(e.toJson()));
      }
      return 0;
    }

    // Summary: count events per (source, kind).
    final perSource = <String, Map<JournalEventKind, int>>{};
    for (final e in events) {
      final byKind = perSource.putIfAbsent(e.source, () => {});
      byKind[e.kind] = (byKind[e.kind] ?? 0) + 1;
    }

    stdout.writeln('Journal: $journalPath');
    stdout.writeln('Events:  ${events.length}');
    stdout.writeln('');
    stdout.writeln(
      '${"source".padRight(40)} '
      '${"started".padRight(8)} ${"completed".padRight(10)} '
      '${"warning".padRight(8)} ${"error".padRight(6)} '
      '${"check".padRight(6)}',
    );
    stdout.writeln('-' * 80);
    final sortedSources = perSource.keys.toList()..sort();
    for (final source in sortedSources) {
      final c = perSource[source]!;
      String n(JournalEventKind k) => (c[k] ?? 0).toString();
      stdout.writeln(
        '${source.padRight(40)} '
        '${n(JournalEventKind.started).padRight(8)} '
        '${n(JournalEventKind.completed).padRight(10)} '
        '${n(JournalEventKind.warning).padRight(8)} '
        '${n(JournalEventKind.error).padRight(6)} '
        '${n(JournalEventKind.check).padRight(6)}',
      );
    }
    return 0;
  }
}
