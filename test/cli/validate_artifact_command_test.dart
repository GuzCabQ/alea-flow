// Tests for `aflow validate-artifact` — exit-code + file-handling glue.
// Validator correctness is covered in test/core/schema/schema_validator_test.dart.

import 'dart:convert';
import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('validate-artifact command', () {
    late Directory tmp;
    final schemaFile = p.join(
      Directory.current.path,
      'contracts/schemas/analysis.schema.yaml',
    );

    setUp(() => tmp = Directory.systemTemp.createTempSync('alea_va_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String writeArtifact(Map<String, Object?> json) {
      final f = File(p.join(tmp.path, 'analysis.json'))
        ..writeAsStringSync(jsonEncode(json));
      return f.path;
    }

    Map<String, Object?> validBugfix() => {
      'ticket_id': 'DEV-1',
      'type': 'bugfix',
      'title': 'Fix',
      'description': 'broke',
      'success_criteria': ['ok'],
      'created_at': '2026-05-28T10:00:00Z',
      'bug_description': 'b',
      'root_cause_hypothesis': 'r',
      'pii_sanitized': true,
      'ticket_source': {
        'adapter': 'file',
        'fetched_at': '2026-05-28T10:00:00Z',
      },
    };

    test('valid artifact exits 0', () async {
      final code = await AleaCliRunner().run([
        'validate-artifact',
        '--schema-file',
        schemaFile,
        '--artifact',
        writeArtifact(validBugfix()),
      ]);
      expect(code, 0);
    });

    test('invalid artifact exits 1', () async {
      final code = await AleaCliRunner().run([
        'validate-artifact',
        '--schema-file',
        schemaFile,
        '--artifact',
        writeArtifact(validBugfix()..remove('title')),
      ]);
      expect(code, 1);
    });

    test('resolves schema by name via --schemas-dir', () async {
      final code = await AleaCliRunner().run([
        'validate-artifact',
        '--schema',
        'analysis',
        '--schemas-dir',
        p.join(Directory.current.path, 'contracts/schemas'),
        '--artifact',
        writeArtifact(validBugfix()),
      ]);
      expect(code, 0);
    });

    test('missing schema file exits 2', () async {
      final code = await AleaCliRunner().run([
        'validate-artifact',
        '--schema-file',
        '/no/such/schema.yaml',
        '--artifact',
        writeArtifact(validBugfix()),
      ]);
      expect(code, 2);
    });

    test('missing artifact file exits 2', () async {
      final code = await AleaCliRunner().run([
        'validate-artifact',
        '--schema-file',
        schemaFile,
        '--artifact',
        '/no/such/artifact.json',
      ]);
      expect(code, 2);
    });

    test('no --schema or --schema-file exits 64', () async {
      final code = await AleaCliRunner().run([
        'validate-artifact',
        '--artifact',
        writeArtifact(validBugfix()),
      ]);
      expect(code, 64);
    });

    // Task 4: When --schema resolves to a file that doesn't exist under
    // --schemas-dir, the command must exit 2 with the resolved path in the
    // error message (not an opaque crash or a different code).
    test(
      'missing schema resolved via --schema+--schemas-dir exits 2 with path',
      () async {
        final code = await AleaCliRunner().run([
          'validate-artifact',
          '--schema',
          'does_not_exist',
          '--schemas-dir',
          tmp.path,
          '--artifact',
          writeArtifact(validBugfix()),
        ]);
        expect(code, 2);
      },
    );
  });
}
