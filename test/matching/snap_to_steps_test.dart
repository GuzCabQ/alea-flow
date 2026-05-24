import 'package:alea_flow/src/matching/snap_to_steps.dart';
import 'package:test/test.dart';

void main() {
  group('snapToSteps', () {
    test('exact match has distance 0', () {
      final r = snapToSteps(8, [4, 8, 12]);
      expect(r.snapped, 8);
      expect(r.distance, 0);
    });

    test('snaps to the closer of two surrounding steps', () {
      final r = snapToSteps(5, [4, 8]);
      expect(r.snapped, 4);
      expect(r.distance, 1);
    });

    test('ties break to the smaller step', () {
      final r = snapToSteps(6, [4, 8]);
      expect(r.snapped, 4);
      expect(r.distance, 2);
    });

    test('handles negative values', () {
      final r = snapToSteps(-3, [-4, 0, 4]);
      expect(r.snapped, -4);
      expect(r.distance, 1);
    });

    test('empty list throws ArgumentError', () {
      expect(() => snapToSteps(0, const []), throwsArgumentError);
    });
  });

  group('snapToMultiple', () {
    test('snaps to the nearest multiple of step', () {
      expect(snapToMultiple(17, 4), 16);
      expect(snapToMultiple(18, 4), 20);
    });

    test('respects base offset', () {
      // Steps: 2, 6, 10, 14 (base=2, step=4).
      expect(snapToMultiple(8, 4, base: 2), 10);
    });

    test('step <= 0 throws', () {
      expect(() => snapToMultiple(1, 0), throwsArgumentError);
      expect(() => snapToMultiple(1, -1), throwsArgumentError);
    });
  });

  group('isCleanAgainst', () {
    test('returns true when within tolerance', () {
      expect(isCleanAgainst(5.4, [5, 10], tolerance: 0.5), isTrue);
    });

    test('returns false when outside tolerance', () {
      expect(isCleanAgainst(7, [5, 10], tolerance: 0.5), isFalse);
    });
  });
}
