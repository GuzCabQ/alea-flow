// ALEA — LayoutMetricResolver.
//
// Resolves a numeric layout value (8px, 16px, 5%) to the closest
// [SpacingToken]. Pure-math snapping lives in
// lib/src/matching/snap_to_steps.dart.
//
// Hints:
//   - hints.extras['tolerance'] — absolute distance (in input unit) treated
//     as a perfect match. Default 0.5 — matches the "clean %" tolerance
//     used by the legacy spacing converter.

import 'dart:async';

import '../../contracts/design_token_catalog.dart';
import '../../contracts/token_resolver.dart';

/// Query for layout-metric resolution. [unit] selects the candidate set —
/// only tokens with the same unit are considered.
class LayoutMetricQuery {
  final double value;
  final String unit;

  const LayoutMetricQuery({required this.value, this.unit = 'px'});
}

class LayoutMetricResolver
    implements TokenResolver<LayoutMetricQuery, SpacingToken> {
  final DesignTokenCatalog catalog;

  LayoutMetricResolver(this.catalog);

  @override
  String get resolverId => 'layout_metric';

  Future<List<SpacingToken>>? _tokensFuture;

  Future<List<SpacingToken>> _tokens() {
    return _tokensFuture ??= catalog.spacing();
  }

  @override
  Future<ResolutionResult<SpacingToken>> resolve(
    LayoutMetricQuery query, [
    ResolverHints hints = const ResolverHints(),
  ]) async {
    final all = await _tokens();
    final filtered = all
        .where((t) => t.unit == query.unit)
        .toList(growable: false);

    if (filtered.isEmpty) {
      return ResolutionResult<SpacingToken>(
        verdict: ResolutionVerdict.noMatch,
        confidence: 0,
        warnings: [
          if (all.isEmpty)
            'catalog returned no spacing tokens'
          else
            'no spacing tokens match unit "${query.unit}"',
        ],
      );
    }

    final tolerance = (hints.extras['tolerance'] as num?)?.toDouble() ?? 0.5;

    final scored = <TokenCandidate<SpacingToken>>[];
    for (final t in filtered) {
      final diff = (t.value - query.value).abs();
      // Linear decay over twice the tolerance: diff=0 → 1.0,
      // diff=2*tolerance → 0.0. Allows the verdict logic to fall to
      // ambiguous when a value sits right between two declared steps.
      final raw = 1.0 - (diff / (tolerance * 2));
      final score = raw.clamp(0.0, 1.0).toDouble();
      scored.add(
        TokenCandidate(
          token: t,
          score: score,
          rationale: 'Δ = ${diff.toStringAsFixed(2)}${query.unit}',
        ),
      );
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    return _verdict(scored, hints);
  }
}

ResolutionResult<T> _verdict<T extends DesignToken>(
  List<TokenCandidate<T>> scored,
  ResolverHints hints,
) {
  if (scored.isEmpty) {
    return ResolutionResult<T>(
      verdict: ResolutionVerdict.noMatch,
      confidence: 0,
    );
  }
  final top = scored.first;
  final truncated = scored.take(hints.maxCandidates).toList(growable: false);

  if (top.score < hints.noMatchThreshold) {
    return ResolutionResult<T>(
      candidates: truncated,
      verdict: ResolutionVerdict.noMatch,
      confidence: top.score,
    );
  }

  if (scored.length > 1) {
    final runnerUp = scored[1];
    if (top.score - runnerUp.score < hints.ambiguousMargin) {
      return ResolutionResult<T>(
        recommended: top.token,
        candidates: truncated,
        verdict: ResolutionVerdict.ambiguous,
        confidence: top.score,
      );
    }
  }

  final verdict = top.score >= hints.matchThreshold
      ? ResolutionVerdict.match
      : ResolutionVerdict.ambiguous;
  return ResolutionResult<T>(
    recommended: top.token,
    candidates: truncated,
    verdict: verdict,
    confidence: top.score,
  );
}
