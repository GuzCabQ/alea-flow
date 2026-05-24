import 'dart:io';
import 'package:alea_flow/src/core/git/changed_files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('compareChangedFiles', () {
    late Directory repo;
    void git(List<String> a) {
      final r = Process.runSync('git', ['-C', repo.path, ...a]);
      if (r.exitCode != 0) throw StateError('git ${a.join(" ")}: ${r.stderr}');
    }

    void write(String rel, String c) {
      final f = File(p.join(repo.path, rel))
        ..parent.createSync(recursive: true);
      f.writeAsStringSync(c);
    }

    setUp(() {
      repo = Directory.systemTemp.createTempSync('alea_cf_');
      git(['init']);
      git(['config', 'user.email', 't@e.com']);
      git(['config', 'user.name', 'T']);
      write('lib/a.dart', 'class A {}\n');
      git(['add', '.']);
      git(['commit', '-m', 'base']);
    });
    tearDown(() => repo.deleteSync(recursive: true));

    test(
      'undeclared = changed but not declared; stale = declared not changed',
      () {
        write('lib/a.dart', 'class A { int x = 0; }\n'); // modified
        write('lib/b.dart', 'class B {}\n'); // new untracked
        final r = compareChangedFiles(
          projectRoot: repo.path,
          declared: {'lib/a.dart', 'lib/ghost.dart'},
        );
        expect(r.undeclared, contains('lib/b.dart'));
        expect(r.stale, contains('lib/ghost.dart'));
      },
    );

    test('throws ChangedFilesException when not a git repo', () {
      final tmp = Directory.systemTemp.createTempSync('alea_notgit_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      expect(
        () => compareChangedFiles(projectRoot: tmp.path, declared: {}),
        throwsA(isA<ChangedFilesException>()),
      );
    });
  });
}
