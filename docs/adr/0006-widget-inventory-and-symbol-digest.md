# ADR-0006 — Widget Inventory + Symbol Digest

- **Status:** Accepted
- **Date:** 2026-05-23
- **Phase:** 5

## Context

Two recurring inefficiencies in LLM-driven workflows:

1. Re-generating a widget that already exists somewhere in the
   consumer's codebase — wasting tokens and creating duplication.
2. Asking the LLM to read a 400-line widget file to understand its
   public API — when the imports, comments, and method bodies are
   irrelevant for that question.

## Decision

### `WidgetInventory` contract + `WidgetInventoryBuilder`

A `WidgetEntry` records: class name, project-relative file path,
category (derived from PascalCase tokens — `ButtonSave*Component` →
`button`, `*Input` → `input`), tokens used (via AST visitor), primary
constructor signature, md5 hash.

`WidgetInventoryBuilder` walks the configured scan paths
(`analyzers.options.widget_inventory.scan_paths` or, when absent,
every `architecture.layers.*.paths` entry), detects widget-like
classes by suffix match OR base-class match (`StatelessWidget`,
`ConsumerWidget`, `GetView`, …), and emits an `InMemoryWidgetInventory`.

`WidgetInventoryAnalyzer` runs the builder and persists the inventory
as `.pipeline/runs/<id>/widget_inventory.json`. It is registered in
the standard registry but emits zero issues — its job is the artifact.

### `SymbolDigest`

Pure extractor that produces a sparse view of a Dart file's public
surface: class declarations (with extends + implements), constructors,
methods, getters/setters, fields, top-level functions and consts.
Private members and private classes are skipped.

Format optimizes for LLM consumption: one symbol per line, no bodies,
no imports, no comments. Measured ≥70% character reduction on realistic
widget files (verified by a property-style test).

### `ComponentLookup` wired

The Phase 3 stub `ComponentLookup` accepts an optional
`WidgetInventory` and scores each entry's class name via
`fuzzyScore(query.description, entry.className)`. `query.tokensUsed`
acts as a hard filter (an entry whose `tokensUsed` is missing any
queried token is dropped before scoring).

## Consequences

**Positive:**

- The inventory is a once-per-run artifact; downstream LLM calls can
  reference component names without re-scanning.
- `SymbolDigest` lets a code-review pipeline send "what is in this
  file" to an LLM at a fraction of the cost.
- ComponentLookup is end-to-end working: query "save button" →
  `ButtonSaveComponent` ranked first when present in the inventory.

**Negative:**

- The inventory's category heuristic (rightmost-specific-token wins)
  is opinionated. Projects with very different naming conventions can
  override `widgetSuffixes` / `widgetBases` via the analyzer options.
- md5 fingerprint depends on file content byte-for-byte. Whitespace
  changes invalidate the entry — acceptable because the LLM prompts
  benefit from fresh hashes.

## References

- `lib/src/contracts/widget_inventory.dart`.
- `lib/src/inventory/widget_inventory_builder.dart`.
- `lib/src/inventory/symbol_digest.dart`.
- `lib/src/analyzers/widget_inventory/analyzer.dart`.
- `lib/src/resolvers/component_lookup/resolver.dart`.
- 38 tests across the inventory module.
