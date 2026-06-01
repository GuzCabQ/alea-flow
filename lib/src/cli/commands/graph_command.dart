// lib/src/cli/commands/graph_command.dart
//
// ALEA — `aflow graph` subcommand.
//
// Builds the structural code-knowledge-graph (slice-1a) and emits graph.json to
// stdout or a file. Mirrors `aflow inventory`'s output convention. AST-only,
// local, no network, no AI.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'package:dart_source_graph/dart_source_graph.dart';

import '../../contracts/project_config.dart';
import '../../core/config/loader.dart';
import '../graph/source_graph_config_mapper.dart';

class GraphCommand extends Command<int> {
  GraphCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'r',
        defaultsTo: '.',
        help: 'Root directory of the consumer Flutter/Dart project.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'graph.json output path. Defaults to stdout when omitted.',
        valueHelp: 'graph.json',
      )
      ..addFlag(
        'resolve',
        defaultsTo: false,
        negatable: false,
        help:
            'Resolve types (slower; needs `pub get`): precise inheritance + '
            'type-reference edges. Unresolvable files degrade to by-name.',
      )
      ..addFlag(
        'ensure-fresh',
        defaultsTo: false,
        negatable: false,
        help:
            'Skip the rebuild when --output exists and its inputs_fingerprint '
            'matches the current tree (idempotent build). Requires --output.',
      );
  }

  @override
  String get name => 'graph';

  @override
  String get description =>
      'Build a structural code-knowledge-graph (graph.json) from Dart AST.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final projectRoot = p.canonicalize(res['project-root'] as String);
    final output = res['output'] as String?;
    final ensureFresh = res['ensure-fresh'] as bool;
    if (ensureFresh && output == null) {
      stderr.writeln(
        'Error: --ensure-fresh requires --output (no prior file to compare '
        'in stdout mode).',
      );
      return 64;
    }

    final ProjectConfig config;
    try {
      config = loadProjectConfig(projectRoot);
    } on ProjectConfigException catch (e) {
      stderr.writeln('Error loading config: $e');
      return 2;
    }

    final sgConfig = toSourceGraphConfig(config);

    final files = collectDartFiles(projectRoot, sgConfig);

    if (ensureFresh && output != null) {
      final target = p.isAbsolute(output)
          ? output
          : p.join(projectRoot, output);
      final existing = File(target);
      if (existing.existsSync()) {
        try {
          final doc =
              jsonDecode(existing.readAsStringSync()) as Map<String, Object?>;
          final stored = doc['inputs_fingerprint'] as String?;
          final current = CodeGraphBuilder.inputsFingerprint(
            projectRoot,
            files,
          );
          if (stored != null && stored == current) {
            stderr.writeln(
              'graph fresh (${files.length} files) — skipped rebuild',
            );
            return 0;
          }
        } catch (_) {
          // Unparseable / older-schema file → fall through to a full rebuild.
        }
      }
    }

    final builder = CodeGraphBuilder();
    var graph = builder.build(
      projectRoot: projectRoot,
      filePaths: files,
      config: sgConfig,
      packageName: config.project.packageName,
    );

    graph = addWiringEdges(graph, projectRoot: projectRoot, config: sgConfig);

    final resolve = res['resolve'] as bool;
    var resolvedFiles = 0;
    var unresolvedFiles = 0;
    if (resolve) {
      final resolver = CodeGraphResolver();
      graph = await resolver.resolve(
        graph,
        projectRoot: projectRoot,
        filePaths: files,
        config: sgConfig,
      );
      resolvedFiles = resolver.resolvedFiles;
      unresolvedFiles = resolver.unresolvedFiles;
    }

    final meta = CodeGraphMeta(
      schemaVersion: '1.0.0',
      package: config.project.packageName,
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      inputsFingerprint: CodeGraphBuilder.inputsFingerprint(projectRoot, files),
      root: '.',
      skippedFiles: builder.skippedFiles,
      resolved: resolve,
      resolvedFiles: resolvedFiles,
      unresolvedFiles: unresolvedFiles,
    );

    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(graph.toJson(meta: meta));

    if (output == null) {
      stdout.writeln(encoded);
      return 0;
    }

    try {
      // Resolve an absolute -o as-is; relative -o is under projectRoot.
      final target = p.isAbsolute(output)
          ? output
          : p.join(projectRoot, output);
      final file = File(target);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(encoded);
      stdout.writeln(
        'Wrote ${graph.nodes.length} nodes / ${graph.edges.length} edges to $target',
      );
      return 0;
    } on FileSystemException catch (e) {
      stderr.writeln('Error writing graph.json: $e');
      return 2;
    }
  }
}
