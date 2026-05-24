// ALEA — `aflow validate-artifact` subcommand.
//
// Validates a pipeline artifact (JSON) against an ALEA schema (the YAML DSL
// under `contracts/schemas/`). This is the code-enforced "validate before
// persisting" gate: a driver runs it after the AI writes an artifact and
// refuses to advance on violations, instead of trusting the AI's claim.
//
// Exit codes: 0 = valid · 1 = schema violations · 2 = file/parse error ·
// 64 = usage error.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../core/schema/schema_validator.dart';

class ValidateArtifactCommand extends Command<int> {
  ValidateArtifactCommand() {
    argParser
      ..addOption(
        'schema',
        abbr: 's',
        help:
            'Schema name (resolved to <schemas-dir>/<name>.schema.yaml). '
            'Ignored when --schema-file is given.',
        valueHelp: 'analysis',
      )
      ..addOption(
        'schema-file',
        help: 'Explicit path to a schema YAML file (overrides --schema).',
        valueHelp: 'path',
      )
      ..addOption(
        'schemas-dir',
        defaultsTo: 'contracts/schemas',
        help: 'Directory holding <name>.schema.yaml files.',
      )
      ..addOption(
        'artifact',
        abbr: 'a',
        help: 'Path to the artifact JSON to validate.',
        mandatory: true,
        valueHelp: 'path',
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
  String get name => 'validate-artifact';

  @override
  String get description =>
      'Validate a pipeline artifact (JSON) against an ALEA schema.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final format = res['format'] as String;

    final schemaPath = _resolveSchemaPath(res);
    if (schemaPath == null) {
      stderr.writeln('Provide --schema <name> or --schema-file <path>.');
      return 64;
    }
    final schemaFile = File(schemaPath);
    if (!schemaFile.existsSync()) {
      stderr.writeln('Schema not found: $schemaPath');
      return 2;
    }
    final artifactFile = File(res['artifact'] as String);
    if (!artifactFile.existsSync()) {
      stderr.writeln('Artifact not found: ${artifactFile.path}');
      return 2;
    }

    final Map schema;
    final Object? artifact;
    try {
      schema = parseSchema(schemaFile.readAsStringSync());
    } on Object catch (e) {
      stderr.writeln('Failed to parse schema: $e');
      return 2;
    }
    try {
      artifact = jsonDecode(artifactFile.readAsStringSync());
    } on FormatException catch (e) {
      stderr.writeln('Failed to parse artifact JSON: ${e.message}');
      return 2;
    }

    final result = validateArtifact(schema, artifact);

    if (format == 'json') {
      stdout.writeln(jsonEncode(result.toJson()));
    } else {
      if (result.valid) {
        stdout.writeln('VALID — no violations.');
      } else {
        stdout.writeln('INVALID — ${result.violations.length} violation(s):');
        for (final v in result.violations) {
          stdout.writeln('  ✗ $v');
        }
      }
      if (result.skipped.isNotEmpty) {
        stdout.writeln(
          '  (${result.skipped.length} uncheckable construct(s) skipped)',
        );
      }
    }

    return result.valid ? 0 : 1;
  }

  String? _resolveSchemaPath(ArgResults res) {
    final explicit = res['schema-file'] as String?;
    if (explicit != null) return explicit;
    final name = res['schema'] as String?;
    if (name == null) return null;
    return p.join(res['schemas-dir'] as String, '$name.schema.yaml');
  }
}
