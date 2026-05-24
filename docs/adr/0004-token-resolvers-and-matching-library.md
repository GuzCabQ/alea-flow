# ADR-0004 — Token Resolvers + Pure Matching Library

- **Status:** Accepted
- **Date:** 2026-05-23
- **Phase:** 3

## Context

Resolving "the Figma color is `#0066CC`; which catalog token does that
correspond to?" requires perceptual color math, fuzzy string scoring,
and numeric quantization. Two design decisions:

1. **Where does the math live?** The pre-redesign tooling mixed
   CIEDE2000 computation with file I/O and CLI plumbing in the same
   binary. Reusing the math from a test or from another tool meant
   importing the whole binary.
2. **How do resolvers find the catalog?** They consume the
   `DesignTokenCatalog` contract — but resolvers themselves are not
   adapters (they have no I/O of their own). Where do they live in the
   package boundary structure?

## Decision

### Pure-math library

`lib/src/matching/` — pure Dart, only `dart:math` and `dart:core`. No
I/O, no analyzer, no state. Four files:

- `color_distance.dart` — sRGB → Lab → ΔE CIE2000 (Sharma 2005).
- `jaccard.dart` — symmetric + asymmetric set similarity.
- `fuzzy_score.dart` — tokenization + diacritic folding + scoring.
- `snap_to_steps.dart` — quantize a real number to declared steps.

A public entry point `lib/matching.dart` re-exports the four. Anyone
can `import 'package:alea/matching.dart';` in a vanilla Dart project
without dragging `dart:io`.

The `matching_purity` boundary rule applies to both `lib/src/matching/`
AND `lib/matching.dart` — a rogue export that re-exports an I/O
module would fail CI. To enforce that, `PackageBoundaryAnalyzer`
inspects both `ImportDirective` and `ExportDirective` (Phase 3.0).

### Resolvers as services (not adapters)

`PaletteResolver`, `TypeScaleResolver`, `LayoutMetricResolver`,
`ComponentLookup` live under `lib/src/resolvers/` — NOT under
`lib/src/adapters/`. Reasoning: a resolver is a generic algorithm over
a `DesignTokenCatalog` (a port), not an implementation of an external
system. Moving them under `adapters/` would have triggered the
`analyzers_isolation` boundary rule (analyzers cannot import adapters),
which would block Phase 4 (`VisualFidelityAnalyzer` consuming the
resolvers).

Each resolver implements `TokenResolver<TQuery, TToken>` from
`lib/src/contracts/token_resolver.dart`. Resolvers are stateless;
caching of catalog calls happens via a per-resolver Future memoization.

## Consequences

**Positive:**

- The matching library is portable — works in Flutter Web, AOT, server,
  CI containers.
- Resolvers and analyzers share the same algorithmic primitives.
- Verdict semantics (match / ambiguous / no_match) live in one
  contract (`ResolutionResult`); every resolver yields the same shape.
- Adding a resolver = new file under `lib/src/resolvers/<name>/`. No
  other change.

**Negative:**

- The verdict-computation logic is duplicated across the three
  resolvers (each has its own `_verdict()` function). Worth it: keeps
  each resolver self-contained and editable in isolation.

## References

- `lib/src/matching/` + `lib/matching.dart` — pure library.
- `lib/src/contracts/token_resolver.dart` — port.
- `lib/src/resolvers/{palette,type_scale,layout_metric,component_lookup}/` — services.
- `test/matching/` (46 tests including 7 Sharma reference values).
- `test/resolvers/` (50 tests + 1 perf smoke covering 1000 concurrent
  resolves in <2s).
