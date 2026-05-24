# `figma/` — Design Source Adapter

Implements [`DesignSourceAdapter`](../../../lib/src/contracts/design_source_adapter.dart) for Figma designs accessed via the Figma MCP server.

## When this adapter is selected

`/design-feature` walks `analysis.json::attachments[]` and asks each enabled adapter `supports(ref, config)`. This adapter says yes when:

- `attachment.description` (case-insensitive) is `figma`, OR
- `attachment.uri` matches `https://www\.figma\.com/(file|design|proto)/[A-Za-z0-9]+`.

AND `.alea.yaml::design_source.adapters.figma.enabled` is `true`. The circuit breaker in `pipeline-feedback` may flip this to `false` when the hallucination rate exceeds the configured threshold; in that case `/design-feature` records `spec.design_source.status: disabled` and proceeds without NDS.

## Output

Per the contract, returns a `DesignExtractionResult` containing:

| Field | Content |
|---|---|
| `nds` | NDS YAML matching [`contracts/schemas/nds.schema.yaml`](../../../contracts/schemas/nds.schema.yaml) — extracted from Figma via `get_design_context`. |
| `widgetMap` | Decisions per NDS element from [`../_common/widget-audit.md`](../_common/widget-audit.md). |
| `colorMap` | Theme token mapping per NDS color from [`../_common/theme-map.md`](../_common/theme-map.md). |
| `runSubdirectory` | `figma` (relative to `.pipeline/runs/<ticket_id>/`). |

All three artifacts are persisted to `.pipeline/runs/<ticket_id>/figma/`:

```
figma/
├── nds.yaml                  ← from adapter.md Path A extraction
├── widgets_index.csv         ← input to widget-audit; cached
├── widget_map.yaml           ← from _common/widget-audit.md
├── theme_tokens.csv          ← input to theme-map; cached
└── color_map.yaml            ← from _common/theme-map.md
```

## Dependencies

- A Figma MCP server registered in the consumer's Claude Code config. The adapter expects the MCP tool surface to include `get_design_context` (or a configured equivalent). The exact MCP name is `.alea.yaml::design_source.adapters.figma.mcp_server` — defaults to `figma`.
- The consumer's Figma file must be reachable from the MCP server (auth handled by Figma MCP itself; this adapter does not).

## Source of truth

The official **source of truth for every color, size, gradient, and radius** is the React+Tailwind code returned by `get_design_context`. The accompanying screenshot is reference only — never extract numeric values from the screenshot. This rule exists to prevent the most common Figma extraction hallucination: estimating colors by eye when Tailwind classes already encode them.

## Conformance to NDS

See [`adapter.md`](adapter.md) for the full mapping table and extraction rules. Key invariants the Figma adapter MUST satisfy regardless of the design's complexity:

- Buttons never emit `children: []` — always emit `label` and `icon` (each may be empty string / null).
- Gradients never collapse to solid — every stop is preserved in `background.value`.
- `text_align` is emitted only when non-left.
- Images always emit `asset_type` (image / svg / gif / lottie) and `box_fit`.
- Lists with state-variant icons emit `icon_done`, `icon_active`, `icon_pending`.
- `widget_hint` is only set when ≥ 3 visual signals match a known compound pattern.

## Failure modes

| Condition | Behavior |
|---|---|
| Figma MCP server not registered or unauthenticated | Throw `DesignExtractionException(adapter: "figma", reason: "Figma MCP unavailable")`. `/design-feature` records `spec.design_source.status: disabled` and continues without NDS. |
| `get_design_context` returns an empty or malformed response | Throw with `reason: "<get_design_context returned <shape>; expected React+Tailwind output>"`. |
| Tailwind class encountered that has no mapping in the table | Log a warning, leave the corresponding NDS field null. Visual-fidelity analyzer will catch downstream issues. |
| Figma file uses prototype connections to a node not in the extracted tree | Capture the connection in `actions[*].target` with the target node's id; code-gen treats unresolvable targets as `() => {}` placeholders. |

## What this adapter does NOT do

- Does NOT call Figma's REST API directly — only via the MCP server.
- Does NOT modify the Figma file (no annotations, comments, or property changes).
- Does NOT decide what state-management style to use. NDS is style-agnostic; code-gen adapters apply their own conventions.
- Does NOT scan the consumer's codebase — that's the widget-audit and theme-map sub-phases.
- Does NOT enforce the FidelityScore. That's `visual-fidelity` analyzer + `fidelity` gate.
