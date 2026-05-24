import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ScaffoldExecutor — files', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('alea_executor_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('create writes a new file under projectRoot', () async {
      final exec = ScaffoldExecutor(projectRoot: root.path);
      final outcomes = await exec.apply(
        const ScaffoldPlan(
          adapterName: 'test',
          files: [
            GeneratedFile(relativePath: 'lib/a.dart', content: 'class A {}'),
          ],
        ),
      );
      expect(outcomes.single.action, ScaffoldAction.create);
      expect(
        File(p.join(root.path, 'lib/a.dart')).readAsStringSync(),
        'class A {}',
      );
    });

    test('skip when content matches existing file (idempotency)', () async {
      final file = File(p.join(root.path, 'lib/a.dart'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('class A {}');

      final exec = ScaffoldExecutor(projectRoot: root.path);
      final outcomes = await exec.apply(
        const ScaffoldPlan(
          adapterName: 'test',
          files: [
            GeneratedFile(relativePath: 'lib/a.dart', content: 'class A {}'),
          ],
        ),
      );
      expect(outcomes.single.action, ScaffoldAction.skip);
    });

    test('modify when content differs from existing file', () async {
      final file = File(p.join(root.path, 'lib/a.dart'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('class A {}');

      final exec = ScaffoldExecutor(projectRoot: root.path);
      final outcomes = await exec.apply(
        const ScaffoldPlan(
          adapterName: 'test',
          files: [
            GeneratedFile(
              relativePath: 'lib/a.dart',
              content: 'class A { final int x = 0; }',
            ),
          ],
        ),
      );
      expect(outcomes.single.action, ScaffoldAction.modify);
      expect(outcomes.single.previousContent, 'class A {}');
    });

    test('rejects absolute paths', () async {
      final exec = ScaffoldExecutor(projectRoot: root.path);
      expect(
        () => exec.apply(
          const ScaffoldPlan(
            adapterName: 'test',
            files: [GeneratedFile(relativePath: '/abs/path.dart', content: '')],
          ),
        ),
        throwsA(isA<ScaffoldPlanException>()),
      );
    });

    test('rejects parent-directory traversal', () async {
      final exec = ScaffoldExecutor(projectRoot: root.path);
      expect(
        () => exec.apply(
          const ScaffoldPlan(
            adapterName: 'test',
            files: [
              GeneratedFile(
                relativePath: 'lib/../../../etc/passwd',
                content: '',
              ),
            ],
          ),
        ),
        throwsA(isA<ScaffoldPlanException>()),
      );
    });

    test('rejects duplicate file entries', () async {
      final exec = ScaffoldExecutor(projectRoot: root.path);
      expect(
        () => exec.apply(
          const ScaffoldPlan(
            adapterName: 'test',
            files: [
              GeneratedFile(relativePath: 'lib/a.dart', content: 'A'),
              GeneratedFile(relativePath: 'lib/a.dart', content: 'B'),
            ],
          ),
        ),
        throwsA(isA<ScaffoldPlanException>()),
      );
    });
  });

  group('ScaffoldExecutor — rollback', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('alea_executor_rb_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('rollback deletes created files', () async {
      final exec = ScaffoldExecutor(projectRoot: root.path);
      final outcomes = await exec.apply(
        const ScaffoldPlan(
          adapterName: 'test',
          files: [
            GeneratedFile(
              relativePath: 'lib/new.dart',
              content: 'class New {}',
            ),
          ],
        ),
      );
      expect(File(p.join(root.path, 'lib/new.dart')).existsSync(), isTrue);
      await exec.rollback(outcomes);
      expect(File(p.join(root.path, 'lib/new.dart')).existsSync(), isFalse);
    });

    test('rollback restores modified files byte-for-byte', () async {
      final file = File(p.join(root.path, 'lib/m.dart'));
      file.parent.createSync(recursive: true);
      const original = 'class M { final int x = 1; }';
      file.writeAsStringSync(original);

      final exec = ScaffoldExecutor(projectRoot: root.path);
      final outcomes = await exec.apply(
        const ScaffoldPlan(
          adapterName: 'test',
          files: [
            GeneratedFile(
              relativePath: 'lib/m.dart',
              content: 'class M { final int x = 999; }',
            ),
          ],
        ),
      );
      expect(outcomes.single.action, ScaffoldAction.modify);
      await exec.rollback(outcomes);
      expect(file.readAsStringSync(), original);
    });

    test('rollback is a no-op for skip outcomes', () async {
      final file = File(p.join(root.path, 'lib/s.dart'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('class S {}');

      final exec = ScaffoldExecutor(projectRoot: root.path);
      final outcomes = await exec.apply(
        const ScaffoldPlan(
          adapterName: 'test',
          files: [
            GeneratedFile(relativePath: 'lib/s.dart', content: 'class S {}'),
          ],
        ),
      );
      expect(outcomes.single.action, ScaffoldAction.skip);
      final rolled = await exec.rollback(outcomes);
      expect(rolled.single.action, ScaffoldAction.skip);
      expect(file.readAsStringSync(), 'class S {}');
    });
  });

  group('ScaffoldExecutor — patches', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('alea_executor_patch_');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('insertAfterAnchor adds insertion below the anchor line', () async {
      final manifest = File(p.join(root.path, 'lib/manifest.dart'));
      manifest.parent.createSync(recursive: true);
      manifest.writeAsStringSync('''
class Manifest {
  // anchor
  void register() {}
}
''');
      final exec = ScaffoldExecutor(projectRoot: root.path);
      await exec.apply(
        const ScaffoldPlan(
          adapterName: 'test',
          patches: [
            WiringPatch(
              relativePath: 'lib/manifest.dart',
              mode: WiringPatchMode.insertAfterAnchor,
              anchor: '// anchor',
              insertion: '  registerSingleton(FooService());',
            ),
          ],
        ),
      );
      expect(
        manifest.readAsStringSync(),
        contains('// anchor\n  registerSingleton(FooService());'),
      );
    });

    test('skip when insertion already present', () async {
      final manifest = File(p.join(root.path, 'lib/manifest.dart'));
      manifest.parent.createSync(recursive: true);
      manifest.writeAsStringSync(
        'class Manifest {\n  registerSingleton(FooService());\n}\n',
      );

      final exec = ScaffoldExecutor(projectRoot: root.path);
      final outcomes = await exec.apply(
        const ScaffoldPlan(
          adapterName: 'test',
          patches: [
            WiringPatch(
              relativePath: 'lib/manifest.dart',
              mode: WiringPatchMode.insertAfterAnchor,
              anchor: 'class Manifest',
              insertion: 'registerSingleton(FooService());',
            ),
          ],
        ),
      );
      expect(outcomes.single.action, ScaffoldAction.skip);
    });

    test('appendIfMissing appends to end of file', () async {
      final manifest = File(p.join(root.path, 'lib/manifest.dart'));
      manifest.parent.createSync(recursive: true);
      manifest.writeAsStringSync('class Manifest {}\n');

      final exec = ScaffoldExecutor(projectRoot: root.path);
      await exec.apply(
        const ScaffoldPlan(
          adapterName: 'test',
          patches: [
            WiringPatch(
              relativePath: 'lib/manifest.dart',
              mode: WiringPatchMode.appendIfMissing,
              insertion: '// added by patch',
            ),
          ],
        ),
      );
      expect(manifest.readAsStringSync(), contains('// added by patch'));
    });
  });
}
