# ADR-0020 — Code-knowledge-graph slice-2: opt-out coverage, roles, methods + calls

- **Status:** Accepted
- **Date:** 2026-05-31
- **Related:** [ADR-0014](0014-code-knowledge-graph.md) (slice-1a structural) ·
  [ADR-0019](0019-graph-as-pipeline-and-config-engine.md) (graph as pipeline + config engine) ·
  Investigation: `docs/superpowers/research/2026-05-31-state-mgmt-semantics-catalog.md`

## Context

ADR-0019 made the graph the engine of verified facts for the pipeline (`impact`/`neighbors`/
`god-nodes`) and config (`structure` → `/complete-config`). An empirical investigation — running
`aflow graph` over the real team apps **Freya** (Riverpod) and **Horus** (GetX), plus the framework
sources — proved three gaps that made the fact-engine **confidently wrong** rather than merely coarse:

1. **Coverage was opt-in by layer path.** `collectDartFiles` only collected files under declared
   `architecture.layers[*].paths`. Horus is feature-first (`lib/src/feature/…`) but declares a
   layer-first config, so **47 of 57 `GetxController`s (82%) were invisible** — `impact` would report
   "nothing impacted" for a ticket touching them.
2. **No semantic roles.** A `Notifier`/`GetxController`/`ConsumerWidget` was just `class_`; the
   pipeline could not reason about state-mgmt roles or generate idiomatic code.
3. **No method-level nodes or call graph.** `ref.watch`/`Get.find` inside method bodies were invisible,
   so widget→provider / widget→controller dependencies (the state flow) could not be derived.

## Decision

Four additive, independently-committed work-streams (slice-2), each grounded in the investigation:

- **A — Opt-out coverage.** `collectDartFiles` now collects every `.dart` under `lib/`, minus
  `graph.exclude` globs (defaults: `**/*.g.dart`, `**/*.freezed.dart`; user globs merge onto defaults).
  Layer paths only *classify* (`_layerOf` is now glob-aware, so feature-first trees are describable).
  Files outside every layer are **surfaced, never dropped**, via `graph-query unlayered` (a bounded,
  directory-clustered count) — the signal `/complete-config` uses to propose declaring or excluding them.
- **B — Role tag.** `GraphNode.role` (nullable, persisted like `layer`) is derived from the
  declaration's supertype against a built-in map (`Notifier → riverpod.notifier`,
  `GetxController → getx.controller`, `StatelessWidget → flutter.widget`, …), extensible via
  `graph.roles`. Derived in the structural pass — no `--resolve` required. Also detects Riverpod
  **codegen** roles from the `@riverpod`/`@Riverpod` annotation (class → `riverpod.notifier`,
  top-level function → `riverpod.provider`) — necessary because the codegen supertype `_$X` lives in
  an excluded `.g.dart`, so the annotation is the only role signal. (Added for the public pub.dev
  audience, where codegen is common, not inferred from the internal sample.)
- **C — Method / function nodes.** New `GraphNodeKind.method`/`function` (+ `GraphNodeId.member`)
  with `contains` edges. Mixin/enum members and constructors are out of scope (later slice).
- **D — `calls` edges + state-flow.** Every method invocation in a member body becomes a `calls` edge
  to a by-name external node, marked **`confidence: ambiguous`** (by-name resolution is imprecise, so
  the consuming AI must never treat these as verified). `graph-query state-flow` filters the noisy raw
  calls to a state-API subset (`watch`/`read`/`find`/`put`/…) per role-tagged node — the AI-consumable
  state-flow summary.

## Consequences

- **Coverage is opt-out:** a blind spot can only exist by an explicit `graph.exclude` entry, never by
  omission. Validated: Horus `extends GetxController` rose 8 → 55; node count 980 → 2398.
- **Graph scale grows** with method nodes + calls (Freya: ~2k → ~7.9k nodes, ~18.6k edges, `graph.json`
  ~6.4 MB). This is acceptable because `graph.json` is **never read whole into AI context** (ADR-0019);
  `unlayered`/`state-flow`/`impact`/`neighbors`/`god-nodes` return bounded summaries. Recorded here
  rather than silently capped.
- **Raw `calls` are noisy by design** (e.g. `copyWith`, `Text`, `Column` dominate); value is delivered
  through the `state-flow` filter, not raw traversal. `calls` is deliberately excluded from
  `kDependsOnRelations`, so `impact` is not polluted by ambiguous by-name edges.
- **Deferred:** `@riverpod` `annotates` edges (the team uses 0 codegen), a separate feature/module
  classification axis, resolved (`--resolve`) calls, and mixin/enum member nodes.
- No new external dependency (a minimal in-repo `glob_match.dart` instead of `package:glob`); ADR-0001
  boundaries hold (contract stays `dart:core`-pure; logic in `core/graph/` + `cli/`).
