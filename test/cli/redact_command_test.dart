// Tests for `aflow redact` — the CLI primitive over the shared PiiRedactor.
//
// Content correctness of the redaction itself is covered exhaustively in
// test/core/journal/pii_redactor_test.dart. Here we verify the *command glue*:
// input selection (positional / --file), the --format flag, exit codes, and
// that the redacted result actually reaches stdout.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('redact command', () {
    // Known-good PII examples (same ones the PiiRedactor tests use).
    const curp = 'PEPE850101HDFRNS01';
    const email = 'dev@example.com';

    test('redacts positional input and reports counts as JSON', () async {
      final out = await _captureStdout(() async {
        final code = await AleaCliRunner().run([
          'redact',
          'curp $curp mail $email',
          '--format',
          'json',
        ]);
        expect(code, 0);
      });
      final decoded = jsonDecode(out.trim()) as Map<String, Object?>;
      expect(decoded['text'], isNot(contains(curp)));
      expect(decoded['text'], contains('[REDACTED:curp]'));
      expect(decoded['text'], contains('[REDACTED:email]'));
      final redactions = decoded['redactions'] as Map<String, Object?>;
      expect(redactions['curp'], 1);
      expect(redactions['email'], 1);
    });

    test('default text format prints only the redacted text', () async {
      final out = await _captureStdout(() async {
        final code = await AleaCliRunner().run(['redact', 'mail $email']);
        expect(code, 0);
      });
      expect(out, contains('[REDACTED:email]'));
      expect(out, isNot(contains(email)));
      expect(out, isNot(contains('redactions'))); // no JSON envelope
    });

    test('reads input from --file', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_redact_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final f = File(p.join(tmp.path, 'ticket.txt'))
        ..writeAsStringSync('contacto $email');

      final out = await _captureStdout(() async {
        final code = await AleaCliRunner().run([
          'redact',
          '--file',
          f.path,
          '--format',
          'json',
        ]);
        expect(code, 0);
      });
      final decoded = jsonDecode(out.trim()) as Map<String, Object?>;
      expect((decoded['redactions'] as Map)['email'], 1);
    });

    test('missing --file exits 2', () async {
      final code = await AleaCliRunner().run([
        'redact',
        '--file',
        '/no/such/file.txt',
      ]);
      expect(code, 2);
    });

    test('clean text passes through unchanged', () async {
      final out = await _captureStdout(() async {
        final code = await AleaCliRunner().run([
          'redact',
          'no PII here',
          '--format',
          'json',
        ]);
        expect(code, 0);
      });
      final decoded = jsonDecode(out.trim()) as Map<String, Object?>;
      expect(decoded['text'], 'no PII here');
      expect((decoded['redactions'] as Map), isEmpty);
    });

    test('invalid --format value exits 64 (usage)', () async {
      final code = await AleaCliRunner().run([
        'redact',
        'x',
        '--format',
        'xml',
      ]);
      expect(code, 64);
    });
  });
}

// ── stdout capture ───────────────────────────────────────────────────────────

Future<String> _captureStdout(Future<void> Function() body) async {
  final buffer = StringBuffer();
  await IOOverrides.runZoned(body, stdout: () => _CapturingStdout(buffer));
  return buffer.toString();
}

/// Minimal [Stdout] that routes written text to a [StringBuffer]. Only the
/// members the redact command touches are implemented; the rest throw.
class _CapturingStdout implements Stdout {
  _CapturingStdout(this._buffer);
  final StringBuffer _buffer;

  @override
  void write(Object? object) => _buffer.write(object);

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String sep = '']) =>
      _buffer.writeAll(objects, sep);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);

  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));

  @override
  Encoding encoding = utf8;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future<void>.value();

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      throw UnimplementedError();

  @override
  Future<void> addStream(Stream<List<int>> stream) async =>
      throw UnimplementedError();

  @override
  bool get hasTerminal => false;

  @override
  IOSink get nonBlocking => throw UnimplementedError();

  @override
  bool get supportsAnsiEscapes => false;

  @override
  int get terminalColumns => throw UnimplementedError();

  @override
  int get terminalLines => throw UnimplementedError();

  @override
  String lineTerminator = '\n';
}
