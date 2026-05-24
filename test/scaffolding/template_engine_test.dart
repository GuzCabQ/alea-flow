import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateEngine', () {
    final engine = TemplateEngine();

    test('substitutes a single placeholder', () {
      expect(engine.render('hi {{who}}!', {'who': 'world'}), 'hi world!');
    });

    test('substitutes multiple placeholders', () {
      expect(
        engine.render('class {{class}} extends {{base}} {}', {
          'class': 'Foo',
          'base': 'Bar',
        }),
        'class Foo extends Bar {}',
      );
    });

    test('throws on missing required variable', () {
      expect(
        () => engine.render('hi {{name}}', {}),
        throwsA(isA<TemplateRenderException>()),
      );
    });

    test('honours fallback when variable absent', () {
      expect(engine.render('hi {{name|stranger}}', {}), 'hi stranger');
    });

    test('comment placeholders are stripped', () {
      expect(engine.render('a{{! drop me}}b', {}), 'ab');
    });

    test('placeholdersOf returns declared variables, skipping comments', () {
      const tpl = '{{a}} + {{b|fallback}} {{!ignored}}';
      expect(engine.placeholdersOf(tpl), {'a', 'b'});
    });

    test('non-placeholder text preserved byte-for-byte', () {
      const tpl = '''
import 'package:flutter/material.dart';

class {{class}} {
  const {{class}}();
}
''';
      final rendered = engine.render(tpl, {'class': 'X'});
      expect(rendered, '''
import 'package:flutter/material.dart';

class X {
  const X();
}
''');
    });
  });
}
