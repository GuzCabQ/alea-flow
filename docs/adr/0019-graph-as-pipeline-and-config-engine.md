# ADR-0019 — The code graph as the pipeline's verification + config engine

- **Status:** Accepted
- **Date:** 2026-05-31
- **Supersedes role of:** ADR-0017 (which named `graph-query` "the graph's first consumer" — a human CLI; the pipeline and `/complete-config` are the real consumers).

## Context

The code-knowledge-graph (ADR-0013…0018) was built but no `core/command` consumed it: `graph.json` was produced and queried only by hand. The most valuable artifact for an AI (reverse dependency closure, hubs, neighbors, structure) was disconnected from the pipeline it was built for.

## Decision

The graph becomes the engine of verified facts for two consumers, via deterministic CLI primitives (the prompts orchestrate, they do not re-derive):

1. **Pipeline (S1):** `aflow graph --ensure-fresh` (idempotent, fingerprint-guarded build) feeds `impact` (blast radius in `/analyze-ticket`, untouched-consumer regressions in `/review-feature`), `neighbors` (reuse in `/design-feature`), and `god-nodes` (hub warning in `/run-gates`). Added to `core/README.md`'s Verification-primitives table.
2. **Config (S2):** `aflow graph-query structure` grounds `.alea.yaml` via `/complete-config` — a graph-grounded realization of Proposal 0001 Item A/B that avoids the proposed ~2500-LOC `lib/src/diagnostics/` module, because the graph already computes layer structure, dependency direction, cycles and flutter-in-domain.

## Consequences

- `.pipeline/graph.json` is a project-scoped, freshness-guarded artifact rebuilt only when the tree changes.
- `graph.json` is never read whole into AI context — `structure`/`impact`/`neighbors`/`god-nodes` return bounded summaries.
- No new adapters; ADR-0001 boundaries hold (primitives live in `cli/` + `core/graph/`).
