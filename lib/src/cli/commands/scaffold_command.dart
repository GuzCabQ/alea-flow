// ALEA — `aflow scaffold <feature>` subcommand.
//
// Generates a feature scaffold via the appropriate `CodeGenAdapter`.
// Adapter selection: explicit `--style <name>` wins; otherwise the value
// of `state_management.style` in `.alea.yaml`.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../adapters/code_gen/bloc/adapter.dart';
import '../../adapters/code_gen/riverpod_manual/adapter.dart';
import '../../contracts/code_gen_adapter.dart';
import '../../contracts/project_config.dart';
import '../../core/config/loader.dart';
import '../../scaffolding/code_gen_orchestrator.dart';

class ScaffoldCommand extends Command<int> {
  ScaffoldCommand() {
    argParser
      ..addOption(
        'project-root',
        abbr: 'r',
        defaultsTo: '.',
        help: 'Root directory of the consumer Flutter project.',
      )
      ..addOption(
        'layer',
        abbr: 'l',
        allowed: ['domain', 'infrastructure', 'presentation', 'bugfix'],
        defaultsTo: 'presentation',
        help: 'Layer to generate.',
      )
      ..addOption(
        'style',
        abbr: 's',
        help:
            'Override `state_management.style` (riverpod_manual, bloc). '
            'Falls back to the value in .alea.yaml when omitted.',
      )
      ..addOption(
        'run-directory',
        abbr: 'd',
        help:
            'Path to the pipeline run directory '
            '(e.g. .pipeline/runs/DEV-XXXX/).',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Build the plan and report it but do not write any file.',
      );
  }

  @override
  String get name => 'scaffold';

  @override
  String get description =>
      'Generate a feature scaffold via the configured code-gen adapter.';

  @override
  String get invocation => 'aflow scaffold <feature_name>';

  @override
  Future<int> run() async {
    final res = argResults!;
    final positional = res.rest;
    if (positional.isEmpty) {
      stderr.writeln('Usage: $invocation');
      return 64;
    }
    final featureName = positional.first;
    final projectRoot = p.canonicalize(res['project-root'] as String);

    final ProjectConfig config;
    try {
      config = loadProjectConfig(projectRoot);
    } on ProjectConfigException catch (e) {
      stderr.writeln('Error loading config: $e');
      return 2;
    }

    final styleName = (res['style'] as String?) ?? config.stateManagement.style;
    final adapter = _resolveAdapter(styleName);
    if (adapter == null) {
      stderr.writeln(
        'Unsupported state_management.style: $styleName. '
        'Built-in adapters: riverpod_manual, bloc.',
      );
      return 2;
    }

    final layer = CodeGenLayer.values.firstWhere(
      (l) => l.name == (res['layer'] as String),
    );

    if (!adapter.supports(layer, config)) {
      stderr.writeln(
        'Style "$styleName" does not support layer "${layer.name}". '
        'Nothing to scaffold.',
      );
      return 2;
    }

    final request = CodeGenRequest(
      layer: layer,
      spec: {
        'feature': {'name': featureName},
      },
      projectRoot: projectRoot,
      runDirectory: res['run-directory'] as String?,
      config: config,
    );

    if (res['dry-run'] as bool) {
      final plan = await adapter.generate(request);
      stdout.writeln(
        'Plan (${plan.adapterName}) — '
        '${plan.files.length} file(s), ${plan.patches.length} patch(es)',
      );
      for (final f in plan.files) {
        stdout.writeln('  - ${f.relativePath} (${f.content.length} bytes)');
      }
      return 0;
    }

    final orchestrator = CodeGenOrchestrator();
    final result = await orchestrator.run(adapter: adapter, request: request);

    stdout.writeln('Adapter:      ${result.plan.adapterName}');
    stdout.writeln('Files:        ${result.outcomes.length}');
    for (final o in result.outcomes) {
      stdout.writeln('  ${o.action.name.padRight(12)} ${o.relativePath}');
    }
    stdout.writeln(
      'Verification: '
      '${result.verification.passed ? "passed" : "failed"}'
      '${result.verification.rolledBack ? " (rolled back)" : ""}',
    );
    if (result.verification.issues.isNotEmpty) {
      stdout.writeln('Issues:');
      for (final i in result.verification.issues) {
        stdout.writeln('  [${i.severity.name}] ${i.file} — ${i.message}');
      }
    }
    return result.success ? 0 : 1;
  }

  CodeGenAdapter? _resolveAdapter(String style) {
    switch (style) {
      case 'riverpod_manual':
        return RiverpodManualCodeGen();
      case 'bloc':
        return BlocCodeGen();
      default:
        return null;
    }
  }
}
