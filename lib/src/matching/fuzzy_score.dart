// ALEA — Fuzzy string scoring.
//
// Tokenizes input strings and produces a compound similarity score combining
// token-set overlap (Jaccard asymmetric) with substring containment. Used by
// ComponentLookup (Phase 5) and any resolver that needs free-text matching.
//
// Pure math: no I/O, no state.

import 'jaccard.dart';

/// Tokenize a string for fuzzy matching.
///
/// Splits on whitespace, punctuation, and word boundaries inside camelCase
/// identifiers. Returns lower-cased, diacritic-folded tokens.
///
/// Diacritics are folded BEFORE the alpha check so accented letters
/// (Spanish "botón", "canción") count as alphabetic and remain inside the
/// same token.
List<String> tokenize(String input) {
  if (input.isEmpty) return const [];
  final out = <String>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    out.add(buffer.toString().toLowerCase());
    buffer.clear();
  }

  for (var i = 0; i < input.length; i++) {
    final raw = input.codeUnitAt(i);
    final folded = _foldDiacritic(raw);
    final isAlpha =
        (folded >= 0x41 && folded <= 0x5A) ||
        (folded >= 0x61 && folded <= 0x7A);
    final isDigit = folded >= 0x30 && folded <= 0x39;
    final isAlphaNum = isAlpha || isDigit;
    final isUpper = folded >= 0x41 && folded <= 0x5A;

    if (!isAlphaNum) {
      flush();
      continue;
    }

    // camelCase split: uppercase letter inside a non-empty buffer that ended
    // in a lowercase letter starts a new token.
    if (isUpper && buffer.isNotEmpty) {
      final last = buffer.toString().codeUnitAt(buffer.length - 1);
      final lastIsLower = last >= 0x61 && last <= 0x7A;
      if (lastIsLower) flush();
    }

    buffer.writeCharCode(folded);
  }
  flush();
  return out;
}

/// Fold diacritics across an entire string, preserving non-alpha characters.
/// Used by [fuzzyScore] for substring containment checks.
String foldDiacritics(String input) {
  final buffer = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    buffer.writeCharCode(_foldDiacritic(input.codeUnitAt(i)));
  }
  return buffer.toString();
}

/// ASCII-fold a single code point — used for matching across diacritics.
/// Returns the original code point for everything outside the small Latin
/// supplement table we care about; the [tokenize] caller then lower-cases.
int _foldDiacritic(int cp) {
  // Latin-1 supplement: map accented letters to their base.
  if (cp >= 0xC0 && cp <= 0xC6) return 0x41; // ÀÁÂÃÄÅÆ → A
  if (cp == 0xC7) return 0x43; // Ç → C
  if (cp >= 0xC8 && cp <= 0xCB) return 0x45; // ÈÉÊË → E
  if (cp >= 0xCC && cp <= 0xCF) return 0x49; // ÌÍÎÏ → I
  if (cp == 0xD1) return 0x4E; // Ñ → N
  if (cp >= 0xD2 && cp <= 0xD6) return 0x4F; // ÒÓÔÕÖ → O
  if (cp >= 0xD9 && cp <= 0xDC) return 0x55; // ÙÚÛÜ → U
  if (cp == 0xDD) return 0x59; // Ý → Y
  if (cp >= 0xE0 && cp <= 0xE6) return 0x61; // àáâãäåæ → a
  if (cp == 0xE7) return 0x63; // ç → c
  if (cp >= 0xE8 && cp <= 0xEB) return 0x65; // èéêë → e
  if (cp >= 0xEC && cp <= 0xEF) return 0x69; // ìíîï → i
  if (cp == 0xF1) return 0x6E; // ñ → n
  if (cp >= 0xF2 && cp <= 0xF6) return 0x6F; // òóôõö → o
  if (cp >= 0xF9 && cp <= 0xFC) return 0x75; // ùúûü → u
  if (cp == 0xFD || cp == 0xFF) return 0x79; // ýÿ → y
  return cp;
}

/// Compound fuzzy score in 0..1, higher = better match.
///
/// Blends:
///   - Token-set overlap (symmetric Jaccard, weight 0.6). Reaches 1.0 when
///     [query] and [candidate] tokenize to the same set.
///   - Diacritic-folded, case-insensitive substring containment (weight 0.4).
///
/// Empty inputs short-circuit to 0.0. Identical inputs reach exactly 1.0.
double fuzzyScore(String query, String candidate) {
  if (query.isEmpty || candidate.isEmpty) return 0.0;
  final qSet = tokenize(query).toSet();
  final cSet = tokenize(candidate).toSet();
  final tokenScore = jaccardSimilarity(qSet, cSet);
  final foldedQuery = foldDiacritics(query).toLowerCase();
  final foldedCand = foldDiacritics(candidate).toLowerCase();
  final substr = foldedCand.contains(foldedQuery) ? 1.0 : 0.0;
  return (0.6 * tokenScore + 0.4 * substr).clamp(0.0, 1.0);
}
