---
description: Generates the presentation layer for a feature — notifiers, pages, widgets, route registration, and widget tests — using spec.json and optional NDS from the design-source adapter.
---
# `/aflow-implement-presentation` — Implement Presentation Layer

Generates the presentation layer: notifiers + pages + widgets + route registration + widget tests. Reads `spec.json::presentation`, plus optional NDS + widget_map + color_map from the design-source run, then dispatches to the configured code-gen adapter.

## Usage

```
/aflow-implement-presentation DEV-XXXX
```

## Steps

### 1. Load config, spec, optional NDS

1. Read `.alea.yaml`; validate.
2. Read `analysis.json::type`. If it is not `feature`, stop with: "This command is for feature tickets only; bugfix tickets use /aflow-implement-bugfix."
3. Read `.pipeline/runs/<ticket_id>/spec.json`. Verify `type: feature` AND `approved: true`. If not:
   ```
   Error: approved spec not found for <ticket_id>.
   Run /aflow-design-feature <ticket_id> and approve at Gate 0 first.
   ```
   Stop.
4. Check `spec.design_source.status`:
   - `extracted` → load NDS from `<run_dir>/<spec.design_source.nds_ref>` (e.g. `figma/nds.yaml`). Load adjacent `widget_map.yaml` and `color_map.yaml`. All three must validate against their schemas.
   - `none` or `disabled` → continue without NDS. The adapter generates from spec + code conventions only.
4. Read consumer files referenced by `spec.presentation.widgets_reuse[*].file` to know their current constructor surfaces (USE_AS_IS must not break call sites; ADAPT requires non-breaking new optional params).
5. Read `config.theme.path` to confirm the available `AppColors`/`AppTextStyles` class names.

### 2. Resolve code-gen adapter

`adapters/code_gen/<config.state_management.style>/`. Stop if missing.

### 3. Dispatch to the adapter

Follow ALL instructions in [`adapters/code_gen/<style>/adapter.md`](../../adapters/code_gen/) with `layer: presentation`, passing the loaded `spec`, `nds`, `widgetMap`, `colorMap`. The adapter routes to `layers/presentation.md`, which:

- Generates state-management code per `config.state_management.style`.
- Generates pages with switch-over-status patterns.
- Generates new widgets (when NDS + widget_map dictate CREATE_NEW).
- Imports existing widgets (when widget_map says USE_AS_IS / ADAPT).
- Registers routes in `config.routing.router_path`.
- Generates widget tests overriding repository providers per `config.testing.override_target`.
- Returns `CodeGenResult`.

### 4. Run quality validations

```bash
flutter analyze <files from CodeGenResult>
dart format --set-exit-if-changed <same>
flutter test <test paths> --coverage
```

Coverage threshold: `config.coverage.thresholds.presentation` (the reference consumer default: 70).

### 5. Write `presentation_impl.md`

Produced by the adapter at `<run_dir>/presentation_impl.md`. Must include `## files_changed`, `## Dependencies Required (NOT auto-added)`, and the theme tokens summary (USE_EXACT / USE_CLOSEST / CREATE_NEW from `color_map.yaml`).

### 6. Display summary

```
══════════════════════════════════════════════
Presentation Implementation: <ticket_id>
══════════════════════════════════════════════
Adapter:          <style>
NDS source:       <adapter name or "none">
Providers:        <N> created
Pages:            <N> (states: <list>)
New widgets:      <N>
Reused widgets:   <N> (USE_AS_IS) + <N> (ADAPT)
Routes added:     <N>
Tests:            <N> written

Theme tokens:
  USE_EXACT:      <N>
  USE_CLOSEST:    <N> (max Δ: <X.X>%)
  CREATE_NEW:     <N> (raw hex — needs theme entry)

✓ flutter analyze — 0 issues
✓ dart format    — clean
✓ flutter test   — <N> tests, coverage <XX>%
══════════════════════════════════════════════

Saved to .pipeline/runs/<ticket_id>/presentation_impl.md
Next: /aflow-run-gates <ticket_id> --gate presentation
```

## What this command MUST NOT do

- ❌ Write Dart code directly.
- ❌ Modify the consumer's `pubspec.yaml`. New dependencies are listed in `presentation_impl.md::Dependencies Required`.
- ❌ Override notifiers in widget tests. Tests override the target declared in `config.testing.override_target` (the reference consumer: `repository`).
- ❌ Persist code that uses raw hex literals when `color_map.yaml` resolved a token. Visual-fidelity gate catches this.
