# ADR-0022 — Code-knowledge-graph extracted to `dart_source_graph`

- **Status:** Accepted
- **Date:** 2026-06-01
- **Phase:** post-20 (graph extraction)

## Context

ADRs 0014–0020 built the code-knowledge-graph directly inside alea-flow:
the graph builder, contract types, resolver, wiring-edge pass, query
engine, self-package resolution, and Slice-2 precision work amounted to
roughly **2,400 lines of production code** plus a corresponding test
suite. The graph is a general-purpose Dart static-analysis tool; it has
no inherent dependency on alea-flow's token catalog, analyzer registry,
or scaffolding logic. Keeping it inline made alea-flow the sole consumer
of its own graph engine and blocked any downstream project from importing
the graph types directly.

## Decision

The graph implementation was extracted into a standalone published package,
`dart_source_graph ^0.1.0`, and alea-flow now depends on it as an external
dependency.

### What moved

All graph production code and its tests now live in `dart_source_graph`.
alea-flow retains:

- `lib/src/cli/commands/graph_command.dart` — thin `aflow graph` wrapper.
- `lib/src/cli/commands/graph_query_command.dart` — thin `aflow graph-query` wrapper.
- `lib/src/cli/graph/source_graph_config_mapper.dart` — maps
  `ProjectConfig` (from `.alea.yaml`) to `SourceGraphConfig` (the
  package's config type) and delegates to `CodeGraphBuilder`,
  `CodeGraphResolver`, `addWiringEdges`, and `CodeGraphQuery`.
- One end-to-end smoke test that invokes `aflow graph` over a real target
  and asserts the output is valid JSON with `nodes`/`edges` keys.

ADRs 0014–0020 are left intact as historical record of the design
decisions; they document the evolution of the graph's data model and
query language regardless of where the code lives.

### CLI contract

The `aflow graph` and `aflow graph-query` subcommand interfaces — flags,
output schema, exit codes — are **unchanged**. Pipeline prompts that
invoke them (`/aflow-complete-config`, `/aflow-review-diff`,
`/aflow-analyze-ticket`, etc.) require no modification.

### Public API boundary

The graph data-model types (`GraphNode`, `GraphEdge`, `CodeGraph`,
`CodeGraphQuery`, …) are no longer part of alea-flow's exported public API.
Consumers that need those types import `dart_source_graph` directly.

## Consequences

**Positive:**

- alea-flow ships less code; the graph build/test cycle is a separate
  concern handled upstream.
- The graph engine is available to any Dart project, not just alea-flow
  consumers.
- The `ProjectConfig → SourceGraphConfig` mapper is the only coupling
  point; changes to the graph package's API are isolated to
  `source_graph_config_mapper.dart` and the two command files.
- Parity-verified: a baseline graph built with the inline implementation
  and a graph built after extraction from the same real consumer project
  (Freya) produce byte-identical `nodes` and `edges` — confirmed by `jq`
  diff (PARITY OK).

**Negative:**

- alea-flow's graph behavior is now gated on a published package release;
  graph bug fixes require a `dart_source_graph` release before alea-flow
  can pick them up.
- The graph data-model types are no longer accessible via an alea-flow
  import — consumers must add `dart_source_graph` to their own
  `pubspec.yaml` if they need them.

## References

- `lib/src/cli/commands/graph_command.dart`
- `lib/src/cli/commands/graph_query_command.dart`
- `lib/src/cli/graph/source_graph_config_mapper.dart`
- `pubspec.yaml` — `dart_source_graph: ^0.1.0`
- ADRs [0014](0014-code-knowledge-graph.md) through [0020](0020-graph-slice-2-precision.md) — historical inline design record.
