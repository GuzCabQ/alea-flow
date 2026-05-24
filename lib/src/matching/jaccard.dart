// ALEA — Jaccard similarity (symmetric and asymmetric variants).
//
// Pure math: set-based overlap scoring. No I/O. Uses only `dart:core`.

/// Symmetric Jaccard similarity: |A ∩ B| / |A ∪ B|.
///
/// Returns 1.0 for identical (and identically-empty) sets, 0.0 for disjoint.
double jaccardSimilarity<T>(Set<T> a, Set<T> b) {
  if (a.isEmpty && b.isEmpty) return 1.0;
  final union = a.union(b);
  if (union.isEmpty) return 0.0;
  return a.intersection(b).length / union.length;
}

/// Asymmetric Jaccard: |Q ∩ C| / (|Q| + weight * |C|).
///
/// Treats [query] as the "small" side and [candidate] as the "large" side.
/// A small [weight] (default 0.3) softens the penalty for the catalog being
/// larger than the query — useful when matching short descriptive tokens
/// against a long classname or constructor signature.
///
/// Returns 1.0 only when [query] ⊆ [candidate] AND [candidate] is empty
/// (which can't happen if the intersection is non-empty); otherwise less
/// than 1.0.
double jaccardAsymmetric<T>(
  Set<T> query,
  Set<T> candidate, {
  double weight = 0.3,
}) {
  if (query.isEmpty && candidate.isEmpty) return 1.0;
  final intersection = query.intersection(candidate).length;
  final denominator = query.length + weight * candidate.length;
  if (denominator == 0) return 0.0;
  return intersection / denominator;
}
