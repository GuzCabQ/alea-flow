// Tests for `aflow check-files-changed` — the git cross-check primitive.
//
// Builds a real temp git repo (baseline commit, then modifications) and runs
// the command against it. Pure deterministic set comparison; no consumer
// project needed.

import 'dart:convert';
import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('check-files-changed command', () {
    late Directory repo;

    void git(List<String> args) {
      final r = Process.runSync('git', ['-C', repo.path, ...args]);
      if (r.exitCode != 0) {
        throw StateError('git ${args.join(" ")} failed: ${r.stderr}');
      }
    }

    void write(String rel, String content) {
      final f = File(p.join(repo.path, rel));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(content);
    }

    setUp(() {
      repo = Directory.systemTemp.createTempSync('alea_cfc_');
      git(['init']);
      git(['config', 'user.email', 'test@example.com']);
      git(['config', 'user.name', 'Test']);
      write('lib/a.dart', 'class A {}\n');
      git(['add', '.']);
      git(['commit', '-m', 'baseline']);
    });
    tearDown(() => repo.deleteSync(recursive: true));

    /// Run the command with the given declared files; return exit code + parsed JSON.
    Future<({int code, Map<String, Object?> json})> run(
      List<String> declared,
    ) async {
      final args = <String>[
        'check-files-changed',
        '--project-root',
        repo.path,
        '--format',
        'json',
      ];
      for (final d in declared) {
        args
          ..add('--declared')
          ..add(d);
      }
      late int code;
      final out = await _captureStdout(() async {
        code = await AleaCliRunner().run(args);
      });
      return (code: code, json: jsonDecode(out.trim()) as Map<String, Object?>);
    }

    test('declared matches actual (modify + new) → passes, exit 0', () async {
      write('lib/a.dart', 'class A { int x = 0; }\n'); // modify
      write('lib/b.dart', 'class B {}\n'); // new (untracked)

      final r = await run(['lib/a.dart', 'lib/b.dart']);
      expect(r.code, 0);
      expect(r.json['passed'], true);
      expect(r.json['undeclared'], isEmpty);
    });

    test('a changed file missing from declared → fails, exit 1', () async {
      write('lib/a.dart', 'class A { int x = 0; }\n');
      write('lib/b.dart', 'class B {}\n'); // changed but NOT declared

      final r = await run(['lib/a.dart']);
      expect(r.code, 1);
      expect(r.json['passed'], false);
      expect(r.json['undeclared'], contains('lib/b.dart'));
    });

    test('declared-but-unchanged is stale (advisory), still passes', () async {
      write('lib/a.dart', 'class A { int x = 0; }\n'); // only this changed

      final r = await run(['lib/a.dart', 'lib/ghost.dart']);
      expect(r.code, 0); // stale never fails
      expect(r.json['passed'], true);
      expect(r.json['stale'], contains('lib/ghost.dart'));
    });

    test('not a git repository → exit 2', () async {
      final notRepo = Directory.systemTemp.createTempSync('alea_notgit_');
      addTearDown(() => notRepo.deleteSync(recursive: true));
      final code = await AleaCliRunner().run([
        'check-files-changed',
        '--project-root',
        notRepo.path,
        '--declared',
        'lib/a.dart',
      ]);
      expect(code, 2);
    });
  });
}

// ── stdout capture ───────────────────────────────────────────────────────────

Future<String> _captureStdout(Future<void> Function() body) async {
  final buffer = StringBuffer();
  await IOOverrides.runZoned(body, stdout: () => _CapturingStdout(buffer));
  return buffer.toString();
}

class _CapturingStdout implements Stdout {
  _CapturingStdout(this._buffer);
  final StringBuffer _buffer;

  @override
  void write(Object? object) => _buffer.write(object);
  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String sep = '']) =>
      _buffer.writeAll(objects, sep);
  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);
  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data));
  @override
  Encoding encoding = utf8;
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> get done => Future<void>.value();
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      throw UnimplementedError();
  @override
  Future<void> addStream(Stream<List<int>> stream) async =>
      throw UnimplementedError();
  @override
  bool get hasTerminal => false;
  @override
  IOSink get nonBlocking => throw UnimplementedError();
  @override
  bool get supportsAnsiEscapes => false;
  @override
  int get terminalColumns => throw UnimplementedError();
  @override
  int get terminalLines => throw UnimplementedError();
  @override
  String lineTerminator = '\n';
}
