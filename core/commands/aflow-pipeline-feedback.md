---
description: Aggregates a completed run's artifacts into a metrics entry, appends it to the pipeline history, and re-evaluates the design-source circuit breaker.
---
# `/aflow-pipeline-feedback` — Capture Run Metrics

Run after the MR is merged. Aggregates the run's artifacts into a metrics entry, appends to `.pipeline/metrics/history.jsonl`, and re-evaluates the design-source circuit breaker.

## Usage

```
/aflow-pipeline-feedback DEV-XXXX
```

## Steps

### 1. Load config + run artifacts

1. Read `.alea.yaml`; validate.
2. Read `.pipeline/runs/<ticket_id>/metrics.json` (created by `/aflow-pipeline`), plus every artifact under the run dir.

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

### 4. Re-evaluate circuit breakers (arithmetic by code, not by hand)

**Do not compute these counts by hand.** Run the tested aggregator over the
history and read its verdict:

```bash
aflow metrics \
  --history .pipeline/metrics/history.jsonl \
  --window <config.pipeline.unreliable_threshold.runs_window> \
  --manual-threshold <config.pipeline.unreliable_threshold.manual_corrections_per_run> \
  --bad-runs <config.pipeline.unreliable_threshold.bad_runs_required> \
  --circuit-min-runs <config...circuit_breaker_min_runs> \
  --hallucination-pct <config.design_source.adapters.<adapter>.hallucination_threshold_pct> \
  --format json
# → {"unreliable_flag": bool, "adapters": [{"adapter","breaker_tripped",...}], ...}
```

#### Unreliable flag

If `unreliable_flag` is true, the next `/aflow-pipeline` invocation will force
`guided` mode. No action needed here; `/aflow-pipeline` re-reads the history at run
start (and should call `aflow metrics` itself to decide).

#### Design-source hallucination circuit breaker

For each adapter in `adapters[]` (the `aflow metrics` output decides both
directions — do not recompute):

- `breaker_tripped: true` → flip `.pipeline/config.json::design_source.<adapter>.enabled = false`.
- `should_reset: true` → flip it back to `enabled = true` (auto-reset: the last
  `circuit_breaker_min_runs` runs were all clean). `breaker_tripped` and
  `should_reset` are mutually exclusive, so there is never a conflict.

When flipping to disabled, log:
```
⚠ Circuit breaker tripped: <adapter> hallucination rate <X.X>% > <threshold>%.
Disabled in .pipeline/config.json.
Subsequent /aflow-design-feature runs will set design_source.status: disabled.
To re-enable: a later /aflow-pipeline-feedback auto-resets once
`aflow metrics` reports should_reset: true (or edit enabled = true by hand).
```

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
- ❌ Delete the rollback tag. That's a `/aflow-merge` step after the MR is confirmed in main.
- ❌ Re-run analyzers. Reads from existing reports only.
- ❌ Email/post external notifications. Pure local-aggregation step.
