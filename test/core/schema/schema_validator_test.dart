// Unit tests for the artifact schema validator, exercised against the REAL
// analysis.schema.yaml. This doubles as the evidence base for freezing that
// schema (F1): it proves the schema accepts valid artifacts and rejects the
// concrete invalid shapes below.

import 'dart:io';

import 'package:alea_flow/src/core/schema/schema_validator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('validateArtifact against analysis.schema.yaml', () {
    late Map schema;

    setUp(() {
      final path = p.join(
        Directory.current.path,
        'contracts/schemas/analysis.schema.yaml',
      );
      schema = parseSchema(File(path).readAsStringSync());
    });

    Map<String, Object?> validBugfix() => {
      'ticket_id': 'DEV-1234',
      'type': 'bugfix',
      'title': 'Fix crash on tap',
      'description': 'The button crashes when tapped twice.',
      'success_criteria': ['no crash on double tap'],
      'created_at': '2026-05-28T10:00:00Z',
      'bug_description': 'Double tap triggers a null deref.',
      'root_cause_hypothesis': 'Missing mounted guard after await.',
      'pii_sanitized': true,
      'ticket_source': {
        'adapter': 'file',
        'fetched_at': '2026-05-28T10:00:00Z',
      },
    };

    test('a complete valid bugfix artifact passes', () {
      final r = validateArtifact(schema, validBugfix());
      expect(r.valid, isTrue, reason: r.violations.join('; '));
    });

    test('a valid feature artifact passes (required_when feature)', () {
      final feature = validBugfix()
        ..remove('bug_description')
        ..remove('root_cause_hypothesis')
        ..['type'] = 'feature'
        ..['feature_description'] = 'Add a profile screen.'
        ..['new_components'] = {
          'entities': ['Profile'],
          'screens': ['ProfileScreen'],
        };
      final r = validateArtifact(schema, feature);
      expect(r.valid, isTrue, reason: r.violations.join('; '));
    });

    test('missing a required field is reported', () {
      final a = validBugfix()..remove('title');
      final r = validateArtifact(schema, a);
      expect(r.valid, isFalse);
      expect(r.violations.map((v) => v.path), contains('title'));
    });

    test('enum violation is reported', () {
      final a = validBugfix()..['type'] = 'banana';
      final r = validateArtifact(schema, a);
      expect(r.violations.any((v) => v.path == 'type'), isTrue);
    });

    test('pattern violation on ticket_id is reported', () {
      final a = validBugfix()..['ticket_id'] = 'not a ticket';
      final r = validateArtifact(schema, a);
      expect(r.violations.any((v) => v.path == 'ticket_id'), isTrue);
    });

    test('required_when: bugfix without bug_description fails', () {
      final a = validBugfix()..remove('bug_description');
      final r = validateArtifact(schema, a);
      expect(r.violations.any((v) => v.path == 'bug_description'), isTrue);
    });

    test('min_items: empty success_criteria fails', () {
      final a = validBugfix()..['success_criteria'] = <String>[];
      final r = validateArtifact(schema, a);
      expect(r.violations.any((v) => v.path == 'success_criteria'), isTrue);
    });

    test('nested object: ticket_source missing adapter fails', () {
      final a = validBugfix()
        ..['ticket_source'] = {'fetched_at': '2026-05-28T10:00:00Z'};
      final r = validateArtifact(schema, a);
      expect(
        r.violations.any((v) => v.path == 'ticket_source.adapter'),
        isTrue,
      );
    });

    test('list<AttachmentRef>: element missing uri fails', () {
      final a = validBugfix()
        ..['attachments'] = [
          {'kind': 'image'}, // missing uri
        ];
      final r = validateArtifact(schema, a);
      expect(r.violations.any((v) => v.path == 'attachments[0].uri'), isTrue);
    });

    test('a valid attachment passes', () {
      final a = validBugfix()
        ..['attachments'] = [
          {
            'kind': 'link',
            'uri': 'https://figma.com/x',
            'description': 'figma',
          },
        ];
      final r = validateArtifact(schema, a);
      expect(r.valid, isTrue, reason: r.violations.join('; '));
    });

    test('non-object artifact root fails cleanly', () {
      final r = validateArtifact(schema, ['not', 'an', 'object']);
      expect(r.valid, isFalse);
    });
  });

  group('required_when honesty (the _evalCondition fix)', () {
    test('parseable == condition is enforced', () {
      final s = parseSchema('''
required: [a]
a: { type: string }
b:
  type: string | null
  required_when: "a == x"
''');
      // a == x holds and b is missing → must be a violation on b.
      final r = validateArtifact(s, {'a': 'x'});
      expect(r.violations.any((v) => v.path == 'b'), isTrue);
    });

    test(
      'unparseable condition is recorded in skipped, not silently dropped',
      () {
        final s = parseSchema('''
required: [a]
a: { type: string }
b:
  type: string | null
  required_when: "a != x"
''');
        final r = validateArtifact(s, {'a': 'y'});
        // The requirement can't be evaluated → no violation invented,
        // but it MUST be surfaced as skipped (honesty contract).
        expect(r.violations.any((v) => v.path == 'b'), isFalse);
        expect(r.skipped.any((msg) => msg.contains('required_when')), isTrue);
      },
    );
  });
}
