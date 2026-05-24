# Figma Adapter — Extraction Prompt

Invoked by `/design-feature` after the figma adapter is selected for an attachment in `analysis.json::attachments[]`. The prompt extracts NDS from Figma via the MCP server, then delegates widget audit and theme mapping to `_common/`.

## Inputs

- `attachment_uri` — Figma URL from `attachments[*].uri` (matches `figma.com/(file|design|proto)/...`).
- `config` — loaded `ProjectConfig`. Specifically: `config.design_source.adapters.figma.mcp_server` (the registered MCP name), `config.theme.path`, `config.theme.brand_colors`, `config.architecture.layers.presentation.paths`.
- `run_dir` — `.pipeline/runs/<ticket_id>/figma/`. Created if absent.

## Steps

### Step 0 — Mandatory: `get_design_context` BEFORE any NDS write

Parse `nodeId` and `fileKey` from the URL:

- `figma.com/design/<fileKey>/<name>?node-id=X-Y` → `fileKey = <fileKey>`, `nodeId = "X:Y"` (replace `-` with `:`).
- `figma.com/design/<fileKey>/branch/<branchKey>/...` → use `branchKey` as `fileKey`.

Call the Figma MCP tool:

```
<mcp_server>.get_design_context(
  nodeId           = <parsed>,
  fileKey          = <parsed>,
  clientLanguages  = "dart",
  clientFrameworks = "flutter"
)
```

The MCP tool name prefix comes from `config.design_source.adapters.figma.mcp_server` (default `figma`).

The response includes React+Tailwind code AND a screenshot. **The React+Tailwind code is the source of truth for all numeric values.** The screenshot is reference-only for visual hierarchy — NEVER extract colors, sizes, or gradients from it.

### Step 1 — Tailwind → NDS mapping

Walk the React tree returned by `get_design_context`. For each node, translate its Tailwind classes using this table:

| Tailwind class | NDS field |
|---|---|
| `bg-[#RRGGBB]` | `background.type: solid, value: "#RRGGBB"` |
| `bg-[rgba(R,G,B,A)]` | `background.type: solid, value: "#RRGGBB"` (derived), `opacity: A` |
| `bg-gradient-to-b from-[#X] to-[#Y]` | `background.type: gradient, value: "#X,#Y", direction: 180` |
| `bg-gradient-to-r from-[#X] to-[#Y]` | `background.type: gradient, value: "#X,#Y", direction: 90` |
| `bg-gradient-to-br from-[#X] to-[#Y]` | `background.type: gradient, value: "#X,#Y", direction: 135` |
| `bg-gradient-to-bl from-[#X] to-[#Y]` | `background.type: gradient, value: "#X,#Y", direction: 225` |
| `bg-gradient-to-tr from-[#X] to-[#Y]` | `background.type: gradient, value: "#X,#Y", direction: 45` |
| `bg-gradient-to-tl from-[#X] to-[#Y]` | `background.type: gradient, value: "#X,#Y", direction: 315` |
| `rounded-[Npx]` | `border.radius: N` |
| `rounded-tl-[N]` | `border.radius_tl: N` (also `tr` / `bl` / `br`) |
| `border-[Npx] border-[#RRGGBB]` | `border.width: N, border.color: "#RRGGBB"` |
| `w-[Npx]` | `width: "fixed:N"` |
| `w-full` / `size-full` | `width: "fill"` |
| `w-fit` | `width: "hug"` |
| `h-[Npx]` | `height: "fixed:N"` |
| `text-[#RRGGBB]` | `style.color: "#RRGGBB"` |
| `text-[Npx]` / `text-[Nrem]` | `style.size: N` (rem × 16 = px) |
| `font-bold` | `style.weight: bold` |
| `font-semibold` | `style.weight: w600` |
| `font-normal` | `style.weight: normal` |
| `text-center` | `style.text_align: center` |
| `text-right` | `style.text_align: right` |
| `leading-[N]` (unitless) | `style.line_height: N` |
| `tracking-[Npx]` | `style.letter_spacing: N` |
| `flex flex-col` | `layout: column` |
| `flex` (without `flex-col`) | `layout: row` |
| `overflow-y-auto` / `overflow-scroll` | `scroll: true` |
| `cursor-pointer` on a text-containing element | `type: button, interactive: true` |
| Absolutely-positioned thin div with `bg-[#X]` on the left edge of a banner | left border: `border.width: <thin div width>, border.color: "#X"` |

#### Rule for embedded images in Figma

If a node is an `<img>` that fills the entire parent (e.g. a screenshot pasted as background), IGNORE it for color extraction. Use the parent `div`'s `bg-[...]` as the real background color.

### Step 2 — Walk the React tree

Use `data-node-id` attributes to follow hierarchy. Map element types:

| React shape | NDS `type` + `layout` |
|---|---|
| `div` with `flex flex-col` | `container, layout: column` |
| `div` with `flex` (no `flex-col`) | `container, layout: row` |
| `div` with `relative` containing absolutely-positioned children | `container, layout: stack` |
| `p` / inline text | `text` |
| Standalone `img` | `image` |
| `a` OR `div` with `cursor-pointer` + text/icon content | `button` |
| Repeated same-shape siblings | `list` (collapse to ONE element with `content: dynamic`) |
| Node containing both an `img` and a `p` at the same level | `icon_text_compound` |

For each emitted NDS element:

- `id`: snake_case, unique, descriptive (e.g. `header_card`, `cta_button`, `status_step_2`).
- `parent_id`: the parent container's id.

### Step 3 — Extract `cornerRadius` and `actions`

- All corners equal → `border.radius: <N>`.
- Any corner differs → `border.radius_tl / tr / bl / br` independently.
- Prototype connections on the node → append to `actions[]` with `trigger: tap` and `target: <destination node id or route name>`.

### Mandatory extraction rules (non-negotiable)

Violating any of these produces incomplete NDS that the visual-fidelity analyzer will flag, and that code-gen cannot recover from.

#### TEXT nodes

- Always extract `text_align` when non-left.
- Extract `line_height` when Figma reports anything other than `AUTO`.
- Extract `letter_spacing` when non-zero.

#### BUTTON nodes

- NEVER emit `children: []`. Always extract:
  - `label`: the visible text string inside the button (use `""` only if truly no text).
  - `icon`: asset path if an icon image is present inside the button, else `null`.
  - `icon_position`: `leading` or `trailing` when `icon` is non-null.
- If a button has no text AND no icon → STOP and escalate to Question Gate.

#### IMAGE nodes

- Always set `asset_type`:
  - `.json` extension or Lottie animation → `lottie`
  - `.svg` → `svg`
  - `.gif` → `gif`
  - `.png` / `.jpg` / `.webp` / bitmap → `image`
- Always set `box_fit`:
  - Icon / illustration / logo → `contain`
  - Full-bleed or background image → `cover`
  - Unclear → `contain` (the documented default)

#### LIST nodes with state-variant icons

If list items show different icons per state (done / active / pending), extract all three:

- `icon_done`, `icon_active`, `icon_pending` (each may be the same path — dimming is the code-gen adapter's concern).

#### ICON_TEXT_COMPOUND nodes

- Use `type: icon_text_compound` when a Figma node contains both an image asset and a text label at the same level and they form one semantic unit (badge, step label, status chip).
- Do NOT classify as `text`. Do NOT use emoji as a substitute for an image asset.

#### GRADIENT fills

- When a Figma node has a gradient fill (linear or radial): ALWAYS emit `background.type: gradient` and `background.value` with ALL color stops as `"#hex1,#hex2,..."`.
- NEVER reduce a gradient fill to `background.type: solid` by picking the dominant stop.
- Extract the gradient angle → `background.direction` (degrees). When Figma reports a vector handle, convert with `angle = atan2(dy, dx) * 180 / π`, normalize to `0–360`.
- If a node has both a gradient fill and a solid overlay → capture the gradient, ignore the solid overlay.

#### Compound widget recognition — `widget_hint`

Scan each parent element's visual structure against this recognition table. When a match is found AND ≥ 3 signals are present, set `widget_hint`. Continue decomposing children normally so the audit has the atoms as fallback.

| Visual pattern | `widget_hint` value |
|---|---|
| Row layout + colored left border (≥ 4dp) + icon asset + title text + subtitle text | `InformationBanner` |
| Card/container with diagonal purple→magenta gradient (top-left → bottom-right) + rounded corners ≥ 8dp | `PurpleGradientCard` |
| Card with bank/institution name + numeric account field + copy-icon button | `BankReferenceCard` |
| Progress bar pattern + percentage label + title above | check widget index; set if a project widget matches |

Rules:

- Only set when confidence is HIGH (≥ 3 of the pattern's signals present).
- When in doubt, leave `widget_hint: null`. A missed hint degrades gracefully (normal scoring kicks in). A wrong hint forces a bad match.
- The hint value is a class name (no path), and MUST match a widget in the consumer's index. If the project has no such widget, leave null.

### What this prompt MUST NOT do

- ❌ Infer colors from the screenshot. If `bg-[#f6e9e9]` is in the React+Tailwind code, use `#F6E9E9`. Do NOT estimate "looks light pink".
- ❌ Treat an `<img>` filling its parent as the background source. It's a screenshot embedded over the real background; read the parent `div`'s `bg-[...]` instead.
- ❌ Apply project-specific conventions without evidence in Figma. Don't add `iconBackground: orangeHexagon` because the reference consumer usually has one — only add what the Figma actually shows.
- ❌ Emit emoji as substitutes for icons when `source: figma`. If the icon's path is unknown, emit `// TODO: asset unknown` (in the run-dir's NDS comments) and a null `asset_path`.

### Step 4 — Persist NDS

Write the assembled NDS to `<run_dir>/nds.yaml` with `document.source.adapter: figma`, `document.source.uri: <attachment_uri>`, `document.source.extracted_at: <ISO 8601 now>`, `document.source.contract_version: <from nds.schema.yaml>`.

Validate against [`contracts/schemas/nds.schema.yaml`](../../../contracts/schemas/nds.schema.yaml) before writing. On validation failure, log the offending element id and field path and throw `DesignExtractionException` — do NOT persist a malformed NDS.

### Step 5 — Delegate to `_common/widget-audit.md`

Follow ALL instructions in [`../_common/widget-audit.md`](../_common/widget-audit.md), passing the just-written NDS, `config`, and `run_dir`. This writes `<run_dir>/widget_map.yaml`.

### Step 6 — Delegate to `_common/theme-map.md`

Follow ALL instructions in [`../_common/theme-map.md`](../_common/theme-map.md), passing the same NDS, `config`, and `run_dir`. This writes `<run_dir>/color_map.yaml`.

### Step 7 — Return the DesignExtractionResult

Return a `DesignExtractionResult` referencing the three artifacts just written:

```
{
  nds: <parsed contents of run_dir/nds.yaml>,
  widgetMap: <parsed contents of run_dir/widget_map.yaml>,
  colorMap: <parsed contents of run_dir/color_map.yaml>,
  runSubdirectory: "figma",
}
```

`/design-feature` reads `spec.design_source.{adapter: "figma", nds_ref: "figma/nds.yaml", attachment_uri: <the URL>}` from this and proceeds.

## Determinism

The same Figma file at the same version, with the same `get_design_context` response, MUST produce the same NDS bytewise. This lets the visual-fidelity gate use golden-file comparison to detect regressions.
