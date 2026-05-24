// ALEA — Numeric snapping utilities.
//
// Pure math: snap a real number to the nearest entry in a discrete set
// (LayoutMetricResolver) or to the nearest multiple of a step. No I/O.

/// Result of [snapToSteps] — the closest declared step and how far the
/// input was from it (in the same unit as the input).
class SnapResult {
  final double snapped;
  final double distance;
  const SnapResult(this.snapped, this.distance);
}

/// Snap [value] to the closest entry of [steps]. [steps] must not be empty.
/// Ties are broken in favour of the smaller value.
SnapResult snapToSteps(double value, List<double> steps) {
  if (steps.isEmpty) {
    throw ArgumentError.value(steps, 'steps', 'must not be empty');
  }
  double best = steps.first;
  double bestDistance = (value - best).abs();
  for (var i = 1; i < steps.length; i++) {
    final step = steps[i];
    final d = (value - step).abs();
    if (d < bestDistance || (d == bestDistance && step < best)) {
      best = step;
      bestDistance = d;
    }
  }
  return SnapResult(best, bestDistance);
}

/// Snap [value] to the nearest multiple of [step], offset by [base]. Useful
/// when a design system uses an even grid (e.g. multiples of 4 px starting
/// at 0). [step] must be strictly positive.
double snapToMultiple(double value, double step, {double base = 0}) {
  if (step <= 0) {
    throw ArgumentError.value(step, 'step', 'must be strictly positive');
  }
  return base + ((value - base) / step).roundToDouble() * step;
}

/// Return true when [value] is within [tolerance] of any entry in [steps].
bool isCleanAgainst(
  double value,
  List<double> steps, {
  double tolerance = 0.5,
}) {
  for (final step in steps) {
    if ((value - step).abs() <= tolerance) return true;
  }
  return false;
}
