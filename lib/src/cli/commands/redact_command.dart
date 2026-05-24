// ALEA — `aflow redact` subcommand.
//
// Exposes the shared, tested [redactString] (Mexican-context PII catalog:
// CURP / RFC / CLABE / card / phone / email) as a CLI primitive, so commands
// and drivers can scrub text via *code* instead of re-specifying the regex
// policy in prose for an AI to apply by hand.
//
// Reads input from `--file`, positional arguments, or stdin (in that order).
// Emits the redacted text (default) or `{text, redactions}` JSON (--format
// json), where `redactions` is the per-label count map the redactor returns.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../../core/journal/pii_redactor.dart';

class RedactCommand extends Command<int> {
  RedactCommand() {
    argParser
      ..addOption(
        'file',
        abbr: 'f',
        help: 'Read input from this file instead of arguments/stdin.',
        valueHelp: 'path',
      )
      ..addOption(
        'format',
        allowed: ['text', 'json'],
        defaultsTo: 'text',
        help:
            '`text` prints the redacted text only; '
            '`json` prints {"text": ..., "redactions": {label: count}}.',
      );
  }

  @override
  String get name => 'redact';

  @override
  String get description =>
      'Redact Mexican-context PII (CURP/RFC/CLABE/card/phone/email) from text '
      'using the shared PiiRedactor.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final filePath = res['file'] as String?;
    final format = res['format'] as String;

    final String input;
    if (filePath != null) {
      final file = File(filePath);
      if (!file.existsSync()) {
        stderr.writeln('File not found: $filePath');
        return 2;
      }
      input = await file.readAsString();
    } else if (res.rest.isNotEmpty) {
      input = res.rest.join(' ');
    } else {
      input = await stdin.transform(utf8.decoder).join();
    }

    final result = redactString(input);

    if (format == 'json') {
      stdout.writeln(
        jsonEncode({'text': result.text, 'redactions': result.counts}),
      );
    } else {
      stdout.writeln(result.text);
    }
    return 0;
  }
}
