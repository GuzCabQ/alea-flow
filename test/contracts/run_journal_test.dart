// Tests for the RunJournal contract — JournalEvent serialization round-trip.

import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

void main() {
  group('JournalEvent', () {
    test('toJson includes required fields and skips empty optionals', () {
      final ts = DateTime.utc(2026, 5, 23, 10, 0, 0);
      final event = JournalEvent(
        timestamp: ts,
        source: 'analyzer:foo',
        kind: JournalEventKind.started,
      );
      final json = event.toJson();
      expect(json['ts'], '2026-05-23T10:00:00.000Z');
      expect(json['source'], 'analyzer:foo');
      expect(json['kind'], 'started');
      expect(json.containsKey('payload'), isFalse);
      expect(json.containsKey('correlation_id'), isFalse);
    });

    test('toJson includes payload and correlation_id when non-empty', () {
      final event = JournalEvent(
        timestamp: DateTime.utc(2026, 5, 23),
        source: 'runner',
        kind: JournalEventKind.check,
        payload: const {'issues_found': 3},
        correlationId: 'run-42',
      );
      final json = event.toJson();
      expect(json['payload'], {'issues_found': 3});
      expect(json['correlation_id'], 'run-42');
    });

    test('round-trip via toJson/fromJson preserves equality of fields', () {
      final original = JournalEvent(
        timestamp: DateTime.utc(2026, 5, 23, 12, 34, 56),
        source: 'analyzer:layer_integrity',
        kind: JournalEventKind.warning,
        payload: const {
          'score': 0.95,
          'details': {'nested': true},
          'tags': ['a', 'b'],
        },
        correlationId: 'op-1',
      );
      final json = original.toJson();
      final replay = JournalEvent.fromJson(json);
      expect(
        replay.timestamp.toIso8601String(),
        original.timestamp.toIso8601String(),
      );
      expect(replay.source, original.source);
      expect(replay.kind, original.kind);
      expect(replay.payload, original.payload);
      expect(replay.correlationId, original.correlationId);
    });

    test('fromJson rejects missing required fields', () {
      expect(
        () => JournalEvent.fromJson(const {'source': 'x', 'kind': 'started'}),
        throwsFormatException,
      );
    });

    test('fromJson rejects unknown kind', () {
      expect(
        () => JournalEvent.fromJson(const {
          'ts': '2026-05-23T00:00:00.000Z',
          'source': 'x',
          'kind': 'NOT_A_KIND',
        }),
        throwsFormatException,
      );
    });
  });
}
