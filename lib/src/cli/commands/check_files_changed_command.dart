// ALEA — `aflow check-files-changed` subcommand.
//
// Cross-checks a declared `files_changed` list (e.g. from a `<layer>_impl.md`)
// against what git actually sees, so a commit driven by that list never
// silently misses a file. Pure, deterministic set comparison (bucket 1):
//
//   actual     = `git diff --name-only <base>` ∪ untracked files
//   undeclared = actual − declared   ← the dangerous set (would be missed)
//   stale      = declared − actual   ← advisory (declared but unchanged)
//
// Exit 0 iff `undeclared` is empty. `stale` only warns — it never fails the
// check (a stale declaration is harmless; a missed change is not).

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../core/git/changed_files.dart';

class CheckFilesChangedCommand extends Command<int> {
  CheckFilesChangedCommand() {
    argParser
      ..addMultiOption(
        'declared',
        abbr: 'd',
        help: 'A declared changed file (repeat for each). Project-relative.',
        valueHelp: 'lib/foo.dart',
      )
      ..addOption(
        'project-root',
        abbr: 'r',
        defaultsTo: '.',
        help: 'Root of the git repository.',
      )
      ..addOption(
        'base',
        abbr: 'b',
        defaultsTo: 'HEAD',
        help: 'Git ref to diff tracked changes against.',
      )
      ..addFlag(
        'include-untracked',
        defaultsTo: true,
        help: 'Count untracked (new) files as changed.',
      )
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['text', 'json'],
        defaultsTo: 'text',
        help: 'Output format.',
      );
  }

  @override
  String get name => 'check-files-changed';

  @override
  String get description =>
      'Verify a declared files_changed list matches what git actually changed.';

  @override
  Future<int> run() async {
    final res = argResults!;
    final projectRoot = p.canonicalize(res['project-root'] as String);
    final base = res['base'] as String;
    final includeUntracked = res['include-untracked'] as bool;
    final format = res['format'] as String;
    final declared = (res['declared'] as List<String>).toSet();

    final ChangedFiles cf;
    try {
      cf = compareChangedFiles(
        projectRoot: projectRoot,
        declared: declared,
        base: base,
        includeUntracked: includeUntracked,
      );
    } on ChangedFilesException catch (e) {
      stderr.writeln(e.message);
      return 2;
    }

    final undeclared = cf.undeclared;
    final stale = cf.stale;
    final actual = cf.actual;
    final passed = undeclared.isEmpty;

    if (format == 'json') {
      stdout.writeln(
        jsonEncode({
          'base': base,
          'declared': declared.toList()..sort(),
          'actual': actual.toList()..sort(),
          'undeclared': undeclared,
          'stale': stale,
          'passed': passed,
        }),
      );
    } else {
      stdout.writeln('Files-changed check (base: $base)');
      stdout.writeln(
        '  declared: ${declared.length}  actual: ${actual.length}',
      );
      if (undeclared.isNotEmpty) {
        stdout.writeln('  ✗ undeclared (changed but not declared):');
        for (final f in undeclared) {
          stdout.writeln('     - $f');
        }
      }
      if (stale.isNotEmpty) {
        stdout.writeln('  ⚠ stale (declared but not changed):');
        for (final f in stale) {
          stdout.writeln('     - $f');
        }
      }
      stdout.writeln('Status: ${passed ? "PASS" : "FAIL"}');
    }

    return passed ? 0 : 1;
  }
}
