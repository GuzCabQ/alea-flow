// ALEA — TypeScaleResolver.
//
// Resolves a typography query (fontSize + fontWeight + optional family /
// decoration) to the closest [TypographyToken]. Weight and family act as
// hard filters; size acts as a soft proximity score.
//
// Hints:
//   - hints.extras['size_tolerance_px'] — maximum |sizeDiff| treated as a
//     full-score match. Default 1.0 (matches the ±1px convention used by
//     Figma-to-token resolvers in the legacy tooling).

import 'dart:async';

import '../../contracts/design_token_catalog.dart';
import '../../contracts/token_resolver.dart';

/// Query for typography resolution. [fontFamily] and [decoration] are
/// optional hard filters — when null, they don't constrain the candidate
/// set.
class TypographyQuery {
  final double fontSize;
  final int fontWeight;
  final String? fontFamily;
  final String? decoration;

  const TypographyQuery({
    required this.fontSize,
    required this.fontWeight,
    this.fontFamily,
    this.decoration,
  });
}

class TypeScaleResolver
    implements TokenResolver<TypographyQuery, TypographyToken> {
  final DesignTokenCatalog catalog;

  TypeScaleResolver(this.catalog);

  @override
  String get resolverId => 'type_scale';

  Future<List<TypographyToken>>? _tokensFuture;

  Future<List<TypographyToken>> _tokens() {
    return _tokensFuture ??= catalog.typography();
  }

  @override
  Future<ResolutionResult<TypographyToken>> resolve(
    TypographyQuery query, [
    ResolverHints hints = const ResolverHints(),
  ]) async {
    final all = await _tokens();
    if (all.isEmpty) {
      return const ResolutionResult(
        verdict: ResolutionVerdict.noMatch,
        confidence: 0,
        warnings: ['catalog returned no typography tokens'],
      );
    }

    // Hard filters: weight equality is required; family/decoration only
    // when the query declared one AND the token declared one too. If the
    // token does not declare a family, we don't reject it on that axis.
    final filtered = all
        .where((t) {
          if (t.fontWeight != query.fontWeight) return false;
          if (query.fontFamily != null &&
              t.fontFamily != null &&
              t.fontFamily != query.fontFamily) {
            return false;
          }
          if (query.decoration != null &&
              t.decoration != null &&
              t.decoration != query.decoration) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    if (filtered.isEmpty) {
      return ResolutionResult<TypographyToken>(
        verdict: ResolutionVerdict.noMatch,
        confidence: 0,
        warnings: [
          'No typography tokens match weight=${query.fontWeight}'
              '${query.fontFamily != null ? ', family=${query.fontFamily}' : ''}',
        ],
      );
    }

    final sizeTolerance =
        (hints.extras['size_tolerance_px'] as num?)?.toDouble() ?? 1.0;

    final scored = <TokenCandidate<TypographyToken>>[];
    for (final t in filtered) {
      final diff = (t.fontSize - query.fontSize).abs();
      // Linear decay: diff=0 → 1.0; diff=sizeTolerance → 0.0.
      final raw = 1.0 - (diff / (sizeTolerance * 2));
      final score = raw.clamp(0.0, 1.0).toDouble();
      scored.add(
        TokenCandidate(
          token: t,
          score: score,
          rationale:
              'Δsize = ${diff.toStringAsFixed(2)}px '
              '(tolerance ±${sizeTolerance.toStringAsFixed(1)})',
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
