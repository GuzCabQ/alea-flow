// ALEA — PII redactor.
//
// Centralizes the regex catalog used to scrub Mexican-context PII from any
// string before it lands in a durable artifact (journal entries, gate
// reports, run metrics).
//
// The redactor is intentionally conservative: it replaces matches with a
// fixed token (`[REDACTED:<label>]`) so downstream consumers can audit how
// many redactions happened without seeing the original value.
//
// Patterns covered:
//   - CURP   — 18 chars, [A-Z]{4}[0-9]{6}[HM][A-Z]{5}[A-Z0-9][0-9]
//   - RFC    — 12 or 13 chars, [A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}
//   - CLABE  — 18 consecutive digits
//   - Card  — 13–19 consecutive digits (after the CLABE rule so 18-digit
//             CLABE wins for ambiguous strings)
//   - Phone — MX form `+52`, `+521`, `52`, `521` followed by 10 digits, or
//             a bare 10-digit sequence.
//   - Email — RFC-light: word chars / dots / dashes around an `@` with TLD.
//
// The redactor only sees what is passed to it; it does not introspect the
// surrounding payload, so callers should pass each string value
// individually (see `redactPayload` for the recursive convenience).

/// Replace every PII pattern in [text] with a redaction token. Returns the
/// scrubbed string and a count map (`{ "curp": 2, "email": 1 }`) of what
/// was redacted.
class RedactionResult {
  final String text;
  final Map<String, int> counts;
  const RedactionResult(this.text, this.counts);
}

RedactionResult redactString(String text) {
  var current = text;
  final counts = <String, int>{};

  for (final entry in _patterns.entries) {
    final label = entry.key;
    final pattern = entry.value;
    final matches = pattern.allMatches(current).length;
    if (matches == 0) continue;
    counts[label] = matches;
    current = current.replaceAll(pattern, '[REDACTED:$label]');
  }

  return RedactionResult(current, counts);
}

/// Recursively redact every string leaf in [payload]. Returns the redacted
/// payload (a new map; the input is not mutated) and the aggregated counts.
({Map<String, Object?> payload, Map<String, int> counts}) redactPayload(
  Map<String, Object?> payload,
) {
  final aggregated = <String, int>{};
  Object? walk(Object? value) {
    if (value is String) {
      final r = redactString(value);
      r.counts.forEach((k, v) => aggregated[k] = (aggregated[k] ?? 0) + v);
      return r.text;
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): walk(entry.value),
      };
    }
    if (value is List) {
      return value.map(walk).toList(growable: false);
    }
    return value;
  }

  final scrubbed = walk(payload) as Map<String, Object?>;
  return (payload: scrubbed, counts: aggregated);
}

// ── Patterns ─────────────────────────────────────────────────────────────────
//
// Ordered: longer/more-specific patterns first so they win the replacement
// race against shorter ones (e.g. CLABE before generic card).

final Map<String, RegExp> _patterns = {
  'curp': RegExp(
    r'\b[A-Z][AEIOUX][A-Z]{2}\d{6}[HM][A-Z]{5}[A-Z0-9]\d\b',
    caseSensitive: false,
  ),
  'clabe': RegExp(r'\b\d{18}\b'),
  'rfc': RegExp(
    r'\b[A-Z&Ñ]{3,4}\d{6}[A-Z0-9]{2}[A-Z0-9]\b',
    caseSensitive: false,
  ),
  'card': RegExp(r'\b\d{13,19}\b'),
  'phone': RegExp(r'(?:\+?52(?:1)?[\s\-]?)?\b\d{10}\b'),
  'email': RegExp(r'\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b'),
};
