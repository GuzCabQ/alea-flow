// ALEA — pure command installer: render + write, no stdin, no exit().

import 'dart:io';

import '../../contracts/platform_command_adapter.dart';

/// One written (or would-be-written) command file.
class WrittenFile {
  final String platformId;
  final String path;

  /// True if a file already existed at [path] before this run.
  final bool existed;

  const WrittenFile({
    required this.platformId,
    required this.path,
    required this.existed,
  });
}

class InstallReport {
  final List<WrittenFile> files;
  const InstallReport(this.files);
}

/// Render every [prompts] entry through every [adapters] entry and write each
/// to its target path under [projectRoot]. Overwrites existing files (they are
/// alea-flow-managed). When [dryRun] is true, computes the report without
/// touching disk.
Future<InstallReport> installCommands({
  required List<CommandPrompt> prompts,
  required List<PlatformCommandAdapter> adapters,
  required String projectRoot,
  bool dryRun = false,
}) async {
  final written = <WrittenFile>[];
  for (final adapter in adapters) {
    for (final prompt in prompts) {
      final path = adapter.targetPath(prompt.id, projectRoot: projectRoot);
      final file = File(path);
      final existed = file.existsSync();
      if (!dryRun) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(adapter.render(prompt));
      }
      written.add(
        WrittenFile(
          platformId: adapter.platformId,
          path: path,
          existed: existed,
        ),
      );
    }
  }
  return InstallReport(written);
}
