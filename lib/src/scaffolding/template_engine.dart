// ALEA — Template engine.
//
// Mustache-like rendering of single-string templates. Substitutes
// `{{variable}}` placeholders with values from a `Map<String, Object?>`,
// preserving non-placeholder text byte-for-byte.
//
// Design constraints (per the architectural invariants of Phase 7):
//   - The engine MUST NOT build Dart source code by string concatenation.
//     Templates are WHOLE strings; the engine performs token substitution
//     on the whole string at once. Adapters cannot smuggle code through
//     conditional `+` operations.
//   - The engine is pure: no I/O, no clock, deterministic output for a
//     given (template, variables) pair.
//   - Missing variables raise [TemplateRenderException] — silent fallback
//     would let adapters emit `{{accidental_typo}}` strings into the
//     generated source.
//
// Supported syntax:
//   - `{{name}}`               — required substitution.
//   - `{{name|fallback}}`      — substitution with a literal fallback when
//                                `name` is absent or null.
//   - `{{!comment}}`           — comment, deleted from output.
//
// NOT supported (intentional — keeps the engine boringly safe):
//   - Sections / loops (`{{#each ...}}` / `{{/each}}`)
//   - Partials
//   - Lambdas / pipes
//   - HTML escaping
//
// If an adapter needs a loop, it builds the repeated string from the
// templates IT controls and passes it in as a variable; the engine never
// concatenates on its own.

class TemplateEngine {
  static final RegExp _placeholder = RegExp(r'\{\{([^{}]+)\}\}');

  /// Render [template] with [vars]. Throws [TemplateRenderException] when a
  /// required placeholder has no binding.
  String render(String template, Map<String, Object?> vars) {
    return template.replaceAllMapped(_placeholder, (match) {
      final raw = match.group(1)!.trim();
      if (raw.startsWith('!')) return '';
      final pipeIdx = raw.indexOf('|');
      final name = pipeIdx >= 0 ? raw.substring(0, pipeIdx).trim() : raw;
      final fallback = pipeIdx >= 0 ? raw.substring(pipeIdx + 1) : null;
      if (!vars.containsKey(name) || vars[name] == null) {
        if (fallback != null) return fallback;
        throw TemplateRenderException(
          'missing required variable "$name"',
          placeholder: match.group(0)!,
        );
      }
      return vars[name].toString();
    });
  }

  /// Return the set of distinct placeholder names referenced by [template].
  /// Useful for adapter tests that want to verify they're providing every
  /// expected variable.
  Set<String> placeholdersOf(String template) {
    final names = <String>{};
    for (final match in _placeholder.allMatches(template)) {
      final raw = match.group(1)!.trim();
      if (raw.startsWith('!')) continue;
      final pipeIdx = raw.indexOf('|');
      final name = pipeIdx >= 0 ? raw.substring(0, pipeIdx).trim() : raw;
      names.add(name);
    }
    return names;
  }
}

class TemplateRenderException implements Exception {
  final String message;
  final String? placeholder;
  const TemplateRenderException(this.message, {this.placeholder});
  @override
  String toString() =>
      'TemplateRenderException(message=$message'
      '${placeholder != null ? ', placeholder=$placeholder' : ''})';
}
