# ADR-0016 — Code-knowledge-graph wiring edges (class→registration)

- **Status:** Proposed
- **Date:** 2026-05-30
- **Phase:** 13
- **Related:** [Design spec](../superpowers/specs/2026-05-30-code-knowledge-graph-wiring-design.md) ·
  [ADR-0014](0014-code-knowledge-graph.md) (slice-1a) · [ADR-0015](0015-code-knowledge-graph-resolution.md) (slice-1b) ·
  [ADR-0007](0007-wiring-cohesion.md) (the wiring config + analyzer this reuses) ·
  [ADR-0001](0001-architectural-invariants.md) (boundaries)

## Context

The code-knowledge-graph (slice-1a/1b) captures files, classes, imports, layers, inheritance, and
type references. One structural relationship remains uncaptured: which classes are **wired** into a
project's DI containers / route tables. The consumer already declares this via
`architecture.wiring.rules` (class pattern, manifest file, registration call), and the
`wiring_cohesion` analyzer already detects registered-vs-missing classes — but it emits only
missing-registration **issues** and discards the positive class→registration relationship.

This is the last of the three sub-slices decomposed from the original "slice-1b": resolution
(done, ADR-0015), the call graph (deferred — the expensive one), and **wiring** (this ADR — the
cheap, independent, parsed-AST one).

## Decision

Persist the class→registration relationship as `wiring` graph edges:

1. **New `GraphRelation.wiring`** (json `"wiring"`). Edge: `class:<rel>#Name --wiring-->
   file:<manifest-rel>`, `confidence: extracted`. The relationship is detected by parsed AST
   (name-matching), consistent with how `wiring_cohesion` works and with slice-1a's by-name approach.
2. **New `lib/src/core/graph/code_graph_wiring.dart`** — `addWiringEdges(CodeGraph base,
   {projectRoot, config}) → CodeGraph`. For each `WiringRule`: parse the manifest, collect the
   PascalCase identifiers registered inside `registrationCall` invocations, and add a `wiring` edge
   from each matching project declaration node to the manifest file node. The registration-detection
   logic is **lifted** from `wiring_cohesion`'s `_RegistrationCollector`; the analyzer is left
   untouched (duplication accepted, like slice-1a's import canonicalizer).
3. **Default-on, no flag.** The command runs `build → addWiringEdges → (resolve if --resolve)`.
   Wiring is parsed and cheap; gating it behind a flag is unwarranted. It is a **no-op** when
   `architecture.wiring` is absent, so it does not change the graph of projects (like alea itself)
   that declare no wiring rules.
4. **`CodeGraphBuilder` and `wiring_cohesion` untouched.** The unit lives in `core/` and imports no
   `adapters/`; the contract stays pure. `schema_version` stays `1.0.0` (additive relation value).

## Consequences

### Positive
- Persists the wiring relationship `wiring_cohesion` computed-and-discarded; classes become
  navigable to their DI/route registration site ("what is wired where").
- Cheap, independent, parsed-AST; no new infrastructure; reuses the existing wiring config.
- No-op without config ⇒ zero blast radius for projects (and alea itself) that declare no wiring.
- Composes cleanly with `--resolve`; separate unit keeps the builder focused (SRP), mirroring the
  resolver.

### Negative
- The registration-detection logic is duplicated from `wiring_cohesion` (third lift after the
  import canonicalizer). A future DRY-unification of these AST helpers is worth doing once the graph
  subsystem stabilizes.

### Neutral
- Adds `lib/src/core/graph/code_graph_wiring.dart`; no new boundary rule.
- Default `aflow graph` output changes only for projects that declare wiring rules (additive edges).

## Alternatives considered

### A. Emit wiring edges from `CodeGraphBuilder`
Rejected: wiring is a cross-file, config-driven concern (read specific manifests, match
registration calls) distinct from the builder's per-file declaration/directive walk. A separate
unit keeps the builder focused, consistent with the slice-1b resolver.

### B. Gate wiring behind an opt-in flag (like `--resolve`)
Rejected: wiring is parsed and cheap and is already a no-op without config. Gating it adds CLI
surface for no benefit.

### C. Synthetic per-rule "registration" nodes
Rejected as over-engineering: an edge from the class to the manifest file conveys the relationship;
a dedicated registration node adds a node kind with no current consumer.

### D. Extract a shared registration-detection helper used by both the analyzer and the graph unit
Deferred (not rejected on merit): the DRY win is real but touches `wiring_cohesion`, breaking the
"analyzers untouched" discipline maintained across these slices. Lifting now keeps blast radius
minimal; unify later.

## References
- [Design spec](../superpowers/specs/2026-05-30-code-knowledge-graph-wiring-design.md)
- [ADR-0007](0007-wiring-cohesion.md) — the wiring config + analyzer whose detection logic this reuses.
