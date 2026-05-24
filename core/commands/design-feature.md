# `/design-feature` — Design Feature Spec

Reads the feature analysis, optionally invokes a design-source adapter for NDS extraction, generates a per-layer technical spec, and writes `.pipeline/runs/<ticket_id>/spec.json` validated against [`contracts/schemas/spec.schema.yaml`](../../contracts/schemas/spec.schema.yaml).

## Usage

```
/design-feature DEV-XXXX
```

## Steps

### 1. Load config and analysis

1. Read `.alea.yaml` from the project root; validate against [`project-config.schema.yaml`](../../contracts/schemas/project-config.schema.yaml). Stop on validation error.
2. Read `.pipeline/runs/<ticket_id>/analysis.json`. Verify `type == "feature"`. If missing or wrong type:
   ```
   Error: feature analysis not found for <ticket_id>.
   Run /analyze-ticket <ticket_id> first (must be a feature ticket).
   ```
   Stop.

### 2. Explore the consumer codebase

Run in parallel:

- **Widget catalog** — scan every `config.architecture.layers.<X>.paths` where `<X>` is the consumer's UI layer (typically `presentation`). Cache to `<run_dir>/widgets_index.csv`.
- **Theme tokens** — read `config.theme.path`; extract `Color(0x...)` constants and named text styles. Use `config.theme.brand_colors` from config as preferred matches. Cache to `<run_dir>/theme_tokens.csv`.
- **State management style** — confirm by reading `config.state_management.style`. Surface in the spec as documentation only; code-gen adapter will enforce.
- **Routing pattern** — read `config.routing.router_path` to confirm the package + structure (`go_router`, `auto_route`, etc.).

### 3. Walk `attachments[]` and select a design-source adapter

For each entry in `analysis.json::attachments[]`:

1. Resolve which adapter (if any) supports it:
   - Match `attachment.description` (case-insensitive) against any adapter folder name under `adapters/design_source/<name>/`. First match wins.
   - If no description match: apply URL/extension fallback (host `figma.com` → `figma`; extension `.html`/`.jsx` → `markup`; image extensions → `image`; etc. — see [`analysis.schema.yaml::AttachmentRef.description`](../../contracts/schemas/analysis.schema.yaml)).
2. Check `config.design_source.adapters.<adapter>.enabled`. When `false`, skip this attachment.
3. Stop on the first attachment that resolves to an enabled adapter.

**Possible outcomes:**

- **Found:** invoke that adapter's `adapter.md` (e.g. [`adapters/design_source/figma/adapter.md`](../../adapters/design_source/figma/adapter.md)). The adapter writes `<run_dir>/<adapter>/nds.yaml`, `widget_map.yaml`, `color_map.yaml`. Record in spec:
  ```yaml
  design_source:
    status: extracted
    adapter: figma
    nds_ref: figma/nds.yaml
    attachment_uri: <the URL>
  ```
- **Disabled match:** record what would have run:
  ```yaml
  design_source:
    status: disabled
    adapter: figma
    nds_ref: null
    attachment_uri: <the URL>
  ```
  Continue without NDS — spec falls back to code-only conventions.
- **No match found:** record:
  ```yaml
  design_source:
    status: none
    adapter: null
    nds_ref: null
    attachment_uri: null
  ```

**Important:** this command MUST NEVER mention specific adapter names (`figma`, `sketch`, ...) by hardcoded conditional. Adapter selection is by string lookup against the attachment hint + URL fallback. Adding a new design source requires zero changes here.

### 4. Generate the per-layer spec

For each layer in `config.architecture.layers` (typically `domain`, `infrastructure`, `presentation`), generate the corresponding spec section per [`spec.schema.yaml`](../../contracts/schemas/spec.schema.yaml).

The output shape is rigorously defined by the schema. Key conventions:

- **domain:** entities + value objects + repository contracts. Pure Dart vocabulary.
- **infrastructure:** DTOs (with JSON field mappings) + repository implementations (with endpoints).
- **presentation:** providers (Notifier + state_class + state_fields + actions per `config.state_management`), pages (route + states), `widgets_reuse` (populated from `<run_dir>/<adapter>/widget_map.yaml` USE_AS_IS/ADAPT decisions when NDS exists), `widgets_new` (from CREATE_NEW decisions), routes.

### 5. Completeness checks (max 2 refinement passes)

Run the checks declared at the bottom of `spec.schema.yaml`:

1. Every `analysis.json::success_criteria` entry appears in `success_criteria_map` AND maps to ≥1 spec component.
2. Every page has ≥2 states declared.
3. Every domain repository contract has ≥1 corresponding repository implementation.
4. Every notifier provider has `state_class`, `state_fields` (non-empty), `actions` (non-empty).
5. When `design_source.status: extracted` → `adapter`, `nds_ref`, `attachment_uri` all non-null AND NDS file exists on disk.
6. When `disabled` → `adapter` + `attachment_uri` set, `nds_ref` null.
7. When `none` → all three null.

If any check fails, expand the spec and retry once. Max 2 passes. After 2 failed passes, surface the gap to the user and stop.

### 6. Write spec.json

Validate the assembled object against [`spec.schema.yaml`](../../contracts/schemas/spec.schema.yaml). Stop on validation error — never persist a malformed spec. Write to `.pipeline/runs/<ticket_id>/spec.json` with `approved: false`. The Gate 0 step in `/pipeline` flips approval after human review.

### 7. Display summary

```
══════════════════════════════════════════════
Feature Spec: <ticket_id> — <title>
══════════════════════════════════════════════
Design source: <status: extracted | none | disabled> <(adapter)>

DOMAIN
  Entities:           <names>
  Value objects:      <names or "none">
  Repository contracts: <names>

DATA
  DTOs:               <names>
  Repositories:       <names → implements>

PRESENTATION
  Providers:          <name: StateClass>
  Pages:              <name → /route (states)>
  Reuse widgets:      <list> from widget_map (USE_AS_IS + ADAPT)
  New widgets:        <list> from widget_map (CREATE_NEW)
  Routes:             <list>

Success criteria coverage: <N/N mapped>
Completeness:              <all checks passed | N failed>
══════════════════════════════════════════════

Saved to .pipeline/runs/<ticket_id>/spec.json
Edit the file directly before approval if needed.
```

## What this command MUST NOT do

- ❌ Name a specific design-source adapter in conditionals (figma, sketch, etc.). Adapter selection is string-lookup.
- ❌ Write any Dart code. That's `/implement-*`.
- ❌ Hardcode any project path or convention. Everything comes from `.alea.yaml`.
- ❌ Persist a spec that fails schema validation.
