import 'package:alea_flow/src/matching/fuzzy_score.dart';
import 'package:test/test.dart';

void main() {
  group('tokenize', () {
    test('splits whitespace', () {
      expect(tokenize('hola que tal'), ['hola', 'que', 'tal']);
    });

    test('splits camelCase', () {
      expect(
        tokenize('ButtonSaveSCIComponent'),
        // SCI is consumed as a single uppercase run; no lowercase-to-upper
        // transition there. Verify it parses to lowercased tokens.
        containsAllInOrder(['button', 'save']),
      );
    });

    test('splits punctuation', () {
      expect(tokenize('foo-bar_baz.qux'), ['foo', 'bar', 'baz', 'qux']);
    });

    test('lowercases', () {
      expect(tokenize('ALLCAPS'), ['allcaps']);
    });

    test('folds Spanish diacritics', () {
      expect(tokenize('botón guardar'), ['boton', 'guardar']);
      expect(tokenize('canción mañana'), ['cancion', 'manana']);
    });

    test('empty string returns empty list', () {
      expect(tokenize(''), isEmpty);
    });

    test('only punctuation returns empty list', () {
      expect(tokenize('---___---'), isEmpty);
    });
  });

  group('fuzzyScore', () {
    test('identical strings → 1.0', () {
      expect(fuzzyScore('button save', 'button save'), 1.0);
    });

    test('substring containment bonus is significant', () {
      // 'guardar' is contained in 'ButtonGuardarSciComponent' → bonus.
      final score = fuzzyScore('guardar', 'ButtonGuardarSciComponent');
      expect(score, greaterThan(0.4));
    });

    test('disjoint vocab → low score', () {
      expect(fuzzyScore('xyz', 'button save'), lessThan(0.1));
    });

    test('case- and diacritic-insensitive', () {
      // 'botón' should match 'Boton' (lowercased + diacritic-folded).
      expect(fuzzyScore('botón', 'BotonSaveComponent'), greaterThan(0.3));
    });

    test('empty inputs short-circuit to 0', () {
      expect(fuzzyScore('', 'foo'), 0.0);
      expect(fuzzyScore('foo', ''), 0.0);
    });
  });
}
