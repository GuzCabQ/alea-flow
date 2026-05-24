# `image/` — Design Source Adapter (Stub)

Stub for an adapter that extracts NDS from a screenshot (`.png`, `.jpg`, `.webp`). Not implemented in v1.

## When this would be selected

`/design-feature` walks `analysis.json::attachments[]` and asks each enabled adapter `supports(ref, config)`. This adapter would match attachments whose URI ends in `.png`, `.jpg`, `.jpeg`, or `.webp` AND whose host is not a known design-tool host.

Currently `.alea.yaml::design_source.adapters.image.enabled` defaults to `false`. Implement this adapter when the first consumer requests it.

## When to implement

A consumer that doesn't use Figma but has screenshot-based hand-offs (PM dropping a screenshot in the ticket, designer in a freeform tool with no MCP, etc.).

## Implementation outline (when ready)

The adapter would follow the same three-phase pattern as [`../figma/adapter.md`](../figma/adapter.md):

1. **Source-specific extraction (Path B):**
   - Identify layout axis (vertical = column, horizontal = row, overlapping = stack).
   - For each distinct region, estimate `background.type` (solid if single fill, gradient if multi-stop, none if transparent).
   - Estimate `background.value` from the region's dominant color.
   - Estimate `border.radius` category (0 / 8 / 12-16 / ≥24).
   - Identify text nodes; capture `static_value` if legible, set `content: dynamic` if placeholder-looking.
   - Identify interactive regions (buttons, list rows, cards with chevrons) → `interactive: true`.
   - Estimate scrollability when content is taller than visible region.
2. **Delegate widget audit:** [`../_common/widget-audit.md`](../_common/widget-audit.md).
3. **Delegate theme map:** [`../_common/theme-map.md`](../_common/theme-map.md).

## Why this is not in v1

The extraction step requires multimodal vision (LLM analyzing the image), which is inherently less deterministic than reading Tailwind classes from Figma's MCP. Estimating hex values from pixels has ≥10% error rate in practice. Acceptable for stub flows, not acceptable as a default for production code generation.

When implemented, the adapter should:

- Document its known error rate in this README.
- Output NDS with `confidence` annotations per element (`high` / `medium` / `low`) so visual-fidelity can weight its checks accordingly.
- Honor the circuit breaker (same as figma) when `pipeline-feedback` accumulates evidence of hallucinations.
