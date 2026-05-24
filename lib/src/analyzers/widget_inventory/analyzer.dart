// ALEA — WidgetInventoryAnalyzer.
//
// Secondary analyzer: does NOT emit issues — its purpose is to produce a
// `widget_inventory.json` artifact under the run directory and to emit
// journal events that downstream skills can read. The analyzer registers in
// the standard registry so consumers can opt in via `analyzers.enabled`.
//
// Configuration (via `analyzers.options.widget_inventory`):
//
//   analyzers:
//     options:
//       widget_inventory:
//         scan_paths:
//           - lib/src/shared/presentation/components/
//           - lib/src/feature/sci/shared/components/
//         token_classes:
//           - StyleColors
//           - StyleFonts
//           - StyleSize
//         output_path: widget_inventory.json   # relative to runDirectory
//
// Defaults (when the section is absent):
//   - scan_paths: every entry from `architecture.layers.<*>.paths`
//   - token_classes: ['StyleColors', 'StyleFonts', 'StyleSize']
//   - output_path: 'widget_inventory.json'

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../contracts/analyzer.dart';
import '../../contracts/run_journal.dart';
import '../../inventory/widget_inventory_builder.dart';

class WidgetInventoryAnalyzer extends Analyzer {
  @override
  String get name => 'widget_inventory';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final opts = ctx.config.analyzers.optionsFor(name);
    final scanPaths = _resolveScanPaths(opts, ctx);
    if (scanPaths.isEmpty) {
      await ctx.journal?.record(
        JournalEvent(
          source: 'analyzer:$name',
          kind: JournalEventKind.warning,
          payload: const {'reason': 'no scan_paths resolved; skipping'},
        ),
      );
      return const [];
    }

    final tokenClasses = _resolveTokenClasses(opts);
    final outputName =
        (opts['output_path'] as String?) ?? 'widget_inventory.json';

    final builder = WidgetInventoryBuilder(
      scanPaths: scanPaths,
      tokenClasses: tokenClasses,
      projectRoot: ctx.projectRoot,
    );

    final inventory = await builder.build(journal: ctx.journal);

    final runDir = ctx.runDirectory;
    if (runDir != null) {
      final outPath = p.join(runDir, outputName);
      await builder.emitJsonTo(outPath, inventory);
      await ctx.journal?.record(
        JournalEvent(
          source: 'analyzer:$name',
          kind: JournalEventKind.completed,
          payload: {
            'artifact': p.relative(outPath, from: runDir),
            'widgets': (await inventory.entries()).length,
          },
        ),
      );
    } else {
      await ctx.journal?.record(
        JournalEvent(
          source: 'analyzer:$name',
          kind: JournalEventKind.completed,
          payload: {
            'artifact': null,
            'widgets': (await inventory.entries()).length,
            'note': 'no runDirectory — artifact not persisted',
          },
        ),
      );
    }

    return const [];
  }

  List<String> _resolveScanPaths(
    Map<String, Object?> opts,
    AnalyzerContext ctx,
  ) {
    final raw = opts['scan_paths'];
    final declared = <String>[];
    if (raw is List) {
      declared.addAll(raw.map((e) => e.toString()));
    } else {
      // Default: every layer path declared in the project config.
      for (final layer in ctx.config.architecture.layers.values) {
        declared.addAll(layer.paths);
      }
    }
    final absolute = <String>[];
    for (final relOrAbs in declared) {
      final isAbs = p.isAbsolute(relOrAbs);
      final candidate = isAbs ? relOrAbs : p.join(ctx.projectRoot, relOrAbs);
      if (Directory(candidate).existsSync() || File(candidate).existsSync()) {
        absolute.add(p.normalize(candidate));
      }
    }
    return absolute;
  }

  Set<String> _resolveTokenClasses(Map<String, Object?> opts) {
    final raw = opts['token_classes'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toSet();
    }
    return defaultTokenClasses.toSet();
  }
}
