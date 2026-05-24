// ALEA — git changed-files comparison.
// Pure git-diff comparison: declared file set vs what git actually changed.
// Extracted from check_files_changed_command for in-process reuse by the driver.
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

class ChangedFilesException implements Exception {
  final String message;
  const ChangedFilesException(this.message);
  @override
  String toString() => 'ChangedFilesException: $message';
}

class ChangedFiles {
  final Set<String> actual;
  final List<String> undeclared; // changed but not declared (dangerous)
  final List<String> stale; // declared but not changed (advisory)
  const ChangedFiles(this.actual, this.undeclared, this.stale);
}

ChangedFiles compareChangedFiles({
  required String projectRoot,
  required Set<String> declared,
  String base = 'HEAD',
  bool includeUntracked = true,
}) {
  ProcessResult git(List<String> args) =>
      Process.runSync('git', ['-C', projectRoot, ...args]);

  if (git(['rev-parse', '--is-inside-work-tree']).exitCode != 0) {
    throw ChangedFilesException('not a git repository: $projectRoot');
  }
  final diff = git(['diff', '--name-only', base]);
  if (diff.exitCode != 0) {
    throw ChangedFilesException(
      'git diff failed: ${(diff.stderr as String).trim()}',
    );
  }
  String norm(String s) => p.normalize(s.trim()).replaceAll(r'\', '/');
  Iterable<String> lines(String s) =>
      const LineSplitter().convert(s).where((l) => l.trim().isNotEmpty);

  final actual = <String>{...lines(diff.stdout as String).map(norm)};
  if (includeUntracked) {
    final u = git(['ls-files', '--others', '--exclude-standard']);
    actual.addAll(lines(u.stdout as String).map(norm));
  }
  final declaredNorm = declared.map(norm).toSet();
  final undeclared = actual.difference(declaredNorm).toList()..sort();
  final stale = declaredNorm.difference(actual).toList()..sort();
  return ChangedFiles(actual, undeclared, stale);
}
