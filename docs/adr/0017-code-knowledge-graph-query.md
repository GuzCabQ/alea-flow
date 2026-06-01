# ADR-0017 — `aflow graph-query` (the graph's first consumer)

- **Status:** Proposed
- **Date:** 2026-05-30
- **Phase:** 13
- **Related:** [Design spec](../superpowers/specs/2026-05-30-code-knowledge-graph-query-design.md) ·
  [ADR-0014](0014-code-knowledge-graph.md) / [ADR-0015](0015-code-knowledge-graph-resolution.md) /
  [ADR-0016](0016-code-knowledge-graph-wiring.md) (the producer) · [ADR-0001](0001-architectural-invariants.md)

## Context

The code-knowledge-graph producer (`aflow graph [--resolve]`) is complete and was validated
locally on two real internal Flutter projects (freya, horus) — full resolution, zero unresolved,
thousands of edges. But it had **no consumer**: ADR-0014 explicitly flagged the risk of "a rail
with no immediate consumer." Continuing to add edge types (e.g. the call graph) without a consumer
would be gold-plating. The disciplined next step is to give the graph a first consumer that makes
it actionable and surfaces what real queries need — before investing in more producer features.

A query/impact CLI is the highest-leverage first consumer: it is **actionable at 2000+ nodes**
(where a raw force-directed visualization is an unreadable hairball), it answers the
architecture-quality questions the product cares about (blast radius, hubs, dependencies), and it
is the direct bridge to the deferred AI-context use.

## Decision

Add `aflow graph-query`, a read-only consumer of a prebuilt `graph.json`:

1. **Pure query engine** `lib/src/core/graph/code_graph_query.dart` — `impact` (reverse-dependency
   closure), `neighbors` (1-hop), `godNodes` (top-degree hubs), `resolveNodes` (name/id → nodes).
   Operates on an in-memory `CodeGraph`; no I/O; imports only the pure contract.
2. **New command `aflow graph-query`** (parent) with subcommands `impact <name|id>`,
   `neighbors <name|id>`, `god-nodes [--limit N]`. Reads `-i graph.json` (default `graph.json`) via
   `CodeGraph.fromJson`; `--format text|json`.
3. **Reads prebuilt, with a freshness warning.** Producer/consumer split: produce once
   (`aflow graph`), query many. The consumer recomputes `CodeGraphBuilder.inputsFingerprint` over
   the current tree and **warns** (does not refuse) when it differs from the graph's
   `inputs_fingerprint` — finally exercising the freshness anchor built in slice-1a. Warn (not
   refuse) is the right UX for an interactive read-only query; the user decides whether to rebuild.
4. **`impact` follows only depends-on relations** — `imports`, `references`, `extends_`,
   `implements_`, `mixesIn` (source depends on target). `contains`/`exports`/`part`/`partOf` are
   structural-internal and `wiring` (class→manifest) does not fit the depends-on direction; all are
   excluded from impact. Documented; revisitable.
5. **The producer `aflow graph`'s behavior is unchanged.** The consumer is a separate command — no
   parent-command restructure. The only producer edit is mechanical: its `_collectDartFiles`
   file-collection is extracted into a shared helper both commands call, so the consumer's
   fingerprint recompute uses the identical file set (otherwise a false "stale" warning fires).

## Consequences

### Positive
- The graph becomes usable: blast-radius, hubs, and dependency questions answerable in milliseconds
  over a prebuilt artifact. Validates the whole subsystem against real consumer queries.
- Finally uses the `inputs_fingerprint` freshness anchor (a real consumer of it).
- Pure engine is trivially unit-testable; the producer stays untouched (lower risk).
- Tested on the real freya/horus graphs generated locally.

### Negative
- Requires a prebuilt `graph.json` (no build-on-demand) — a deliberate two-step (produce once,
  query many) for a fast interactive consumer.
- `aflow graph` vs `aflow graph-query` are sibling commands rather than `graph build`/`graph query`;
  the flatter naming avoids churning the validated producer (accepted trade-off).

### Neutral
- Adds `lib/src/core/graph/code_graph_query.dart` + a command; registers one command. No new
  boundary rule. `path` queries and HTML visualization are deferred.

## Alternatives considered

### A. HTML graph visualization as the first consumer
Rejected for now: at 2000+ nodes a force-directed view is a hairball without significant
scoping/filtering UX; less actionable than queries and more work.

### B. Build the graph on demand inside the query command
Rejected for slice-1: build is ~15s on large projects — poor UX for interactive querying. Reading a
prebuilt artifact (with a staleness warning) is fast and reuses the fingerprint. Build-on-demand can
be added later.

### C. Refuse on a stale graph (instead of warn)
Rejected: for an interactive read-only query, a loud warning that still answers is friendlier than
refusing; the user decides whether to rebuild. (Refuse-or-rebuild remains the right stance for a
future automated AI-context consumer that *trusts* the graph.)

### D. Restructure `aflow graph` into `graph build` + `graph query`
Rejected: nicer namespace but refactors the just-validated producer and its tests for naming alone.
A separate `graph-query` command keeps blast radius minimal.

## References
- [Design spec](../superpowers/specs/2026-05-30-code-knowledge-graph-query-design.md)
- The producer ADRs 0014/0015/0016.
