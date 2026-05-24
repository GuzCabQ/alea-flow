// ALEA — PaletteResolver.
//
// Resolves an arbitrary color (hex or ARGB int) to the closest [ColorToken]
// of a [DesignTokenCatalog] using ΔE CIE2000 as the distance metric.
//
// Pure math lives in lib/src/matching/color_distance.dart. This file only
// orchestrates: load tokens once, precompute Lab values once, rank by
// ΔE, derive a verdict from the configured thresholds.

import 'dart:async';

import '../../contracts/design_token_catalog.dart';
import '../../contracts/token_resolver.dart';
import '../../matching/color_distance.dart';

/// A color query expressed in 32-bit ARGB.
class ColorQuery {
  final int argb;
  const ColorQuery(this.argb);

  /// Parse `#RGB`, `#RGBA`, `#RRGGBB`, `#AARRGGBB`. Returns null for any
  /// other form.
  static ColorQuery? fromHex(String hex) {
    var s = hex.trim();
    if (!s.startsWith('#')) return null;
    s = s.substring(1).toUpperCase();
    String expanded;
    switch (s.length) {
      case 3:
        expanded = 'FF${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
        break;
      case 4:
        expanded = '${s[3]}${s[3]}${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
        break;
      case 6:
        expanded = 'FF$s';
        break;
      case 8:
        expanded = s;
        break;
      default:
        return null;
    }
    final n = int.tryParse(expanded, radix: 16);
    return n == null ? null : ColorQuery(n);
  }

  int get red => (argb >> 16) & 0xFF;
  int get green => (argb >> 8) & 0xFF;
  int get blue => argb & 0xFF;
}

class PaletteResolver implements TokenResolver<ColorQuery, ColorToken> {
  final DesignTokenCatalog catalog;

  /// Maximum ΔE that still maps to a non-zero score. Above this, the
  /// candidate is considered "no match" before thresholds are applied.
  final double maxDelta;

  PaletteResolver(this.catalog, {this.maxDelta = 10});

  @override
  String get resolverId => 'palette';

  // Cache the future, not the resolved value: concurrent first-call resolves
  // share a single I/O.
  Future<List<_ColorEntry>>? _entriesFuture;

  Future<List<_ColorEntry>> _entries() {
    return _entriesFuture ??= () async {
      final tokens = await catalog.colors();
      return tokens
          .map(
            (t) =>
                _ColorEntry(token: t, lab: srgbToLab(t.red, t.green, t.blue)),
          )
          .toList(growable: false);
    }();
  }

  @override
  Future<ResolutionResult<ColorToken>> resolve(
    ColorQuery query, [
    ResolverHints hints = const ResolverHints(),
  ]) async {
    final entries = await _entries();
    if (entries.isEmpty) {
      return const ResolutionResult(
        verdict: ResolutionVerdict.noMatch,
        confidence: 0,
        warnings: ['catalog returned no colors'],
      );
    }

    final qLab = srgbToLab(query.red, query.green, query.blue);

    final scored = <TokenCandidate<ColorToken>>[];
    for (final e in entries) {
      final delta = deltaE2000(qLab, e.lab);
      final raw = 1.0 - delta / maxDelta;
      final score = raw.clamp(0.0, 1.0).toDouble();
      scored.add(
        TokenCandidate(
          token: e.token,
          score: score,
          rationale: 'ΔE = ${delta.toStringAsFixed(2)}',
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

  // Ambiguous if a runner-up is too close to the top score.
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

class _ColorEntry {
  final ColorToken token;
  final Lab lab;
  const _ColorEntry({required this.token, required this.lab});
}
