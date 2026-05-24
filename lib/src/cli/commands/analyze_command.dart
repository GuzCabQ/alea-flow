// ALEA — `alea analyze` subcommand.
//
// Runs the analyzer registry against a consumer's project and writes a
// gate report (human-readable to stdout by default; JSON when --format=json
// or --output-file is set).

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../adapters/token_catalog/factory.dart';
import '../../contracts/design_token_catalog.dart';
import '../../contracts/project_config.dart';
import '../../core/config/loader.dart';
import '../../core/registry.dart';
import '../../core/reporter.dart';
import '../../core/runner.dart';

class AnalyzeCommand extends Command<int> {
  AnalyzeCommand() {
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
        'gate',
        abbr: 'g',
        defaultsTo: 'gate',
        help:
            'Gate name included in the report. Does not filter analyzers — '
            'that comes from `.alea.yaml::analyzers.enabled`.',
      )
      ..addOption(
        'run-directory',
        abbr: 'd',
        help:
            'Path to the pipeline run directory '
            '(e.g. .pipeline/runs/DEV-XXXX/).',
        valueHelp: '.pipeline/runs/DEV-XXXX/',
      )
      ..addMultiOption(
        'changed-files',
        abbr: 'c',
        help:
            'Dart files to analyze. Repeat for multiple files. '
            'If omitted, every layer path declared in `.alea.yaml` is '
            'scanned recursively.',
        valueHelp: 'path/to/file.dart',
      )
      ..addOption(
        'output-file',
        abbr: 'o',
        help:
            'Write the JSON gate report to this path. Parent dirs are '
            'created automatically.',
        valueHelp: '.pipeline/runs/DEV-XXXX/gate_report.json',
      );
  }

  @override
  String get name => 'analyze';

  @override
  String get description => 'Run analyzers and produce a gate report.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final projectRoot = p.canonicalize(res['project-root'] as String);
    final format = res['format'] as String;
    final gate = res['gate'] as String;
    final outputFile = res['output-file'] as String?;
    final runDirectoryArg = res['run-directory'] as String?;
    final runDirectory = runDirectoryArg != null
        ? p.canonicalize(runDirectoryArg)
        : null;
    final changedFiles = (res['changed-files'] as List<String>)
        .map(p.canonicalize)
        .toList();

    final ProjectConfig config;
    try {
      config = loadProjectConfig(projectRoot);
    } on ProjectConfigException catch (e) {
      stderr.writeln('Error loading config: $e');
      return 2;
    }

    final filesToAnalyze = _resolveFiles(
      config: config,
      projectRoot: projectRoot,
      changedFiles: changedFiles,
      positional: res.rest,
    );
    if (filesToAnalyze.isEmpty) {
      stderr.writeln('No Dart files found to analyze.');
      return 0;
    }

    DesignTokenCatalog? catalog;
    try {
      catalog = buildTokenCatalog(config, projectRoot: projectRoot);
    } on ProjectConfigException catch (e) {
      stderr.writeln('Warning: unable to build token catalog: $e');
    }

    final runner = AnalyzerRunner(registeredAnalyzers());
    final report = await runner.run(
      gate: gate,
      filePaths: filesToAnalyze,
      projectRoot: projectRoot,
      runDirectory: runDirectory,
      config: config,
      tokenCatalog: catalog,
    );

    final reporter = GateReporter();
    if (outputFile != null) {
      final file = File(outputFile);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(reporter.toJsonString(report));
      stderr.writeln('Gate report written to $outputFile');
    }

    stdout.writeln(
      format == 'json'
          ? reporter.toJsonString(report)
          : reporter.toHumanReadable(report),
    );

    return report.passed ? 0 : 1;
  }

  List<String> _resolveFiles({
    required ProjectConfig config,
    required String projectRoot,
    required List<String> changedFiles,
    required List<String> positional,
  }) {
    if (changedFiles.isNotEmpty) return changedFiles;
    if (positional.isNotEmpty) {
      return positional.map(p.canonicalize).toList();
    }
    final out = <String>[];
    for (final layer in config.architecture.layers.values) {
      for (final layerPath in layer.paths) {
        final dir = Directory(p.join(projectRoot, layerPath));
        if (!dir.existsSync()) continue;
        out.addAll(
          dir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .map((f) => f.path),
        );
      }
    }
    return out;
  }
}
