import 'package:alea_flow/src/matching/jaccard.dart';
import 'package:test/test.dart';

void main() {
  group('jaccardSimilarity', () {
    test('identical sets → 1.0', () {
      expect(jaccardSimilarity({'a', 'b', 'c'}, {'a', 'b', 'c'}), 1.0);
    });

    test('disjoint sets → 0.0', () {
      expect(jaccardSimilarity({'a'}, {'b'}), 0.0);
    });

    test('both empty → 1.0 (defined for our use case)', () {
      expect(jaccardSimilarity<String>({}, {}), 1.0);
    });

    test('partial overlap: 1 of 3 → 1/3', () {
      expect(jaccardSimilarity({'a', 'b'}, {'a', 'c'}), closeTo(1 / 3, 1e-9));
    });
  });

  group('jaccardAsymmetric', () {
    test('query fully covered by candidate yields high score', () {
      final s = jaccardAsymmetric({'a', 'b'}, {'a', 'b', 'c', 'd', 'e'});
      // Intersection=2, denom=2 + 0.3*5 = 3.5 → 2/3.5 ≈ 0.571
      expect(s, closeTo(0.571, 0.01));
    });

    test('candidate-side enlargement is dampened by weight', () {
      final tight = jaccardAsymmetric({'a'}, {'a', 'b'}, weight: 0.3);
      final loose = jaccardAsymmetric(
        {'a'},
        {'a', 'b', 'c', 'd', 'e'},
        weight: 0.3,
      );
      // Both contain query; the larger candidate scores lower but not by much.
      expect(tight, greaterThan(loose));
      expect(loose, greaterThan(0.3));
    });

    test('empty query and candidate → 1.0', () {
      expect(jaccardAsymmetric<String>({}, {}), 1.0);
    });

    test('empty intersection → 0', () {
      expect(jaccardAsymmetric({'x'}, {'a', 'b'}), 0.0);
    });
  });
}
