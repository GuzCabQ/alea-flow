// ALEA — TokenResolver contract.
//
// Generic resolution port: given a query (a hex string, a (size, weight)
// pair, a Figma description) and a [DesignTokenCatalog], pick the best
// matching token and surface confidence + alternates. Phase 4 analyzers
// consume the result to emit blocker / critical / warning issues based on
// `ResolutionVerdict` and `confidence`.
//
// Design notes:
//   - The contract is intentionally generic in both the query type and the
//     token type. Concrete resolvers parameterize it: PaletteResolver
//     implements `TokenResolver<ColorQuery, ColorToken>`, TypeScaleResolver
//     implements `TokenResolver<TypographyQuery, TypographyToken>`, etc.
//   - Resolvers are stateless; any caching belongs to the catalog they
//     consume. This keeps resolvers concurrency-safe.
//   - Thresholds belong in [ResolverHints], not in the resolver constructor.
//     Each call can pick its own thresholds — e.g. blocker-grade for
//     pre-commit gates, lenient for early design review.

import 'dart:async';

import 'design_token_catalog.dart';

/// Outcome of a single resolution attempt.
enum ResolutionVerdict {
  /// Best candidate exceeds `hints.matchThreshold`.
  match,

  /// Best candidate is above `hints.noMatchThreshold` but below
  /// `hints.matchThreshold`. The next-best candidate is within
  /// `hints.ambiguousMargin` of the best.
  ambiguous,

  /// No candidate clears `hints.noMatchThreshold`.
  noMatch,
}

/// A scored candidate. [score] is in 0..1, higher = better. [rationale] is
/// a short human-readable explanation ("ΔE = 1.23", "weight differs by 100")
/// surfaced in journal events and issue messages.
class TokenCandidate<T extends DesignToken> {
  final T token;
  final double score;
  final String? rationale;

  const TokenCandidate({
    required this.token,
    required this.score,
    this.rationale,
  });
}

/// Outcome of a [TokenResolver.resolve] call.
///
/// [recommended] is the top candidate when [verdict] is `match` or
/// `ambiguous`; null when `noMatch`. [candidates] is the ranked list
/// (descending by score) truncated to `hints.maxCandidates`.
class ResolutionResult<T extends DesignToken> {
  final T? recommended;
  final List<TokenCandidate<T>> candidates;
  final ResolutionVerdict verdict;
  final double confidence;
  final List<String> warnings;

  const ResolutionResult({
    this.recommended,
    this.candidates = const [],
    required this.verdict,
    required this.confidence,
    this.warnings = const [],
  });

  /// Convenience for analyzers serializing the result into journal events
  /// and issue messages.
  Map<String, Object?> toJson() => {
    'verdict': verdict.name,
    'confidence': confidence,
    if (recommended != null) 'recommended': recommended!.qualifiedName,
    if (candidates.isNotEmpty)
      'candidates': candidates
          .map(
            (c) => {
              'token': c.token.qualifiedName,
              'score': c.score,
              if (c.rationale != null) 'rationale': c.rationale,
            },
          )
          .toList(),
    if (warnings.isNotEmpty) 'warnings': warnings,
  };
}

/// Tunable thresholds for a single resolution call.
///
/// Defaults are conservative — they assume the caller wants to flag
/// anything that is not a clear, unambiguous match.
class ResolverHints {
  /// Above this score the result is `match`.
  final double matchThreshold;

  /// Below this score the result is `noMatch`.
  final double noMatchThreshold;

  /// When the runner-up score is within this much of the top score, the
  /// result is downgraded from `match` to `ambiguous` even if the top score
  /// is above [matchThreshold].
  final double ambiguousMargin;

  /// Truncate the [ResolutionResult.candidates] list to this many entries.
  final int maxCandidates;

  /// Free-form bag of resolver-specific knobs (e.g. allowed font families).
  final Map<String, Object?> extras;

  const ResolverHints({
    this.matchThreshold = 0.85,
    this.noMatchThreshold = 0.40,
    this.ambiguousMargin = 0.05,
    this.maxCandidates = 3,
    this.extras = const {},
  });
}

/// Port: produce a [ResolutionResult] for a [TQuery] against a catalog
/// (already injected at construction time, not passed per-call so the
/// resolver can cache its own pre-computations if it wants).
abstract interface class TokenResolver<TQuery, TToken extends DesignToken> {
  /// Stable identifier ('palette', 'type_scale', ...). Used as the `source`
  /// in journal events emitted by analyzers that consume the resolver.
  String get resolverId;

  Future<ResolutionResult<TToken>> resolve(
    TQuery query, [
    ResolverHints hints = const ResolverHints(),
  ]);
}
