# ADR-0018 — Self-package import resolution + orphan external-node GC

- **Status:** Proposed
- **Date:** 2026-05-30
- **Phase:** 13
- **Related:** [Design spec](../superpowers/specs/2026-05-30-graph-self-package-resolution-design.md) ·
  [ADR-0014](0014-code-knowledge-graph.md) / [ADR-0015](0015-code-knowledge-graph-resolution.md) /
  [ADR-0016](0016-code-knowledge-graph-wiring.md) (producer) ·
  [ADR-0017](0017-code-knowledge-graph-query.md) (consumer) · [ADR-0001](0001-architectural-invariants.md)

## Context

Dogfooding the query consumer on real projects surfaced two correctness gaps that make the graph
misrepresent internal vs. external structure:

1. **Self-package imports dangle.** `import 'package:<self>/...'` produced an
   `external:package:<self>/...` node rather than connecting to the internal `file:lib/...` node.
   Negligible in library packages (relative imports), but dominant in apps: **63%** of import edges
   in freya (1477/2350) and **77%** in horus (1743/2257) were dangling self-package externals. An
   app's import graph was therefore largely disconnected.

2. **Orphan external nodes.** The builder emits `external:<Name>` nodes for by-name inheritance; the
   resolver retargets inheritance to the internal declaration and drops the by-name edge but left
   the now-edgeless external node behind. On alea_flow itself: **8 orphan external nodes, all with an
   internal twin**. This caused `impact "Analyzer"` to fail with a **false ambiguity** (internal
   class vs. orphan `external:Analyzer`).

Bad information is worse than none: both gaps make the graph lie. A `--kind internal|external` query
filter was considered as a follow-up, but gap #2 is the *cause* of the ambiguity it would have
masked — fixing the root cause is the disciplined choice.

## Decision

Two surgical changes in `core/` plus one line in the command; the `CodeGraph` contract is untouched.

1. **Builder resolves self-package URIs.** `build()` gains a `String? packageName`; in `_addUriEdge`,
   a `package:<packageName>/<rest>` URI targets the internal `GraphNodeId.file('lib/<rest>')` and
   creates no external node. This is the deterministic package-system mapping
   (`package:<name>/x` ⇄ `<root>/lib/x`), applied uniformly to import/export/part. Confidence stays
   `extracted`. It is pure/parsed, so `aflow graph` benefits even without `--resolve`. `packageName`
   null/empty preserves current behavior.
2. **Resolver GCs orphan externals.** At the end of `resolve()`, drop **external** nodes with zero
   incident edges. Internal nodes (file/class/mixin/enum) are always kept; a live external such as
   `external:StatelessWidget` retains its edge and is kept.
3. **Command** passes `config.project.packageName` into `build()`.

**`--kind` is dropped** — with orphan GC, the `external:Analyzer` twin disappears and
`resolveNodes("Analyzer")` returns a single internal node. YAGNI.

## Consequences

### Positive
- App import graphs become connected (freya ~63%→~0%, horus ~77%→~0% dangling), so
  `impact`/`neighbors` finally count the import dimension correctly.
- The false-ambiguity class of bug is removed at the source; `god-nodes`/`resolveNodes` no longer
  show dead external twins.
- Change A helps the non-resolved `aflow graph` too. No contract/schema change.

### Negative
- `build()` gains a parameter (named, optional — minimal churn). Test call sites that care about
  self-package resolution must pass it.
- Self-package imports of files outside the scan set (e.g. generated `objectbox.g.dart`) now target
  a `file:` id with no matching node — identical to the pre-existing behavior for relative imports.

### Neutral
- Barrel/re-export *symbol* resolution and cross-first-party-package resolution remain deferred.

## Alternatives considered

### A. Add a `--kind internal|external` filter to the query consumer
Rejected: it masks the orphan-node symptom instead of fixing it. Once orphans are GC'd, the
ambiguity it addressed no longer exists.

### B. Resolve self-package imports in the resolver (element model) instead of the builder
Rejected: the mapping is a deterministic string rule on the directive URI; doing it in the parsed
builder is simpler, needs no resolved AST, and lets the non-resolved graph benefit too.

### C. GC orphan externals in the builder as well
Unnecessary: in the non-resolved graph those external nodes still carry their by-name inheritance
edges, so they are not orphans. Orphans only arise after the resolver retargets — GC belongs there.

## References
- [Design spec](../superpowers/specs/2026-05-30-graph-self-package-resolution-design.md)
- Producer/consumer ADRs 0014/0015/0016/0017.
