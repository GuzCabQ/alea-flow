// Tests for JsonlRunJournal.
//
// Areas covered:
//   - Round-trip: record() → readAll() yields the same events.
//   - Concurrency: N parallel record() calls produce N valid JSONL lines
//     with no interleaving.
//   - PII: payload strings are redacted; a `_pii_redactions` summary is
//     appended.
//   - Lifecycle: record() after close() throws StateError.
//   - File creation: parent directories are created on demand.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('JsonlRunJournal', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('alea_journal_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('creates parent directories on demand', () async {
      final path = p.join(tmp.path, 'nested', 'sub', 'journal.jsonl');
      final j = JsonlRunJournal(path);
      await j.record(
        JournalEvent(source: 'runner', kind: JournalEventKind.started),
      );
      await j.close();
      expect(File(path).existsSync(), isTrue);
    });

    test('round-trip: record then readAll yields the same events', () async {
      final j = JsonlRunJournal.forRunDirectory(tmp.path);
      final events = <JournalEvent>[
        JournalEvent(
          timestamp: DateTime.utc(2026, 5, 23, 10),
          source: 'runner',
          kind: JournalEventKind.started,
          payload: const {'gate': 'domain'},
        ),
        JournalEvent(
          timestamp: DateTime.utc(2026, 5, 23, 10, 0, 1),
          source: 'analyzer:layer_integrity',
          kind: JournalEventKind.completed,
          payload: const {'issues_found': 0},
        ),
      ];
      for (final e in events) {
        await j.record(e);
      }
      final replay = await j.readAll().toList();
      await j.close();

      expect(replay, hasLength(2));
      expect(replay[0].source, 'runner');
      expect(replay[0].kind, JournalEventKind.started);
      expect(replay[1].source, 'analyzer:layer_integrity');
      expect(replay[1].payload['issues_found'], 0);
    });

    test(
      'concurrent record() calls produce N valid lines',
      () async {
        final j = JsonlRunJournal.forRunDirectory(tmp.path);
        const n = 100;
        await Future.wait(
          List.generate(n, (i) {
            return j.record(
              JournalEvent(
                source: 'concurrent',
                kind: JournalEventKind.check,
                payload: {'i': i},
              ),
            );
          }),
        );
        await j.close();

        final raw = File(p.join(tmp.path, 'journal.jsonl')).readAsStringSync();
        final lines = const LineSplitter()
            .convert(raw)
            .where((l) => l.trim().isNotEmpty)
            .toList();
        expect(lines, hasLength(n));
        for (final line in lines) {
          final json = jsonDecode(line);
          expect(json, isA<Map<String, Object?>>());
          expect((json as Map)['kind'], 'check');
        }
        // Every i should be represented exactly once.
        final indices = lines
            .map(
              (l) =>
                  (jsonDecode(l) as Map<String, Object?>)['payload']
                      as Map<String, Object?>,
            )
            .map((p) => p['i'] as int)
            .toSet();
        expect(indices, equals({for (var i = 0; i < n; i++) i}));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('payload strings are redacted and counts are recorded', () async {
      final j = JsonlRunJournal.forRunDirectory(tmp.path);
      await j.record(
        JournalEvent(
          source: 'analyzer:foo',
          kind: JournalEventKind.warning,
          payload: const {
            'description': 'contacto dev@example.com curp PEPE850101HDFRNS01',
          },
        ),
      );
      await j.close();

      final replay = await JsonlRunJournal.forRunDirectory(
        tmp.path,
      ).readAll().toList();
      final stored = replay.single.payload;
      final description = stored['description'] as String;
      expect(description, contains('[REDACTED:email]'));
      expect(description, contains('[REDACTED:curp]'));
      expect(description, isNot(contains('dev@example.com')));
      expect(stored['_pii_redactions'], isA<Map>());
      final counts = stored['_pii_redactions'] as Map;
      expect(counts['email'], 1);
      expect(counts['curp'], 1);
    });

    test('record() after close() throws StateError', () async {
      final j = JsonlRunJournal.forRunDirectory(tmp.path);
      await j.close();
      await expectLater(
        j.record(JournalEvent(source: 'x', kind: JournalEventKind.started)),
        throwsA(isA<StateError>()),
      );
    });

    test('close() is idempotent', () async {
      final j = JsonlRunJournal.forRunDirectory(tmp.path);
      await j.close();
      await j.close(); // must not throw
      expect(j.isClosed, isTrue);
    });

    test('readAll() on an empty/missing file yields nothing', () async {
      final j = JsonlRunJournal.forRunDirectory(tmp.path);
      final events = await j.readAll().toList();
      expect(events, isEmpty);
      await j.close();
    });
  });

  group('NullRunJournal', () {
    test('never throws and yields no events', () async {
      const j = NullRunJournal();
      await j.record(JournalEvent(source: 'x', kind: JournalEventKind.started));
      final events = await j.readAll().toList();
      expect(events, isEmpty);
      await j.close();
      await j.close(); // idempotent by definition
    });
  });
}
