// ALEA — Color distance (CIEDE2000).
//
// Pure math: sRGB → linear RGB → CIE XYZ → CIE Lab → ΔE CIE2000.
// No I/O, no state, no side effects. Uses only `dart:math`.
//
// References:
//   - Sharma, G., Wu, W., Dalal, E. (2005). "The CIEDE2000 color-difference
//     formula: Implementation notes, supplementary test data, and
//     mathematical observations". Color Research & Application 30(1), 21–30.
//   - sRGB → Lab conversion under D65 standard illuminant.
//
// Conventions:
//   - All channel inputs are integers 0..255 (no alpha).
//   - All angle math is performed in degrees (the formula reads cleaner that
//     way); internal trig calls convert to radians via [_deg2rad].

import 'dart:math' as math;

/// A point in CIE L*a*b* color space (D65 illuminant).
class Lab {
  final double l;
  final double a;
  final double b;
  const Lab(this.l, this.a, this.b);
}

/// Convert sRGB (0..255 per channel) to CIE Lab under D65.
Lab srgbToLab(int r, int g, int b) {
  final rl = _srgbToLinear(r / 255.0);
  final gl = _srgbToLinear(g / 255.0);
  final bl = _srgbToLinear(b / 255.0);

  // Linear RGB → XYZ (sRGB matrix, D65).
  final x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375;
  final y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750;
  final z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041;

  // D65 reference white.
  const xn = 0.95047;
  const yn = 1.00000;
  const zn = 1.08883;

  final fx = _labF(x / xn);
  final fy = _labF(y / yn);
  final fz = _labF(z / zn);

  return Lab(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz));
}

/// ΔE CIE2000 between two Lab colors. Returns 0 for identical inputs and
/// values up to ~100 for extreme contrasts.
///
/// Implementation follows Sharma et al. (2005), equations 1–10.
double deltaE2000(Lab c1, Lab c2) {
  const kL = 1.0;
  const kC = 1.0;
  const kH = 1.0;

  final l1 = c1.l;
  final a1 = c1.a;
  final b1 = c1.b;
  final l2 = c2.l;
  final a2 = c2.a;
  final b2 = c2.b;

  final c1Star = math.sqrt(a1 * a1 + b1 * b1);
  final c2Star = math.sqrt(a2 * a2 + b2 * b2);
  final cMean = (c1Star + c2Star) / 2.0;

  final cMean7 = math.pow(cMean, 7).toDouble();
  final g = 0.5 * (1.0 - math.sqrt(cMean7 / (cMean7 + math.pow(25, 7))));

  final a1Prime = a1 * (1.0 + g);
  final a2Prime = a2 * (1.0 + g);

  final c1Prime = math.sqrt(a1Prime * a1Prime + b1 * b1);
  final c2Prime = math.sqrt(a2Prime * a2Prime + b2 * b2);

  final h1Prime = _atan2Deg(b1, a1Prime);
  final h2Prime = _atan2Deg(b2, a2Prime);

  final dlPrime = l2 - l1;
  final dcPrime = c2Prime - c1Prime;

  double dhPrime;
  if (c1Prime * c2Prime == 0) {
    dhPrime = 0;
  } else {
    var diff = h2Prime - h1Prime;
    if (diff > 180) {
      diff -= 360;
    } else if (diff < -180) {
      diff += 360;
    }
    dhPrime = diff;
  }
  final dHPrime =
      2.0 * math.sqrt(c1Prime * c2Prime) * math.sin(_deg2rad(dhPrime / 2.0));

  final lMeanPrime = (l1 + l2) / 2.0;
  final cMeanPrime = (c1Prime + c2Prime) / 2.0;

  double hMeanPrime;
  if (c1Prime * c2Prime == 0) {
    hMeanPrime = h1Prime + h2Prime;
  } else if ((h1Prime - h2Prime).abs() <= 180) {
    hMeanPrime = (h1Prime + h2Prime) / 2.0;
  } else if ((h1Prime + h2Prime) < 360) {
    hMeanPrime = (h1Prime + h2Prime + 360) / 2.0;
  } else {
    hMeanPrime = (h1Prime + h2Prime - 360) / 2.0;
  }

  final t =
      1.0 -
      0.17 * math.cos(_deg2rad(hMeanPrime - 30)) +
      0.24 * math.cos(_deg2rad(2 * hMeanPrime)) +
      0.32 * math.cos(_deg2rad(3 * hMeanPrime + 6)) -
      0.20 * math.cos(_deg2rad(4 * hMeanPrime - 63));

  final dTheta =
      30.0 * math.exp(-math.pow((hMeanPrime - 275) / 25, 2).toDouble());

  final cMeanPrime7 = math.pow(cMeanPrime, 7).toDouble();
  final rC = 2.0 * math.sqrt(cMeanPrime7 / (cMeanPrime7 + math.pow(25, 7)));

  final lMinus50Sq = (lMeanPrime - 50) * (lMeanPrime - 50);
  final sL = 1.0 + (0.015 * lMinus50Sq) / math.sqrt(20 + lMinus50Sq);
  final sC = 1.0 + 0.045 * cMeanPrime;
  final sH = 1.0 + 0.015 * cMeanPrime * t;

  final rT = -math.sin(_deg2rad(2 * dTheta)) * rC;

  final lTerm = dlPrime / (kL * sL);
  final cTerm = dcPrime / (kC * sC);
  final hTerm = dHPrime / (kH * sH);

  return math.sqrt(
    lTerm * lTerm + cTerm * cTerm + hTerm * hTerm + rT * cTerm * hTerm,
  );
}

/// Convenience: ΔE CIE2000 between two sRGB triples (0..255 per channel).
double deltaE2000FromRgb(int r1, int g1, int b1, int r2, int g2, int b2) =>
    deltaE2000(srgbToLab(r1, g1, b1), srgbToLab(r2, g2, b2));

// ── Helpers ──────────────────────────────────────────────────────────────────

double _srgbToLinear(double c) =>
    c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _labF(double t) {
  const delta = 6.0 / 29.0;
  return t > delta * delta * delta
      ? math.pow(t, 1.0 / 3.0).toDouble()
      : t / (3.0 * delta * delta) + 4.0 / 29.0;
}

double _deg2rad(double deg) => deg * math.pi / 180.0;

double _atan2Deg(double y, double x) {
  final rad = math.atan2(y, x);
  final deg = rad * 180.0 / math.pi;
  return deg < 0 ? deg + 360 : deg;
}
