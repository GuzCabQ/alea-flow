// ALEA — `aflow inventory` subcommand.
//
// Scans the consumer project for widget-like classes and writes the
// JSON inventory to disk. Paths come from `analyzers.options.widget_inventory.scan_paths`
// when set, otherwise from `architecture.layers.*.paths`.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../contracts/project_config.dart';
import '../../core/config/loader.dart';
import '../../inventory/widget_inventory_builder.dart';

class InventoryCommand extends Command<int> {
  InventoryCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'r',
        defaultsTo: '.',
        help: 'Root directory of the consumer Flutter project.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help:
            'JSON output path. Parent directories are created '
            'automatically. Defaults to stdout when omitted.',
        valueHelp: 'widget_inventory.json',
      );
  }

  @override
  String get name => 'inventory';

  @override
  String get description => 'Scan widget classes and emit a JSON inventory.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final projectRoot = p.canonicalize(res['project-root'] as String);
    final output = res['output'] as String?;

    final ProjectConfig config;
    try {
      config = loadProjectConfig(projectRoot);
    } on ProjectConfigException catch (e) {
      stderr.writeln('Error loading config: $e');
      return 2;
    }

    final scanPaths = _resolveScanPaths(config, projectRoot);
    final tokenClasses = _resolveTokenClasses(config);

    final builder = WidgetInventoryBuilder(
      scanPaths: scanPaths,
      tokenClasses: tokenClasses,
      projectRoot: projectRoot,
    );
    final inventory = await builder.build();
    final entries = await inventory.entries();

    if (output == null) {
      stdout.writeln('Widgets found: ${entries.length}');
      for (final e in entries) {
        stdout.writeln(
          '  ${e.className.padRight(36)} '
          '${(e.category ?? "?").padRight(10)} '
          '${e.filePath}',
        );
      }
      return 0;
    }

    await builder.emitJsonTo(p.join(projectRoot, output), inventory);
    stdout.writeln(
      'Wrote ${entries.length} widgets to ${p.join(projectRoot, output)}',
    );
    return 0;
  }

  List<String> _resolveScanPaths(ProjectConfig config, String projectRoot) {
    final opts = config.analyzers.optionsFor('widget_inventory');
    final raw = opts['scan_paths'];
    final declared = <String>[];
    if (raw is List) {
      declared.addAll(raw.map((e) => e.toString()));
    } else {
      for (final layer in config.architecture.layers.values) {
        declared.addAll(layer.paths);
      }
    }
    final out = <String>[];
    for (final rel in declared) {
      final abs = p.isAbsolute(rel) ? rel : p.join(projectRoot, rel);
      if (Directory(abs).existsSync() || File(abs).existsSync()) {
        out.add(p.normalize(abs));
      }
    }
    return out;
  }

  Set<String> _resolveTokenClasses(ProjectConfig config) {
    final opts = config.analyzers.optionsFor('widget_inventory');
    final raw = opts['token_classes'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toSet();
    }
    return defaultTokenClasses.toSet();
  }
}
