# ADR-0015 — Code-knowledge-graph resolution (`aflow graph --resolve`, slice-1b)

- **Status:** Proposed
- **Date:** 2026-05-30
- **Phase:** 13
- **Related:** [Design spec](../superpowers/specs/2026-05-30-code-knowledge-graph-resolution-design.md) ·
  [ADR-0014](0014-code-knowledge-graph.md) (slice-1a structural graph) ·
  [ADR-0001](0001-architectural-invariants.md) (boundaries)

## Context

slice-1a (ADR-0014) builds a structural code-knowledge-graph from PARSED AST. Its one inherent
limitation: inheritance is recorded **by name** (`extends Base` → an `external:Base` node) because
parsed AST cannot tell which file `Base` is declared in. It also carries no type-dependency edges.
Both gaps need RESOLVED AST (the analyzer element model), which is the next increment of value: it
turns by-name inheritance into real internal edges (enabling "what extends my domain Entity?"
traversal) and adds the type dependencies a class actually has.

The originally-scoped "slice-1b" bundled four capabilities (precise inheritance, type references,
wiring, call graph). It was decomposed during design. This ADR covers the **resolution foundation:
precise inheritance + type references**. Wiring (parsed-AST, independent) and the call graph
(resolved-AST, expensive, ambiguity-prone) are separate later slices.

Resolved AST (`getResolvedUnit`) is markedly slower than `parseFile` and requires the target
project to have `dart pub get` applied (and the Flutter SDK for `package:flutter` types). So the
cost must be explicit and opt-in, and resolution must degrade gracefully when it cannot run.

## Decision

Add an opt-in resolved pass, implemented as a **separate resolver unit**:

1. **`--resolve` flag on `aflow graph`, default OFF.** Without it, behavior is byte-for-byte
   slice-1a (`resolved: false`). With it, a resolved pass enriches the graph (`resolved: true`).
2. **New `lib/src/core/graph/code_graph_resolver.dart`** — `CodeGraphResolver.resolve(CodeGraph
   base, {projectRoot, filePaths, config}) → Future<CodeGraph>`. It opens one
   `AnalysisContextCollection`, resolves each file, and via the element model
   (`InterfaceElement.supertype`/`.interfaces`/`.mixins`, member signature types):
   - **retargets** `extends`/`implements`/`with` edges to the internal node `class:<rel>#Name`
     when the supertype is declared inside the scanned project (else keeps `external:`);
   - **adds `references` edges** (new `GraphRelation` value) from a declaration to the types in its
     member signatures (fields, parameters, returns), generic arguments unwrapped, excluding `dart:`
     types and generic type parameters, deduplicated per `(declaration, target)`.
   `CodeGraphBuilder` (parsed) is **untouched**; the resolver consumes its output.
3. **Graceful degradation.** A file that does not resolve (no `pub get`, errors, throws) keeps its
   slice-1a by-name edges and is counted in `unresolved_files`. Resolution only ever upgrades; it
   never loses the structural floor and never crashes.
4. **Confidence stays `extracted`.** Resolution is precise; degraded edges are also `extracted`.
   `inferred`/`ambiguous` remain reserved for the call-graph slice.
5. **Transparency metadata.** `resolved: bool` on the document; `resolved_files`/`unresolved_files`
   in the summary, so a consumer (and the user) can see how much resolution actually happened.

`package:analyzer` is a library dependency, not an adapter (single native resolution
implementation, nothing swappable), so the resolver belongs in `core/` and imports no
`adapters/` — consistent with `core_orchestration_boundaries`. The contract stays pure.

## Consequences

### Positive
- Inheritance becomes traversable to real internal classes; classes gain explicit type-dependency
  edges — the relationship value the feature exists for.
- Opt-in keeps the default `aflow graph` fast and dependency-free; the expensive path is explicit.
- Graceful degradation means `--resolve` is always safe to run: worst case it returns the slice-1a
  graph with a low `resolved_files` count.
- Resolution isolated in its own unit (SRP); the parsed builder stays simple; the resolver is
  independently testable with intra-project relative-import fixtures.

### Negative
- `--resolve` is substantially slower and requires a pub-resolved target (+ Flutter SDK for
  framework types). Documented; mitigated by opt-in + degradation + the `resolved_files` signal.
- The resolver test harness must produce analyzable units (relative-import temp fixtures) — more
  setup than the parsed builder's tests.

### Neutral
- `references` is a new relation value and `resolved`/`resolved_files` are new fields; both are
  backward-compatible additions, so `schema_version` stays `1.0.0` (no external consumer yet).
- Adds `lib/src/core/graph/code_graph_resolver.dart`; no new boundary rule.

## Alternatives considered

### A. Extend `CodeGraphBuilder` with an async `buildResolved()`
Rejected: mixes the parsed and resolved concerns in one growing file (already ~390 lines) and
couples the simple structural pass to the heavy element-model logic.

### B. Single async `build({bool resolve})`
Rejected: makes `build()` async, breaking slice-1a's synchronous callers and tests.

### C. Resolution as a swappable adapter
Rejected: there is one native way to resolve Dart types (`package:analyzer`); nothing is swappable
or external-system-shaped. An adapter would be an unused extension point (YAGNI) and contradicts
the slice's intent (native resolution).

### D. Make `--resolve` the default / always-on
Rejected: every invocation would pay the cost and require pub-get/SDK; the default must stay fast
and not silently change slice-1a's output.

## References
- [Design spec](../superpowers/specs/2026-05-30-code-knowledge-graph-resolution-design.md)
- [ADR-0014](0014-code-knowledge-graph.md) — slice-1a structural graph this builds on.
