// Smoke test for `package:alea_flow/matching.dart` — confirms the public symbols
// are reachable through the pure entry point and nothing more.

import 'package:alea_flow/matching.dart';
import 'package:test/test.dart';

void main() {
  test('color distance symbols are exported', () {
    expect(deltaE2000FromRgb(0, 0, 0, 0, 0, 0), 0);
    expect(srgbToLab(255, 255, 255), isA<Lab>());
  });

  test('jaccard symbols are exported', () {
    expect(jaccardSimilarity({'a'}, {'a'}), 1.0);
    expect(jaccardAsymmetric({'a'}, {'a'}), greaterThan(0));
  });

  test('fuzzy_score symbols are exported', () {
    expect(tokenize('Foo Bar'), ['foo', 'bar']);
    expect(fuzzyScore('foo', 'Foo bar'), greaterThan(0.5));
    expect(foldDiacritics('botón'), 'boton');
  });

  test('snap_to_steps symbols are exported', () {
    expect(snapToSteps(5, [4, 8]).snapped, 4);
    expect(snapToMultiple(17, 4), 16);
    expect(isCleanAgainst(5.4, [5, 10]), isTrue);
  });
}
