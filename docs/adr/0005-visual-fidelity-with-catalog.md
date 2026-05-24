# ADR-0005 — Visual Fidelity: catalog-driven blockers

- **Status:** Accepted
- **Date:** 2026-05-23
- **Phase:** 4

## Context

The pre-redesign `VisualFidelityAnalyzer` had two STUB rules:
`ignored_widget_hint` and `gradient_degraded`. Both required a token
catalog and a token resolver to verify that the design's colors and
typography existed in the consumer's design system. Without these,
generated code could silently introduce new hex colors that no token
declared.

## Decision

Wire `PaletteResolver` and `TypeScaleResolver` into
`VisualFidelityAnalyzer`. Four new rules:

| Rule | Severity | Trigger |
|---|---|---|
| `color_not_in_catalog`        | blocker  | NDS color → resolver verdict `no_match` |
| `color_ambiguous`             | critical | NDS color → resolver verdict `ambiguous` |
| `typography_not_in_catalog`   | blocker  | NDS (size, weight) → resolver verdict `no_match` |
| `typography_ambiguous`        | critical | NDS (size, weight) → resolver verdict `ambiguous` |

The analyzer runs the new rules only when **both** a `runDirectory`
contains an NDS file AND `AnalyzerContext.tokenCatalog` is non-null.
Otherwise it degrades silently to the AST-only rules — backwards
compatible with consumers who haven't configured a catalog yet.

`AnalyzerContext` gained a `tokenCatalog` field;
`AnalyzerRunner.run({tokenCatalog})` accepts it. The CLI
(`analyze` subcommand) builds the catalog via
`buildTokenCatalog(config)` and injects it into the runner.

Per-analyzer configuration uses the new
`AnalyzersConfig.options` bag (`analyzers.options.visual_fidelity.*`):

```yaml
analyzers:
  options:
    visual_fidelity:
      match_threshold: 0.85
      no_match_threshold: 0.40
      check_colors: true
      check_typography: true
```

## Consequences

**Positive:**

- A generated screen using `#000000` when the consumer has only
  `palette.text=#1A1A1A` produces a blocker with
  `suggestedFix` naming the closest token AND the perceptual delta.
- The fix is mechanical: change the design or add the token. No
  ambiguity.
- One injection point (`tokenCatalog`) makes the analyzer testable
  without spinning up adapters.

**Negative:**

- The CLI now has to build the catalog before running analyze — adds
  one I/O step. Mitigated: catalog construction is lazy; not invoked
  unless an analyzer reads it.

## References

- `lib/src/analyzers/visual_fidelity/analyzer.dart`.
- `lib/src/contracts/analyzer.dart` — `AnalyzerContext.tokenCatalog`.
- `lib/src/contracts/project_config.dart` — `AnalyzersConfig.options`.
- `test/analyzers/visual_fidelity/catalog_checks_test.dart` — 7 tests.
