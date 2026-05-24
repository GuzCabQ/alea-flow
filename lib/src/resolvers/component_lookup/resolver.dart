// ALEA — ComponentLookup.
//
// Resolves a free-form widget description ("botón guardar") against a
// `WidgetInventory`. Each entry is scored by [fuzzyScore] against the
// query description; entries that don't satisfy the hard filters declared
// in the query (tokensUsed must be a subset of the entry's tokensUsed) are
// dropped before scoring.
//
// Returned candidates are wrapped in [NamedToken] (family='widget', value=
// the entry's toJson()) so callers can switch on [DesignToken] without
// special-casing widget lookups.

import 'dart:async';

import '../../contracts/design_token_catalog.dart';
import '../../contracts/token_resolver.dart';
import '../../contracts/widget_inventory.dart';
import '../../matching/fuzzy_score.dart';

/// Free-form query for the component lookup.
///
/// [description] is the raw Figma layer name (or any short label). It is
/// matched against every entry's `className` via [fuzzyScore].
///
/// [tokensUsed] acts as a HARD filter: the resolver discards any entry
/// whose `tokensUsed` does not contain every element of the query — useful
/// when a design context already resolved the color/typography tokens for
/// the layer and you only want widgets that use those same tokens.
class ComponentQuery {
  final String description;
  final Set<String> tokensUsed;

  const ComponentQuery({required this.description, this.tokensUsed = const {}});
}

class ComponentLookup implements TokenResolver<ComponentQuery, NamedToken> {
  /// Inventory to consult. Null means the caller did not wire one in (the
  /// resolver then surfaces a `noMatch` with an explanatory warning so
  /// downstream code can degrade gracefully).
  final WidgetInventory? inventory;

  ComponentLookup({this.inventory});

  @override
  String get resolverId => 'component_lookup';

  Future<List<WidgetEntry>>? _entriesFuture;

  Future<List<WidgetEntry>> _entries() {
    final inv = inventory;
    if (inv == null) return Future.value(const []);
    return _entriesFuture ??= inv.entries();
  }

  @override
  Future<ResolutionResult<NamedToken>> resolve(
    ComponentQuery query, [
    ResolverHints hints = const ResolverHints(),
  ]) async {
    if (inventory == null) {
      return const ResolutionResult<NamedToken>(
        verdict: ResolutionVerdict.noMatch,
        confidence: 0,
        warnings: [
          'ComponentLookup has no WidgetInventory injected — no candidates '
              'can be considered. Pass `inventory:` at construction time.',
        ],
      );
    }
    final entries = await _entries();
    if (entries.isEmpty) {
      return const ResolutionResult<NamedToken>(
        verdict: ResolutionVerdict.noMatch,
        confidence: 0,
        warnings: ['WidgetInventory is empty'],
      );
    }

    final candidates = <TokenCandidate<NamedToken>>[];
    for (final entry in entries) {
      // Hard filter: every query.tokensUsed must be present on the entry.
      if (query.tokensUsed.isNotEmpty) {
        final entryTokens = entry.tokensUsed.toSet();
        if (!query.tokensUsed.every(entryTokens.contains)) continue;
      }
      final score = fuzzyScore(query.description, entry.className);
      candidates.add(
        TokenCandidate(
          token: NamedToken(
            qualifiedName: entry.className,
            family: 'widget',
            value: entry.toJson(),
            meta: entry.meta,
          ),
          score: score,
          rationale:
              'fuzzy=${score.toStringAsFixed(2)} className="${entry.className}"',
        ),
      );
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));

    return _verdict(candidates, hints);
  }
}

ResolutionResult<NamedToken> _verdict(
  List<TokenCandidate<NamedToken>> scored,
  ResolverHints hints,
) {
  if (scored.isEmpty) {
    return const ResolutionResult<NamedToken>(
      verdict: ResolutionVerdict.noMatch,
      confidence: 0,
    );
  }
  final top = scored.first;
  final truncated = scored.take(hints.maxCandidates).toList(growable: false);

  if (top.score < hints.noMatchThreshold) {
    return ResolutionResult<NamedToken>(
      candidates: truncated,
      verdict: ResolutionVerdict.noMatch,
      confidence: top.score,
    );
  }
  if (scored.length > 1) {
    final runnerUp = scored[1];
    if (top.score - runnerUp.score < hints.ambiguousMargin) {
      return ResolutionResult<NamedToken>(
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
  return ResolutionResult<NamedToken>(
    recommended: top.token,
    candidates: truncated,
    verdict: verdict,
    confidence: top.score,
  );
}
