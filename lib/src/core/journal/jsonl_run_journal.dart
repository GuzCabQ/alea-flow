// ALEA — JsonlRunJournal.
//
// Default file-backed implementation of [RunJournal]. Writes one JSON object
// per line (JSONL) to the configured file. Concurrent [record] calls are
// serialized through an internal `Future` chain so the file never sees
// interleaved bytes.
//
// File layout:
//   <runDirectory>/journal.jsonl
//
// Each line is exactly one JSON object produced by [JournalEvent.toJson],
// with payload string values run through the PII redactor first.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../contracts/run_journal.dart';
import 'pii_redactor.dart';

class JsonlRunJournal implements RunJournal {
  final File _file;
  Future<void> _writeChain = Future<void>.value();
  bool _closed = false;

  /// Open (or create) a journal file at [filePath]. The parent directory is
  /// created on demand. The file is opened in append mode — existing
  /// contents are preserved across restarts.
  JsonlRunJournal(String filePath) : _file = File(filePath) {
    final parent = Directory(p.dirname(filePath));
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
  }

  /// Convenience: build a JsonlRunJournal at `<runDirectory>/journal.jsonl`.
  factory JsonlRunJournal.forRunDirectory(String runDirectory) {
    return JsonlRunJournal(p.join(runDirectory, 'journal.jsonl'));
  }

  @override
  Future<void> record(JournalEvent event) {
    if (_closed) {
      return Future.error(
        StateError(
          'JsonlRunJournal: record() called after close() on ${_file.path}',
        ),
      );
    }
    final scrubbed = redactPayload(event.payload);
    final mergedPayload = <String, Object?>{
      ...scrubbed.payload,
      if (scrubbed.counts.isNotEmpty) '_pii_redactions': scrubbed.counts,
    };
    final scrubbedEvent = JournalEvent(
      timestamp: event.timestamp,
      source: event.source,
      kind: event.kind,
      payload: mergedPayload,
      correlationId: event.correlationId,
    );
    final line = '${jsonEncode(scrubbedEvent.toJson())}\n';

    final completer = Completer<void>();
    _writeChain = _writeChain.then((_) async {
      try {
        await _file.writeAsString(line, mode: FileMode.append, flush: true);
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  @override
  Stream<JournalEvent> readAll() async* {
    if (!_file.existsSync()) return;
    await _writeChain; // make sure all pending writes are flushed
    final raw = await _file.readAsString();
    for (final line in const LineSplitter().convert(raw)) {
      if (line.trim().isEmpty) continue;
      final json = jsonDecode(line);
      if (json is! Map<String, Object?>) continue;
      yield JournalEvent.fromJson(json);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await _writeChain;
    _closed = true;
  }

  /// Test/debug helper — true after [close] has run.
  bool get isClosed => _closed;
}
