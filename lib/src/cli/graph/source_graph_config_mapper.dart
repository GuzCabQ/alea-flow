// lib/src/cli/graph/source_graph_config_mapper.dart
//
// ALEA — maps alea-flow's ProjectConfig onto dart_source_graph's
// SourceGraphConfig. The graph package is configuration-agnostic (it knows
// nothing about .alea.yaml); this is the single translation point.

import 'package:dart_source_graph/dart_source_graph.dart' as dsg;

import '../../contracts/project_config.dart';

/// Translate a [ProjectConfig] into the package's [dsg.SourceGraphConfig]:
/// architecture layers → LayerConfig list, graph.exclude/roleOverrides verbatim,
/// and the (field-identical) wiring rules.
dsg.SourceGraphConfig toSourceGraphConfig(ProjectConfig config) {
  // Only name + paths cross over: alea-flow's LayerConfig.mayImport/forbidImports
  // are analyzer-only and have no counterpart in dsg.LayerConfig.
  final layers = <dsg.LayerConfig>[
    for (final entry in config.architecture.layers.entries)
      dsg.LayerConfig(name: entry.key, paths: entry.value.paths),
  ];

  final wiring = config.architecture.wiring;
  return dsg.SourceGraphConfig(
    exclude: config.graph.exclude,
    layers: layers,
    roleOverrides: config.graph.roleOverrides,
    wiring: wiring == null
        ? null
        : dsg.WiringConfig(
            rules: [
              for (final r in wiring.rules)
                dsg.WiringRule(
                  name: r.name,
                  classPattern: r.classPattern,
                  manifestFile: r.manifestFile,
                  registrationCall: r.registrationCall,
                  scanPaths: r.scanPaths,
                ),
            ],
          ),
  );
}
