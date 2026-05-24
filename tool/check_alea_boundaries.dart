// ALEA — self-boundary CI guard.
//
// Loads `alea/.alea.yaml`, scans `alea/lib/`, runs PackageBoundaryAnalyzer
// against ALEA itself, and exits non-zero if any boundary is violated.
//
// Run from the alea/ directory:
//
//   dart run tool/check_alea_boundaries.dart
//
// Exit codes:
//   0 — every boundary passed.
//   1 — at least one boundary violation (blocker).
//   2 — config error (.alea.yaml missing or malformed).

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final projectRoot = p.normalize(Directory.current.absolute.path);

  late final ProjectConfig config;
  try {
    config = loadProjectConfig(projectRoot);
  } on ProjectConfigException catch (e) {
    stderr.writeln('ALEA self-config error: $e');
    exit(2);
  }

  final files = _collectDartFiles(p.join(projectRoot, 'lib'));
  if (files.isEmpty) {
    stderr.writeln('No Dart files found under lib/. Aborting.');
    exit(2);
  }

  final runner = AnalyzerRunner([PackageBoundaryAnalyzer()]);
  final report = await runner.run(
    gate: 'self_boundary',
    filePaths: files,
    projectRoot: projectRoot,
    config: config,
  );

  stdout.writeln(GateReporter().toHumanReadable(report));

  exit(report.passed ? 0 : 1);
}

List<String> _collectDartFiles(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => p.normalize(f.absolute.path))
      .toList(growable: false);
}
