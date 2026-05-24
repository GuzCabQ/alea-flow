// Expected: 0 issues.
// Pure math — only dart:math is allowed.

import 'dart:math' as math;

double euclidean(double a, double b) => math.sqrt(a * a + b * b);
