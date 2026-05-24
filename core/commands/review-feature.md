# `/review-feature` — Review Feature

Cross-checks the full implementation against `analysis.json::success_criteria` and the per-layer impl reports. Produces `final_report.json` for `/pipeline` and `/create-mr` to read.

## Usage

```
/review-feature DEV-XXXX
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
dart run alea analyze \
  --project-root . \
  --gate full \
  --format json \
  --output-file <run_dir>/cross_layer_report.json \
  --changed-files <every file from step 1>
```

Embed the result under `final_report.json::cross_layer`.

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
  "summary": {
    "success_criteria_total": <N>,
    "success_criteria_met": <N>,
    "files_total": <N>,
    "spec_drift_count": <N>,
    "unmet_criteria_count": <N>,
    "coverage_violations": <N>
  },
  "unmet_criteria": [],
  "spec_drift": [],
  "coverage_violations": [],
  "cross_layer": <full GateReport object>
}
```

`passed` is true iff: `unmet_criteria_count == 0` AND `spec_drift_count == 0` AND `coverage_violations == 0` AND `cross_layer.passed == true`.

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
[PASSED]: Next /validate-functional or /create-mr.
[FAILED]: Address the items above. Re-run /review-feature after fixes.
```

## What this command MUST NOT do

- ❌ Re-run analyzers it doesn't need (run-gates is the per-layer gate; this is a cross-cutting review).
- ❌ Fix anything. Discrepancies are reported, not corrected.
- ❌ Hardcode coverage thresholds. All from config.
