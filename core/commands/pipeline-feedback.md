# `/pipeline-feedback` — Capture Run Metrics

Run after the MR is merged. Aggregates the run's artifacts into a metrics entry, appends to `.pipeline/metrics/history.jsonl`, and re-evaluates the design-source circuit breaker.

## Usage

```
/pipeline-feedback DEV-XXXX
```

## Steps

### 1. Load config + run artifacts

1. Read `.alea.yaml`; validate.
2. Read `.pipeline/runs/<ticket_id>/metrics.json` (created by `/pipeline`), plus every artifact under the run dir.

### 2. Compute feedback metrics

For this run, count:

- `manual_code_corrections` — number of commits between the first phase commit and the final MR commit (excluding the initial pipeline commits). Read via `git log <pipeline-<ticket_id>-start>..HEAD --oneline | grep -v "pipeline(<ticket_id>):"`.
- `phases_completed` — already in `metrics.json`.
- `estimated_cost_usd` — already in `metrics.json`.
- `duration_minutes` — `metrics.last_updated - metrics.started_at` in minutes.
- `design_source_used` — `spec.design_source.adapter` if `extracted`, else `null`.
- `design_source_hallucinations` — count of `visual_fidelity` issues in `gate_<presentation>.json` whose ruleId starts with `visual_fidelity/`.
- `final_passed` — `final_report.json::passed` (or `gate_report.json::passed` for bugfix).
- `mr_url` — from `final_report.json::mr_url` or `git log` notes.

### 3. Append to history

```bash
mkdir -p .pipeline/metrics
```

Append one JSON line to `.pipeline/metrics/history.jsonl`:

```json
{
  "ticket_id": "<ticket_id>",
  "type": "<feature | bugfix>",
  "mode": "<guided | semi | auto>",
  "started_at": "<ISO8601>",
  "completed_at": "<ISO8601>",
  "duration_minutes": <number>,
  "phases_completed": ["<list>"],
  "estimated_cost_usd": <number>,
  "manual_code_corrections": <number>,
  "design_source_used": "<adapter name or null>",
  "design_source_hallucinations": <number>,
  "final_passed": true,
  "mr_url": "<url>"
}
```

### 4. Re-evaluate circuit breakers

#### Unreliable flag

Look at the last `config.pipeline.unreliable_threshold.runs_window` entries (the reference consumer default: 5). Count entries where `manual_code_corrections >= config.pipeline.unreliable_threshold.manual_corrections_per_run` (default: 5). If count >= `config.pipeline.unreliable_threshold.bad_runs_required` (default: 3):

The next `/pipeline` invocation will force `guided` mode. No action needed here; `/pipeline` re-reads the history at run start.

#### Design-source hallucination circuit breaker

For each adapter used recently (last `circuit_breaker_min_runs` entries, the reference consumer default: 5):

```
bad_runs = entries[-N:].count(design_source_used == adapter AND design_source_hallucinations > 0)
total_runs = entries[-N:].count(design_source_used == adapter)
if total_runs >= circuit_breaker_min_runs AND (bad_runs / total_runs) > hallucination_threshold_pct / 100:
  flip .pipeline/config.json::design_source.<adapter>.enabled = false
```

Where `hallucination_threshold_pct` is `config.design_source.adapters.<adapter>.hallucination_threshold_pct` (the reference consumer figma default: 20).

When flipping to disabled, log:
```
⚠ Circuit breaker tripped: <adapter> hallucination rate <X.X>% > <threshold>%.
Disabled in .pipeline/config.json.
Subsequent /design-feature runs will set design_source.status: disabled.
To re-enable: edit .pipeline/config.json::design_source.<adapter>.enabled = true,
OR run a /pipeline-feedback after several clean runs to auto-reset.
```

Auto-reset is opportunistic: if the last `circuit_breaker_min_runs` runs of the adapter all had `design_source_hallucinations == 0`, flip `enabled` back to `true`.

### 5. Display summary

```
══════════════════════════════════════════════
Feedback Captured: <ticket_id>
══════════════════════════════════════════════
Type:                  <type>
Mode:                  <mode>
Duration:              <N> minutes
Estimated cost:        $<X.XX>
Manual corrections:    <N>
Design source:         <adapter | "none">
Fidelity issues:       <N>
Final report:          PASSED ✓ | FAILED ✗

Circuit breakers:
  Unreliable flag:     <ON | OFF> (<N>/<window> recent runs bad)
  <adapter> breaker:   <ENABLED | DISABLED> (<X.X>% hallucination rate)

Saved to .pipeline/metrics/history.jsonl
══════════════════════════════════════════════
```

## What this command MUST NOT do

- ❌ Modify the run artifacts. Only reads.
- ❌ Delete the rollback tag. That's a `/merge` step after the MR is confirmed in main.
- ❌ Re-run analyzers. Reads from existing reports only.
- ❌ Email/post external notifications. Pure local-aggregation step.
