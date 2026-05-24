# Riverpod Manual Adapter — Dispatcher

Entry point invoked by `/implement-<layer>` slash commands. Validates the request and dispatches to the per-layer prompt under [`layers/`](layers/).

## Inputs

The slash command passes a `CodeGenRequest` (see [`code_gen_adapter.dart`](../../../lib/src/contracts/code_gen_adapter.dart)):

- `layer` — one of `domain`, `infrastructure`, `presentation`, `bugfix`.
- `spec` — parsed contents of `.pipeline/runs/<ticket_id>/spec.json` (feature) or null (bugfix uses analysis.json instead).
- `nds` — parsed `.pipeline/runs/<ticket_id>/figma/nds.yaml` (or other adapter subdir) when `spec.design_source.status == "extracted"`. Null otherwise.
- `widgetMap` — parsed `widget_map.yaml` from the same run subdirectory. Null when no NDS.
- `colorMap` — parsed `color_map.yaml` from the same run subdirectory. Null when no NDS.
- `projectRoot` — consumer project root.
- `runDirectory` — `.pipeline/runs/<ticket_id>/`.
- `config` — `ProjectConfig`.

## Pre-generation checklist

Before dispatching, verify:

- [ ] `config.state_management.style == "riverpod_manual"`. If not → throw `CodeGenException(adapter: "riverpod_manual", reason: "wrong style selected: <style>")`. Should never happen if the slash command's routing is correct.
- [ ] For `layer ∈ {domain, infrastructure, presentation}`: `spec` is non-null AND `spec.approved == true`. If approved is false → throw `reason: "spec not approved; aborting"`.
- [ ] For `layer: bugfix`: an `analysis.json` exists with `type: bugfix`.
- [ ] Every layer named in `config.architecture.layers` referenced by this generation exists on disk (paths from config). If missing, throw.
- [ ] `config.theme.path` exists and is readable (presentation only). If missing, log a warning and continue using only `config.theme.brand_colors`.
- [ ] When NDS is expected (`spec.design_source.status == "extracted"`) but missing → throw. When NDS is absent and `status == "none"` or `"disabled"` → continue without NDS.

## Dispatch

| `layer` | Follow ALL instructions in |
|---|---|
| `domain` | [`layers/domain.md`](layers/domain.md) |
| `infrastructure` | [`layers/infrastructure.md`](layers/infrastructure.md) |
| `presentation` | [`layers/presentation.md`](layers/presentation.md) |
| `bugfix` | [`layers/bugfix.md`](layers/bugfix.md) |

The dispatched prompt handles everything: reading inputs, writing Dart files, generating tests, writing the implementation report. It MUST return a `CodeGenResult` to the slash command.

## What this dispatcher MUST NOT do

- ❌ Write Dart code itself. That's the per-layer prompt's job.
- ❌ Decide which layer to dispatch based on inference. The slash command provides `layer` explicitly.
- ❌ Modify config or NDS or spec in any way. Those are read-only.
- ❌ Bypass the pre-generation checklist. If a check fails, throwing is the only valid response.

## Failure modes

| Condition | Behavior |
|---|---|
| Wrong style selected (dispatcher invoked with config saying non-riverpod) | Throw `CodeGenException` immediately. |
| Spec not approved (feature layers) | Throw with a clear message pointing to the Gate 0 step. |
| NDS expected but missing | Throw. Indicates a corrupted run directory or a logic error in `/design-feature`. |
| Per-layer prompt fails internally | The exception propagates up. `/pipeline` retries up to 3 times per layer before giving up. |
