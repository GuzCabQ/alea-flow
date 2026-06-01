---
description: Cross-checks the full implementation against success_criteria and per-layer impl reports, producing final_report.json for the pipeline and MR creation steps to consume.
---
# `/aflow-review-feature` — Review Feature

Cross-checks the full implementation against `analysis.json::success_criteria` and the per-layer impl reports. Produces `final_report.json` for `/aflow-pipeline` and `/aflow-create-mr` to read.

## Usage

```
/aflow-review-feature DEV-XXXX
```

## Steps

### 1. Load config and run artifacts

1. Read `.alea.yaml`; validate.
2. Read `.pipeline/runs/<ticket_id>/analysis.json` and `spec.json`. Verify `spec.approved: true`.
3. Read every `<layer>_impl.md` under `<run_dir>/`. Collect `files_changed` from each. Build the union: all files touched by this feature.

### 2. Verify success criteria coverage

For every entry in `analysis.json::success_criteria`:

1. Look up the corresponding entry in `spec.success_criteria_map`.
2. For each component name mapped: verify a file matching that component exists in the implementation (e.g. `ExamplePage` → `lib/.../example_page.dart` exists).
3. Verify the file has content (>10 lines of substantive Dart, not just stubs).

If any criterion is unmatched: flag as `major` violation in `final_report.json::unmet_criteria`.

### 3. Cross-layer integrity

Run the layer integrity analyzer scoped to the full file set:

```bash
aflow analyze \
  --project-root . \
  --gate full \
  --format json \
  --output-file <run_dir>/cross_layer_report.json \
  --changed-files <every file from step 1>
```

Embed the result under `final_report.json::cross_layer`.

### 3b. Untouched-consumer regression check (graph-verified)

The graph must reflect the post-implementation tree, so refresh it first (the `/implement-*` phases changed files):

```bash
aflow graph --ensure-fresh -o .pipeline/graph.json --project-root .
# For each file in the files_changed union (step 1):
aflow graph-query impact <changed-file> -i .pipeline/graph.json --format json
```

Any `impacted` consumer that is **NOT** in the `files_changed` union is a potential regression: a dependent of changed code that was neither updated nor re-tested. Collect these into `final_report.json::untouched_consumers[]` as `{file, depends_on}` and flag each as `major` (non-blocking warning — surfaced for the human, does not by itself set `passed: false`).

### 3c. State-flow regression check (graph-verified, when state holders changed)

The reverse-import closure above misses state dependencies expressed only inside method bodies (a widget that `ref.watch`/`context.watch`/`Get.find`s a provider/controller — not an import-level dependency). When any changed file declares a node with a state-mgmt `role` (`*.notifier`, `*.controller`, `getx.service`, `flutter.change_notifier`):

```bash
aflow graph-query state-flow -i .pipeline/graph.json --format json
```

`state_flow[]` lists each role-tagged node and the state-API calls (`watch`/`read`/`find`/`put`/…) its methods make. If a changed state holder is consumed by a node NOT in `files_changed`, add it to `untouched_consumers[]` (same `major`, non-blocking treatment). Note: these `calls` are `confidence: ambiguous` (by-name) — treat as a hint to verify, not a proven edge.

### 4. Coverage aggregation

Verify each layer's per-file coverage against `config.coverage.thresholds.<layer>`:

- `domain` files (matched against `config.architecture.layers.domain.paths`) → threshold from `coverage.thresholds.domain`.
- Same for `infrastructure`, `presentation`.

Flag any below-threshold file as `major` under `final_report.json::coverage_violations`.

### 5. Spec ↔ implementation diff

For each section of `spec.json`:

- `domain.entities[*]` — does a Dart file exist at the path the adapter created?
- `data.dtos[*]` and `data.repositories[*]` — same.
- `presentation.providers[*]`, `pages[*]`, `widgets_new[*]` — same.

For any missing implementation: flag as `critical` under `final_report.json::spec_drift`. The spec promised something the implementation didn't deliver.

### 6. Write `final_report.json`

```json
{
  "ticket_id": "<ticket_id>",
  "passed": true,
  "timestamp": "<ISO8601>",
  "mr_url": null,
  "summary": {
    "success_criteria_total": <N>,
    "success_criteria_met": <N>,
    "files_total": <N>,
    "spec_drift_count": <N>,
    "unmet_criteria_count": <N>,
    "coverage_violations": <N>,
    "untouched_consumers_count": <N>,
  },
  "unmet_criteria": [],
  "spec_drift": [],
  "coverage_violations": [],
  "untouched_consumers": [],
  "cross_layer": <full GateReport object>
}
```

`passed` is true iff: `unmet_criteria_count == 0` AND `spec_drift_count == 0` AND `coverage_violations == 0` AND `cross_layer.passed == true`.

### 6b. Validate the report

Run `aflow validate-artifact --schema final_report --artifact <run_dir>/final_report.json`. If it exits non-zero, fix the report's shape before continuing.

### 7. Display summary

```
══════════════════════════════════════════════
Feature Review: <ticket_id>
══════════════════════════════════════════════
Status: PASSED ✓ | FAILED ✗

Success criteria: <met>/<total>
<for each criterion: ✓ <text> | ✗ <text> — missing: <component>>

Spec drift:       <N> spec items without implementation
<list each>

Coverage:         <N> files below threshold
<list each with current vs required>

Cross-layer:      <N> integrity issues
<list each>
══════════════════════════════════════════════

Saved to .pipeline/runs/<ticket_id>/final_report.json
[PASSED]: Next /aflow-validate-functional or /aflow-create-mr.
[FAILED]: Address the items above. Re-run /aflow-review-feature after fixes.
```

## What this command MUST NOT do

- ❌ Re-run analyzers it doesn't need (run-gates is the per-layer gate; this is a cross-cutting review).
- ❌ Fix anything. Discrepancies are reported, not corrected.
- ❌ Hardcode coverage thresholds. All from config.
