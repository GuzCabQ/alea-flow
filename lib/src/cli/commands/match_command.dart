// ALEA — `aflow match <family> <query>` subcommand.
//
// Family is `color`, `typography`, or `spacing`. The command loads the
// consumer's `.alea.yaml`, builds the DesignTokenCatalog declared by
// `theme.token_catalog`, instantiates the matching resolver, and prints
// the result (human or JSON).

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../adapters/token_catalog/factory.dart';
import '../../contracts/design_token_catalog.dart';
import '../../contracts/project_config.dart';
import '../../core/config/loader.dart';
import '../../resolvers/layout_metric/resolver.dart';
import '../../resolvers/palette/resolver.dart';
import '../../resolvers/type_scale/resolver.dart';

class MatchCommand extends Command<int> {
  MatchCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'r',
        defaultsTo: '.',
        help: 'Root directory of the consumer Flutter project.',
      )
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['human', 'json'],
        defaultsTo: 'human',
        help: 'Output format.',
      )
      ..addOption(
        'unit',
        abbr: 'u',
        defaultsTo: 'px',
        help: 'Unit for the spacing family (px, %, em, ...).',
      )
      ..addOption(
        'family-name',
        abbr: 'F',
        help: 'For typography: optional font family hint.',
      );
  }

  @override
  String get name => 'match';

  @override
  String get description =>
      'Resolve a hex / size+weight / metric against the design-token catalog.';

  @override
  String get invocation => 'aflow match <color|typography|spacing> <query>';

  @override
  Future<int> run() async {
    final res = argResults!;
    final rest = res.rest;
    if (rest.length < 2) {
      stderr.writeln('Usage: $invocation');
      return 64;
    }
    final family = rest[0];
    final query = rest[1];
    final projectRoot = p.canonicalize(res['project-root'] as String);
    final format = res['format'] as String;

    final ProjectConfig config;
    try {
      config = loadProjectConfig(projectRoot);
    } on ProjectConfigException catch (e) {
      stderr.writeln('Error loading config: $e');
      return 2;
    }

    final catalog = buildTokenCatalog(config, projectRoot: projectRoot);
    if (catalog == null) {
      stderr.writeln(
        'No `theme.token_catalog` declared in .alea.yaml — nothing to match against.',
      );
      return 2;
    }

    final result = await _resolve(family, query, res, catalog);
    if (result == null) return 64; // unsupported family or bad query

    if (format == 'json') {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    } else {
      _renderHuman(family, query, result);
    }
    return 0;
  }

  Future<Map<String, Object?>?> _resolve(
    String family,
    String query,
    dynamic res,
    DesignTokenCatalog catalog,
  ) async {
    switch (family) {
      case 'color':
        final cq = ColorQuery.fromHex(query);
        if (cq == null) {
          stderr.writeln('Invalid hex color: $query');
          return null;
        }
        final r = await PaletteResolver(catalog).resolve(cq);
        return r.toJson();
      case 'typography':
        final parts = query.split('/');
        if (parts.length < 2) {
          stderr.writeln(
            'Typography query expects "<size>/<weight>" '
            '(e.g. "16/600" or "16/semibold")',
          );
          return null;
        }
        final size = double.tryParse(parts[0]);
        final weight = _parseWeight(parts[1]);
        if (size == null || weight == null) {
          stderr.writeln('Could not parse typography query: $query');
          return null;
        }
        final r = await TypeScaleResolver(catalog).resolve(
          TypographyQuery(
            fontSize: size,
            fontWeight: weight,
            fontFamily: res['family-name'] as String?,
          ),
        );
        return r.toJson();
      case 'spacing':
        final value = double.tryParse(query);
        if (value == null) {
          stderr.writeln('Spacing query must be numeric: $query');
          return null;
        }
        final unit = res['unit'] as String;
        final r = await LayoutMetricResolver(
          catalog,
        ).resolve(LayoutMetricQuery(value: value, unit: unit));
        return r.toJson();
      default:
        stderr.writeln(
          'Unsupported family "$family". '
          'Supported: color, typography, spacing.',
        );
        return null;
    }
  }

  int? _parseWeight(String raw) {
    final n = int.tryParse(raw);
    if (n != null) return n;
    switch (raw.toLowerCase()) {
      case 'light':
        return 300;
      case 'regular':
      case 'normal':
        return 400;
      case 'medium':
        return 500;
      case 'semibold':
        return 600;
      case 'bold':
        return 700;
    }
    return null;
  }

  void _renderHuman(String family, String query, Map<String, Object?> json) {
    stdout.writeln('Match — $family / $query');
    stdout.writeln('  Verdict:    ${json['verdict']}');
    final confidence = json['confidence'];
    if (confidence is num) {
      stdout.writeln('  Confidence: ${confidence.toStringAsFixed(3)}');
    }
    if (json['recommended'] != null) {
      stdout.writeln('  Recommended: ${json['recommended']}');
    }
    final candidates = json['candidates'];
    if (candidates is List) {
      stdout.writeln('  Candidates:');
      for (final c in candidates) {
        if (c is Map<String, Object?>) {
          final score = (c['score'] as num?)?.toStringAsFixed(3);
          stdout.writeln(
            '    - ${c['token']} '
            '(score=$score, ${c['rationale'] ?? ''})',
          );
        }
      }
    }
    final warnings = json['warnings'];
    if (warnings is List && warnings.isNotEmpty) {
      stdout.writeln('  Warnings:');
      for (final w in warnings) {
        stdout.writeln('    - $w');
      }
    }
  }
}
