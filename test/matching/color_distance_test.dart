// Tests for the CIEDE2000 color-distance implementation.
//
// Reference values come from Sharma, Wu, Dalal (2005) — the canonical paper
// that defined ΔE CIE2000 — plus identity/symmetry property checks.

import 'package:alea_flow/src/matching/color_distance.dart';
import 'package:test/test.dart';

void main() {
  group('srgbToLab', () {
    test('white (255,255,255) maps to ~L=100, a=0, b=0', () {
      final lab = srgbToLab(255, 255, 255);
      expect(lab.l, closeTo(100, 0.5));
      expect(lab.a, closeTo(0, 0.5));
      expect(lab.b, closeTo(0, 0.5));
    });

    test('black (0,0,0) maps to L=0, a=0, b=0', () {
      final lab = srgbToLab(0, 0, 0);
      expect(lab.l, closeTo(0, 0.01));
      expect(lab.a, closeTo(0, 0.01));
      expect(lab.b, closeTo(0, 0.01));
    });

    test('pure red sits in the red quadrant (a > 0, |b| > 0)', () {
      final lab = srgbToLab(255, 0, 0);
      expect(lab.a, greaterThan(50));
      expect(lab.b, isNot(0));
    });
  });

  group('deltaE2000 — properties', () {
    test('identity: ΔE(c, c) = 0', () {
      final lab = srgbToLab(0xDA, 0x18, 0x84);
      expect(deltaE2000(lab, lab), closeTo(0, 1e-9));
    });

    test('symmetry: ΔE(c1, c2) ≈ ΔE(c2, c1)', () {
      final a = srgbToLab(0xDA, 0x18, 0x84);
      final b = srgbToLab(0xE0, 0xF5, 0xF5);
      expect(deltaE2000(a, b), closeTo(deltaE2000(b, a), 1e-9));
    });

    test('non-negativity over a sampling of pairs', () {
      // 20 deterministic pseudo-random pairs (LCG, no rng dep).
      var seed = 12345;
      int next() {
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF;
        return seed;
      }

      for (var i = 0; i < 20; i++) {
        final lab1 = srgbToLab(next() & 0xFF, next() & 0xFF, next() & 0xFF);
        final lab2 = srgbToLab(next() & 0xFF, next() & 0xFF, next() & 0xFF);
        final d = deltaE2000(lab1, lab2);
        expect(
          d,
          greaterThanOrEqualTo(0),
          reason: 'ΔE must be non-negative; pair $i returned $d',
        );
      }
    });
  });

  group('deltaE2000 — known values', () {
    // Sharma reference set, expressed as direct Lab pairs to avoid sRGB
    // roundtrip noise. Tolerance 0.05 absorbs floating-point variance across
    // platforms.
    final cases = <({Lab a, Lab b, double expected})>[
      (
        a: const Lab(50.0000, 2.6772, -79.7751),
        b: const Lab(50.0000, 0.0000, -82.7485),
        expected: 2.0425,
      ),
      (
        a: const Lab(50.0000, 3.1571, -77.2803),
        b: const Lab(50.0000, 0.0000, -82.7485),
        expected: 2.8615,
      ),
      (
        a: const Lab(50.0000, 2.8361, -74.0200),
        b: const Lab(50.0000, 0.0000, -82.7485),
        expected: 3.4412,
      ),
      (
        a: const Lab(50.0000, -1.3802, -84.2814),
        b: const Lab(50.0000, 0.0000, -82.7485),
        expected: 1.0000,
      ),
      (
        a: const Lab(50.0000, -1.1848, -84.8006),
        b: const Lab(50.0000, 0.0000, -82.7485),
        expected: 1.0000,
      ),
      (
        a: const Lab(50.0000, -0.9009, -85.5211),
        b: const Lab(50.0000, 0.0000, -82.7485),
        expected: 1.0000,
      ),
      (
        a: const Lab(50.0000, 0.0000, 0.0000),
        b: const Lab(50.0000, -1.0000, 2.0000),
        expected: 2.3669,
      ),
    ];

    for (final c in cases) {
      test('Sharma case ${c.a.l},${c.a.a.toStringAsFixed(2)} → '
          '${c.expected.toStringAsFixed(4)}', () {
        expect(deltaE2000(c.a, c.b), closeTo(c.expected, 0.05));
      });
    }
  });

  group('deltaE2000FromRgb', () {
    test('identical RGB triples → 0', () {
      expect(
        deltaE2000FromRgb(0xDA, 0x18, 0x84, 0xDA, 0x18, 0x84),
        closeTo(0, 1e-9),
      );
    });

    test('imperceptible perturbation (<1) for one-unit change', () {
      // Visually identical: a single sRGB step in one channel.
      final d = deltaE2000FromRgb(0xDA, 0x18, 0x84, 0xDB, 0x18, 0x84);
      expect(d, lessThan(1.0));
    });

    test('contrasting RGB (red vs blue) yields a large ΔE', () {
      final d = deltaE2000FromRgb(0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF);
      expect(d, greaterThan(40));
    });
  });
}
