# ADR-0014 — Native code-knowledge-graph (`aflow graph`, slice-1a structural)

- **Status:** Proposed
- **Date:** 2026-05-29
- **Phase:** 13
- **Related:** [Design spec](../superpowers/specs/2026-05-29-code-knowledge-graph-design.md) ·
  [ADR-0006](0006-widget-inventory-and-symbol-digest.md) (flat inventory/digest) ·
  [ADR-0009](0009-context-packet.md) (flat context) ·
  [ADR-0001](0001-architectural-invariants.md) (boundaries)

## Context

alea's persisted context surfaces are **flat**: `SymbolDigest`, `ContextPacket`, and
`WidgetInventory` carry no relationships. Meanwhile alea **already computes relationship data
and throws it away**: `layer_integrity` canonicalizes the entire import graph but emits only
forbidden-import issues; `wiring_cohesion` computes class→registration mappings but emits only
missing-registration issues; `package_boundary` builds boundary edges and discards them.

Investigating graphify (github.com/safishamsi/graphify) + Obsidian as a way to add more value
("Use 2": the package using graph knowledge to improve its own results) surfaced the real
opportunity: not to *depend* on graphify (its Dart extraction is regex-only and weaker than
alea's native `package:analyzer` AST), but to build a **native Dart code-knowledge-graph** as
a first-class, reusable artifact — borrowing graphify's transferable design ideas (confidence
tiers, node-link shape, separation of extraction from semantic enrichment) and deliberately
improving on the rest.

The near-term consumer (the pipeline's AI context) is **deferred** — there is no real pipeline
consumer yet. So this is scoped as a rail: build the artifact and validate its schema by
dogfooding on alea itself, before any consumer integration.

## Decision

Add a native code-knowledge-graph built from Dart AST, emitted as a deterministic,
schema-versioned `graph.json`, **phased**:

- **Slice-1a (now):** structural graph from **parsed** AST — files, classes/mixins/enums,
  Dart directives (`imports`/`exports`/`part`/`partOf`), `contains`, and inheritance recorded
  **by type name**. All edges `extracted`. No type resolution, no analyzer changes.
- **Slice-1b (later):** resolved AST adds wiring (class→registration), call graph, type
  references, and precise internal inheritance resolution — introducing `inferred`/`ambiguous`
  confidence.

Slice-1a implementation:

1. **Pure contract `lib/src/contracts/code_graph.dart`** — `GraphNode` / `GraphEdge` /
   `CodeGraph` + enums + pure id builders + `toJson`/`fromJson` with deterministic sorting.
   Imports only `dart:core`/`dart:convert` (`contracts_purity`).
2. **Dedicated builder `lib/src/core/graph/code_graph_builder.dart`** — its own
   `AnalysisContextCollection` pass over a coherent model. Core may import
   `package:analyzer`/`package:path`; it imports no adapters (`core_orchestration_boundaries`).
3. **New command `aflow graph [-o <file>]`** — emits `graph.json` to stdout or a file,
   mirroring `aflow inventory`'s output convention (not the gate-report `alea-reports/` dir).
   `graph.json` is a published project artifact (Law of Demeter).
4. **Analyzers untouched.** The builder carries its own import canonicalization (logic lifted
   from `layer_integrity`); DRY-unifying it is a deliberate later cleanup.

Key schema choices: readable stable IDs (`file:`, `class:…#Name`, `external:`); `layer` as a
node attribute; `confidence` present from day 1; `schema_version` versioned as part of the
contracts stability surface; sorted/deterministic output for diffability.

**Freshness is a first-class invariant.** A stale graph the AI trusts is worse than no graph,
so every `graph.json` carries an `inputs_fingerprint` (SHA-256 over sorted
`(path, content-hash)` pairs). slice-1a is fresh-by-construction (rebuilt each invocation, no
cache); consumers MUST verify the fingerprint against the current tree and rebuild-or-refuse on
mismatch — never serve stale data. Rebuild is cheap (AST-only, local), so the posture is
rebuild-over-trust. The highest-risk window is `implement-*` (the AI writes files mid-run); the
future consumption slice must rebuild/incrementally-update after each generative step.

## Consequences

### Positive
- Turns computed-then-discarded relationship data into a first-class, reusable, native artifact
  — no graphify dependency, AST-precise on Dart where graphify is regex-blind.
- Deterministic + schema-versioned ⇒ committable and git-diffable; schema designed to absorb
  slice-1b without a breaking change.
- ADR-0001 boundaries hold; analyzers untouched; dogfoodable on alea itself.

### Negative
- A rail with **no immediate consumer** (the AI-context integration is deferred) — risk of
  building infrastructure ahead of demand. Mitigated by keeping slice-1a cheap and
  schema-stable, and by dogfooding to validate.
- Import canonicalization is temporarily duplicated between `layer_integrity` and the builder.

### Neutral
- Adds `lib/src/core/graph/` and a `graph` command. No new boundary rule needed.
- Visualization (a graph view in the HTML report) is a deferred subproduct, not part of this ADR.

## Alternatives considered

### A. Side-channel edges out of the analyzers (`GraphSink` on `AnalyzerContext`)
Rejected: insufficient for the chosen scope (no analyzer computes class/inheritance/contains
today), couples graph-emission into issue-detection (mixed responsibility), and yields the
graph only as a side effect of running a gate.

### B. Library-only API, no CLI command
Rejected for slice-1a: without an entry point the schema cannot be dogfooded on alea before
being committed. A thin command is cheap and enables validation.

### C. Depend on graphify (Python) directly
Rejected: violates the Dart-first toolchain, its Dart extraction is regex-only (no calls, no
types, false positives), and it adds an external process + global mutable graph store. Used as
**design inspiration only**.

### D. Build the full rich graph (calls/refs) in one slice
Rejected: precise calls/type-refs need resolved AST (expensive) and a real confidence model;
phasing delivers a useful `graph.json` sooner and de-risks the resolution work.

## References

- [Design spec](../superpowers/specs/2026-05-29-code-knowledge-graph-design.md)
- graphify (github.com/safishamsi/graphify) — reviewed as design inspiration; not a dependency.
