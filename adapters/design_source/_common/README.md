# `design_source/_common/` — Shared logic across design-source adapters

Every design-source adapter under [`../`](../) has its own extraction logic (Figma is different from Image is different from Markup). But three sub-tasks repeat verbatim across all of them and live here:

| Sub-task | Document |
|---|---|
| Score the consumer's widget catalog against each NDS element and decide USE_AS_IS / ADAPT / CREATE_NEW | [`widget-audit.md`](widget-audit.md) |
| Map each NDS color value to the nearest theme token in the consumer project | [`theme-map.md`](theme-map.md) |
| Reference data: scoring weights, thresholds, layout decision tree | [`widget-scoring-matrix.md`](widget-scoring-matrix.md) |

## Why these live here, not in each adapter

- Same input/output regardless of source. Widget audit takes an NDS element + the project's widget catalog and emits a decision; it doesn't care whether the NDS came from Figma or a screenshot.
- One place to fix bugs and update heuristics.
- Future adapters (Sketch, Penpot, Adobe XD) reuse these without copy-paste.

## How adapters invoke this

The figma/image/markup adapter's `adapter.md` finishes its source-specific extraction by emitting the raw NDS, then explicitly delegates the rest of the pipeline:

```
Step N — Audit widgets:
   Follow ALL instructions in ../../_common/widget-audit.md, passing:
     - nds: the NDS document just extracted
     - config: ProjectConfig
     - run_dir: .pipeline/runs/<ticket_id>/<adapter_name>/

Step N+1 — Map theme tokens:
   Follow ALL instructions in ../../_common/theme-map.md, passing:
     - nds: same NDS document
     - config: ProjectConfig
     - run_dir: same as above
```

`widget-audit.md` writes `<run_dir>/widget_map.yaml` and `theme-map.md` writes `<run_dir>/color_map.yaml`. The adapter's `DesignExtractionResult` references these.

## Helper scripts

Dart helpers live at [`scripts/`](scripts/) (TBD in step 9). They will be:

- `color_distance.dart` — RGB Δ between two hex colors; used by `theme-map.md`.
- `extract_theme_tokens.dart` — scan consumer Dart source for `Color(0x...)` constants; produces `theme_tokens.csv`.
- `generate_widget_index.dart` — scan consumer Dart source for widget classes; produces `widgets_index.csv`.

Until those Dart helpers exist, the markdown prompts contain the algorithm inline (color distance is a few lines of math; theme/widget extraction is grep-like).
