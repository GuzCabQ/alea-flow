// Tests for the PII redactor.
//
// The redactor must be:
//   - Conservative (better to over-redact than leak PII to logs).
//   - Deterministic (same input → same output, same counts).
//   - Order-stable across the documented pattern catalog.

import 'package:test/test.dart';

// Internal import is acceptable here — these are package tests of an
// implementation detail in lib/src/core/journal/.
import 'package:alea_flow/src/core/journal/pii_redactor.dart';

void main() {
  group('redactString', () {
    test('redacts CURP', () {
      final r = redactString('mi curp es PEPE850101HDFRNS01 ok');
      expect(r.text, contains('[REDACTED:curp]'));
      expect(r.counts['curp'], 1);
    });

    test('redacts email', () {
      final r = redactString('contacto: foo.bar@example.com.');
      expect(r.text, contains('[REDACTED:email]'));
      expect(r.counts['email'], 1);
    });

    test('redacts CLABE before generic card', () {
      // An 18-digit run must be classified as CLABE, not card.
      final r = redactString('cuenta 012345678901234567');
      expect(r.counts.containsKey('clabe'), isTrue);
      expect(r.counts['card'] ?? 0, 0);
    });

    test('redacts a 16-digit card', () {
      final r = redactString('tarjeta 4111111111111111 venció');
      expect(r.counts['card'], 1);
      expect(r.text, contains('[REDACTED:card]'));
    });

    test('redacts a 10-digit MX phone with country prefix', () {
      final r = redactString('llamar al +521 5512345678');
      expect(r.counts['phone'], 1);
    });

    test('returns text unchanged when nothing matches', () {
      final r = redactString('texto sin PII');
      expect(r.text, 'texto sin PII');
      expect(r.counts, isEmpty);
    });

    test('multiple patterns in one string are all redacted', () {
      final r = redactString(
        'CURP PEPE850101HDFRNS01 mail dev@example.com tel 5512345678',
      );
      expect(r.text.contains('[REDACTED:curp]'), isTrue);
      expect(r.text.contains('[REDACTED:email]'), isTrue);
      expect(r.text.contains('[REDACTED:phone]'), isTrue);
      expect(r.counts['curp'], 1);
      expect(r.counts['email'], 1);
      expect(r.counts['phone'], 1);
    });
  });

  group('redactPayload', () {
    test('recursively redacts string leaves', () {
      final input = <String, Object?>{
        'titulo': 'Reclamo de Pepe',
        'cuerpo': 'curp PEPE850101HDFRNS01 contacto dev@example.com',
        'metadata': {
          'tags': ['ok', 'mail otro@ejemplo.mx'],
          'count': 3,
        },
      };
      final result = redactPayload(input);
      expect(result.payload['titulo'], 'Reclamo de Pepe');
      final cuerpo = result.payload['cuerpo'] as String;
      expect(cuerpo, contains('[REDACTED:curp]'));
      expect(cuerpo, contains('[REDACTED:email]'));
      final meta = result.payload['metadata'] as Map<String, Object?>;
      final tags = meta['tags'] as List;
      expect(tags[1], contains('[REDACTED:email]'));
      expect(result.counts['email'], 2);
      expect(result.counts['curp'], 1);
    });

    test('does not mutate the input map', () {
      final input = <String, Object?>{'leak': 'dev@example.com'};
      redactPayload(input);
      expect(input['leak'], 'dev@example.com');
    });
  });
}
