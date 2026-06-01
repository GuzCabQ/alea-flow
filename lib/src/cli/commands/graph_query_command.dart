// lib/src/cli/commands/graph_query_command.dart
//
// ALEA — `aflow graph-query`: read-only queries over a prebuilt graph.json
// (impact / neighbors / god-nodes). Warns when the graph is stale vs the tree.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'package:dart_source_graph/dart_source_graph.dart';

import '../../contracts/project_config.dart';
import '../../core/config/loader.dart';
import '../graph/source_graph_config_mapper.dart';

class GraphQueryCommand extends Command<int> {
  GraphQueryCommand() {
    addSubcommand(_ImpactSubcommand());
    addSubcommand(_NeighborsSubcommand());
    addSubcommand(_GodNodesSubcommand());
    addSubcommand(_StructureSubcommand());
    addSubcommand(_UnlayeredSubcommand());
    addSubcommand(_StateFlowSubcommand());
  }

  @override
  String get name => 'graph-query';

  @override
  String get description =>
      'Query a prebuilt graph.json: impact / neighbors / god-nodes.';
}

void _addCommonOptions(ArgParser parser) {
  parser
    ..addOption(
      'input',
      abbr: 'i',
      defaultsTo: 'graph.json',
      help: 'Path to a prebuilt graph.json.',
    )
    ..addOption(
      'project-root',
      abbr: 'r',
      defaultsTo: '.',
      help: 'Project root, for the staleness check.',
    )
    ..addOption(
      'format',
      defaultsTo: 'text',
      allowed: ['text', 'json'],
      help: 'Output format.',
    );
}

/// Loads the graph from `--input`, recomputes the fingerprint against the tree
/// and warns (stderr) on mismatch. Returns null on a hard load error (caller
/// returns exit 2).
CodeGraph? _loadGraph(ArgResults res) {
  final projectRoot = p.canonicalize(res['project-root'] as String);
  final rawInput = res['input'] as String;
  final inputPath = p.isAbsolute(rawInput)
      ? rawInput
      : p.join(projectRoot, rawInput);
  final file = File(inputPath);
  if (!file.existsSync()) {
    stderr.writeln('Error: graph file not found: $inputPath');
    return null;
  }
  final Map<String, Object?> doc;
  try {
    doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  } catch (e) {
    stderr.writeln('Error: could not parse $inputPath: $e');
    return null;
  }
  // Freshness check (best-effort; skipped silently if config/tree unavailable).
  try {
    final config = loadProjectConfig(projectRoot);
    final current = CodeGraphBuilder.inputsFingerprint(
      projectRoot,
      collectDartFiles(projectRoot, toSourceGraphConfig(config)),
    );
    final stored = doc['inputs_fingerprint'] as String?;
    if (stored != null && stored != current) {
      stderr.writeln(
        'Warning: $inputPath is stale vs the current tree — results may be '
        'outdated; re-run `aflow graph`.',
      );
    }
  } on ProjectConfigException {
    // no config — skip the check
  } catch (_) {
    // any other check failure — skip silently, still answer
  }
  try {
    return CodeGraph.fromJson(doc);
  } catch (e) {
    stderr.writeln('Error: $inputPath is not a valid graph document: $e');
    return null;
  }
}

/// Resolve a name/id to a single node id; prints an error and returns null on
/// no-match or ambiguity (caller returns exit 1).
String? _resolveOne(CodeGraphQuery q, String nameOrId) {
  final matches = q.resolveNodes(nameOrId);
  if (matches.isEmpty) {
    stderr.writeln('Error: no node matches "$nameOrId".');
    return null;
  }
  if (matches.length > 1) {
    stderr.writeln('Error: "$nameOrId" is ambiguous; pass a full id:');
    for (final n in matches) {
      stderr.writeln('  ${n.id}');
    }
    return null;
  }
  return matches.single.id;
}

class _ImpactSubcommand extends Command<int> {
  _ImpactSubcommand() {
    _addCommonOptions(argParser);
  }
  @override
  String get name => 'impact';
  @override
  String get description =>
      'What transitively depends on a node (blast radius).';

  @override
  Future<int> run() async {
    final res = argResults!;
    if (res.rest.isEmpty) {
      stderr.writeln('Usage: aflow graph-query impact <name|id>');
      return 64;
    }
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final q = CodeGraphQuery(graph);
    final id = _resolveOne(q, res.rest.first);
    if (id == null) return 1;
    final impacted = q.impact(id).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (res['format'] == 'json') {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'target': id,
          'impacted': [for (final n in impacted) n.id],
        }),
      );
    } else {
      stdout.writeln(
        'Impact of $id — ${impacted.length} node(s) depend on it:',
      );
      for (final n in impacted) {
        stdout.writeln('  ${n.id}${n.file != null ? '  (${n.file})' : ''}');
      }
    }
    return 0;
  }
}

class _NeighborsSubcommand extends Command<int> {
  _NeighborsSubcommand() {
    _addCommonOptions(argParser);
  }
  @override
  String get name => 'neighbors';
  @override
  String get description =>
      'Direct 1-hop edges (incoming + outgoing) of a node.';

  @override
  Future<int> run() async {
    final res = argResults!;
    if (res.rest.isEmpty) {
      stderr.writeln('Usage: aflow graph-query neighbors <name|id>');
      return 64;
    }
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final q = CodeGraphQuery(graph);
    final id = _resolveOne(q, res.rest.first);
    if (id == null) return 1;
    final n = q.neighbors(id);
    if (res['format'] == 'json') {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'node': id,
          'incoming': [for (final e in n.incoming) e.toJson()],
          'outgoing': [for (final e in n.outgoing) e.toJson()],
        }),
      );
    } else {
      stdout.writeln('Neighbors of $id:');
      stdout.writeln('  incoming (${n.incoming.length}):');
      for (final e in n.incoming) {
        stdout.writeln(
          '    ${e.source}  --${graphRelationToJson(e.relation)}-->',
        );
      }
      stdout.writeln('  outgoing (${n.outgoing.length}):');
      for (final e in n.outgoing) {
        stdout.writeln(
          '    --${graphRelationToJson(e.relation)}-->  ${e.target}',
        );
      }
    }
    return 0;
  }
}

class _GodNodesSubcommand extends Command<int> {
  _GodNodesSubcommand() {
    _addCommonOptions(argParser);
    argParser.addOption(
      'limit',
      defaultsTo: '20',
      help: 'How many hubs to show.',
    );
  }
  @override
  String get name => 'god-nodes';
  @override
  String get description =>
      'Top internal nodes by degree (architectural hubs).';

  @override
  Future<int> run() async {
    final res = argResults!;
    final parsedLimit = int.tryParse(res['limit'] as String);
    if (parsedLimit == null) {
      stderr.writeln('Warning: --limit must be an integer; using 20.');
    }
    final limit = parsedLimit ?? 20;
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final top = CodeGraphQuery(graph).godNodes(limit: limit);
    if (res['format'] == 'json') {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert([
          for (final r in top)
            {'id': r.node.id, 'degree': r.degree, 'file': r.node.file},
        ]),
      );
    } else {
      stdout.writeln('Top $limit hubs by degree:');
      for (final r in top) {
        final loc = r.node.file != null ? '  (${r.node.file})' : '';
        stdout.writeln('  ${r.degree.toString().padLeft(4)}  ${r.node.id}$loc');
      }
    }
    return 0;
  }
}

class _StructureSubcommand extends Command<int> {
  _StructureSubcommand() {
    _addCommonOptions(argParser);
    argParser.addOption(
      'depth',
      defaultsTo: '3',
      help: 'Directory-segment depth for clustering (default 3).',
    );
  }

  @override
  String get name => 'structure';

  @override
  String get description =>
      'Summarize directory clusters, inter-cluster edges and import cycles '
      '(grounds .alea.yaml via /complete-config).';

  @override
  Future<int> run() async {
    final res = argResults!;
    final depth = int.tryParse(res['depth'] as String);
    if (depth == null || depth < 1) {
      stderr.writeln(
        'Usage: aflow graph-query structure --depth <positive int>',
      );
      return 64;
    }
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final s = CodeGraphQuery(graph).structure(depth: depth);
    if (res['format'] == 'json') {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'clusters': [
            for (final c in s.clusters)
              {
                'path': c.path,
                'file_count': c.fileCount,
                'imports_flutter': c.importsFlutter,
              },
          ],
          'cluster_edges': [
            for (final e in s.clusterEdges)
              {'from': e.from, 'to': e.to, 'count': e.count},
          ],
          'cyclic_clusters': s.cyclicClusters,
        }),
      );
    } else {
      stdout.writeln('Clusters (${s.clusters.length}):');
      for (final c in s.clusters) {
        final fl = c.importsFlutter ? ', imports flutter' : '';
        stdout.writeln('  ${c.path}  (${c.fileCount} files$fl)');
      }
      stdout.writeln('Edges (${s.clusterEdges.length}):');
      for (final e in s.clusterEdges) {
        stdout.writeln('  ${e.from} -> ${e.to}  (${e.count})');
      }
      if (s.cyclicClusters.isNotEmpty) {
        stdout.writeln('Cycles involve: ${s.cyclicClusters.join(', ')}');
      }
    }
    return 0;
  }
}

class _UnlayeredSubcommand extends Command<int> {
  _UnlayeredSubcommand() {
    _addCommonOptions(argParser);
    argParser.addOption(
      'depth',
      defaultsTo: '3',
      help: 'Directory-segment depth for clustering (default 3).',
    );
  }

  @override
  String get name => 'unlayered';

  @override
  String get description =>
      'Directory-clustered counts of files outside every declared layer — a '
      'bounded signal for /complete-config (declare these or add to graph.exclude).';

  @override
  Future<int> run() async {
    final res = argResults!;
    final depth = int.tryParse(res['depth'] as String);
    if (depth == null || depth < 1) {
      stderr.writeln(
        'Usage: aflow graph-query unlayered --depth <positive int>',
      );
      return 64;
    }
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final clusters = CodeGraphQuery(graph).unlayered(depth: depth);
    if (res['format'] == 'json') {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'unlayered': [
            for (final c in clusters)
              {'path': c.path, 'file_count': c.fileCount},
          ],
        }),
      );
    } else {
      stdout.writeln('Unlayered clusters (${clusters.length}):');
      for (final c in clusters) {
        stdout.writeln('  ${c.path}  (${c.fileCount} files)');
      }
    }
    return 0;
  }
}

class _StateFlowSubcommand extends Command<int> {
  _StateFlowSubcommand() {
    _addCommonOptions(argParser);
  }

  @override
  String get name => 'state-flow';

  @override
  String get description =>
      'For each role-tagged node, the state-API calls (watch/read/find/put…) its '
      'methods make — a bounded state-flow summary for the pipeline.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final graph = _loadGraph(res);
    if (graph == null) return 2;
    final flows = CodeGraphQuery(graph).stateFlow();
    if (res['format'] == 'json') {
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          'state_flow': [
            for (final f in flows)
              {'node': f.node, 'role': f.role, 'calls': f.calls},
          ],
        }),
      );
    } else {
      stdout.writeln('State-flow (${flows.length} role-tagged nodes):');
      for (final f in flows) {
        stdout.writeln('  ${f.node} [${f.role}] -> ${f.calls.join(', ')}');
      }
    }
    return 0;
  }
}
