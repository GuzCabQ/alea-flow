// Tests for SymbolDigest.

import 'dart:io';

import 'package:alea_flow/src/inventory/symbol_digest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('extractSymbolDigest', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('alea_symbol_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('captures public class with extends, fields, methods, ctor', () {
      final path = p.join(tmp.path, 'card.dart');
      File(path).writeAsStringSync('''
import 'package:flutter/material.dart';

class CardComponent extends StatelessWidget {
  final Color color;
  final String label;

  const CardComponent({required this.color, required this.label});

  static const String defaultLabel = 'card';

  @override
  Widget build(BuildContext context) {
    return Container(color: color, child: Text(label));
  }

  int get size => label.length;
}
''');
      final digest = extractSymbolDigest(path);
      expect(digest.classes, hasLength(1));
      final cls = digest.classes.single;
      expect(cls.name, 'CardComponent');
      expect(cls.extendsName, 'StatelessWidget');
      final kinds = cls.members.map((m) => '${m.kind}:${m.name}').toList();
      expect(
        kinds,
        containsAll([
          'field:color',
          'field:label',
          'field:defaultLabel',
          'constructor:CardComponent',
          'method:build',
          'getter:size',
        ]),
      );
    });

    test('omits private members and private classes', () {
      final path = p.join(tmp.path, 'private.dart');
      File(path).writeAsStringSync('''
class Public {
  void _private() {}
  void exposed() {}
}

class _PrivateClass {}
''');
      final digest = extractSymbolDigest(path);
      expect(digest.classes, hasLength(1));
      expect(digest.classes.single.name, 'Public');
      final memberNames = digest.classes.single.members
          .map((m) => m.name)
          .toList();
      expect(memberNames, ['exposed']);
    });

    test('captures top-level functions and consts', () {
      final path = p.join(tmp.path, 'tops.dart');
      File(path).writeAsStringSync('''
const String API_URL = 'https://example.com';

int sum(int a, int b) => a + b;

void _private() {}
''');
      final digest = extractSymbolDigest(path);
      final names = digest.topLevels.map((t) => '${t.kind}:${t.name}').toList();
      expect(names, ['const:API_URL', 'function:sum']);
    });

    test('throws FileSystemException when file does not exist', () {
      expect(
        () => extractSymbolDigest('/does/not/exist.dart'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('render() omits bodies and produces stable text output', () {
      final path = p.join(tmp.path, 'render.dart');
      File(path).writeAsStringSync('''
class Foo {
  final int x;
  Foo(this.x);
  int double() => x * 2;
}
''');
      final digest = extractSymbolDigest(path);
      final rendered = digest.render();
      expect(rendered, contains('class Foo'));
      expect(rendered, contains('final int x'));
      expect(rendered, contains('int double()'));
      // No bodies leaked.
      expect(rendered.contains('=> x * 2'), isFalse);
    });

    test('render() achieves ≥70% character reduction for a >100-line file', () {
      final path = p.join(tmp.path, 'big.dart');
      // Generate a synthetic but realistic widget file.
      final src = StringBuffer();
      src.writeln("import 'package:flutter/material.dart';");
      src.writeln();
      src.writeln('class BigWidgetComponent extends StatelessWidget {');
      for (var i = 0; i < 20; i++) {
        src.writeln('  final String field$i;');
      }
      src.writeln('  const BigWidgetComponent({');
      for (var i = 0; i < 20; i++) {
        src.writeln('    required this.field$i,');
      }
      src.writeln('  });');
      for (var i = 0; i < 8; i++) {
        src.writeln();
        src.writeln('  Widget method$i(BuildContext context) {');
        src.writeln('    final theme = Theme.of(context);');
        src.writeln('    final mediaQuery = MediaQuery.of(context);');
        src.writeln('    final result = field0 + field1 + field2;');
        src.writeln('    final children = <Widget>[');
        src.writeln('      Padding(');
        src.writeln(
          '        padding: const EdgeInsets.symmetric(horizontal: 16),',
        );
        src.writeln(
          '        child: Text(result, style: theme.textTheme.bodyMedium),',
        );
        src.writeln('      ),');
        src.writeln('      const SizedBox(height: 8),');
        src.writeln('      Container(');
        src.writeln('        padding: const EdgeInsets.all(12),');
        src.writeln('        decoration: BoxDecoration(');
        src.writeln('          color: theme.colorScheme.surface,');
        src.writeln('          borderRadius: BorderRadius.circular(8),');
        src.writeln('        ),');
        src.writeln('        child: Text(field$i),');
        src.writeln('      ),');
        src.writeln('    ];');
        src.writeln('    return ListView(children: children);');
        src.writeln('  }');
      }
      src.writeln('}');
      File(path).writeAsStringSync(src.toString());

      final original = File(path).readAsStringSync();
      expect(original.split('\n').length, greaterThan(100));

      final digest = extractSymbolDigest(path);
      final rendered = digest.render();

      final ratio = rendered.length / original.length;
      expect(
        ratio,
        lessThanOrEqualTo(0.30),
        reason:
            'digest should be ≤30% of original; observed '
            '${(ratio * 100).toStringAsFixed(1)}%',
      );
    });

    test('toJson is JSON-safe and round-trip-friendly', () {
      final path = p.join(tmp.path, 'json.dart');
      File(path).writeAsStringSync('''
abstract class Base {
  void noop();
}

class Impl extends Base implements Comparable<Impl> {
  @override
  void noop() {}

  @override
  int compareTo(Impl other) => 0;
}
''');
      final digest = extractSymbolDigest(path);
      final json = digest.toJson();
      expect(json['file_path'], path);
      expect(json['classes'], isA<List>());
      final classes = json['classes'] as List;
      final base =
          classes.firstWhere((c) => c['name'] == 'Base')
              as Map<String, Object?>;
      expect(base['abstract'], isTrue);
      final impl =
          classes.firstWhere((c) => c['name'] == 'Impl')
              as Map<String, Object?>;
      expect(impl['extends'], 'Base');
      expect(impl['implements'], contains('Comparable<Impl>'));
    });

    test('projectRoot makes filePath relative', () {
      final path = p.join(tmp.path, 'rel.dart');
      File(path).writeAsStringSync('class Foo {}');
      final digest = extractSymbolDigest(path, projectRoot: tmp.path);
      expect(digest.filePath, 'rel.dart');
    });
  });
}
