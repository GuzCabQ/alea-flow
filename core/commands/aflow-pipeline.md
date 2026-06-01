---
description: Runs the full ALEA pipeline from a ticket to a merge request — analyze, design or implement, gates, review, code-review, MR, and QA handoff — for both feature and bugfix tickets.
---
# `/aflow-pipeline` — Orchestrator

Runs the full ALEA pipeline from a ticket to a merge request: analyze → design / implement → gates → review → code-review → MR + QA handoff. Supports both feature and bugfix tickets. Resumes from the most-recent completed phase when re-invoked on an existing run.

## Usage

```
/aflow-pipeline DEV-XXXX [--ticket-file <path>] [--mode guided|semi|auto] [--reset]
```

**Flags:**

- `--ticket-file <path>` — Use a local file via the `file/` adapter instead of the configured ticket-source adapter.
- `--mode <mode>` — Autonomy mode. Overrides `.alea.yaml::pipeline.default_mode`, unless the unreliable flag forces `guided`.
- `--reset` — Delete the existing run directory and start fresh.

## Modes

| Mode | Stops at |
|---|---|
| `guided` | Every gate — explicit approval required before each phase. |
| `semi` | Gate 0 (spec/analysis approval) and Gate Final (review) only. |
| `auto` | Only when a validator fails (requires fix before continuing). |

Default and available modes come from `.alea.yaml::pipeline.default_mode` and `pipeline.modes_available`.

## Cost tracking

Per-phase estimates are stamped into `metrics.json` as the pipeline runs. Thresholds come from config:

- Warning threshold: `.alea.yaml::pipeline.cost_warn_usd` (the reference consumer default: $3.00)
- Hard-stop threshold: `.alea.yaml::pipeline.cost_hard_stop_usd` (the reference consumer default: $5.00)

Phase estimates (USD, approximate):

| Phase | Estimate |
|---|---|
| analyze | $0.05 |
| design | $0.20 |
| domain_impl | $0.15 |
| infrastructure_impl | $0.15 |
| presentation_impl | $0.25 |
| gate (per layer) | $0.03–0.05 |
| review | $0.08 |
| validate | $0.05 |
| code_review | $0.08 |
| bugfix_impl | $0.20 |

Typical feature run: ~$1.00.

---

## Instructions

### 0. Parse arguments and load config

1. Extract `ticket_id` from the first token of `$ARGUMENTS`.
2. Detect flags: `--ticket-file <path>`, `--mode <m>`, `--reset`.
3. Load `.alea.yaml` from the consumer project root. Validate against [`contracts/schemas/project-config.schema.yaml`](../../contracts/schemas/project-config.schema.yaml). Stop on any error.
4. Determine effective mode:
   - If `--mode` is provided AND its value is in `config.pipeline.modes_available` → use it.
   - Else use `config.pipeline.default_mode`.

#### Resume vs fresh

If `--reset` is set, remove `.pipeline/runs/<ticket_id>/` (if it exists), announce the reset, and continue to step 1 (fresh start).

Otherwise inspect `.pipeline/runs/<ticket_id>/` for resume signals. Check in order (most-complete first):

**Feature runs:**

| Signal found | Resume from |
|---|---|
| `code_review.json` with `approved: true` | Phase 7 (MR + QA) |
| `validation_report.json` with `overall_passed: true` | Phase 6.7 (code-review) |
| `final_report.json` with `passed: true` | Phase 6.5 (validate-functional) |
| `presentation_impl.md` (last layer's impl exists) | Phase 6 (review-feature) |
| Last-but-one layer's `<layer>_impl.md` exists | Implement the remaining layer + its gate |
| First layer's `<layer>_impl.md` exists | Implement the next layer + gate |
| `spec.json` with `approved: true` | Phase 3 (first layer implementation) |
| `analysis.json` with `type: feature` | Phase 2 (design-feature) |

**Bugfix runs:**

| Signal found | Resume from |
|---|---|
| `code_review.json` with `approved: true` | Phase 4B (MR + QA) |
| `gate_report.json` with `passed: true` | Phase 3.5B (code-review) |
| `implementation.md` exists | Phase 3B (run-gates) |
| `analysis.json` with `type: bugfix` | Phase 2B (implement-bugfix), after showing the analysis and asking the user to confirm |

Announce: `Resuming <ticket_id> from <phase_name> in mode <effective_mode>.`

### The driver loop (single source of control flow)

`/aflow-pipeline` does NOT re-implement phase ordering or gates in prose — that logic
lives in **`aflow run`** (the referee). The loop is:

1. Run `aflow run <ticket_id> --format json` (pass `--mode` if the user set one).
2. Read the decision's `status`:
   - `advance` → execute `next_action.command` (follow that command's markdown),
     then go to step 1.
   - `awaitingHuman` → present `reason` + the gate report; in guided/semi wait
     for the human (e.g. set `spec.json::approved = true`), then go to step 1.
   - `blocked` → present `gate.violations`; the AI fixes and goes to step 1.
     **NEVER advance past a `blocked`.**
   - `done` → continue to the post-slice phases (review / validate / feedback /
     create-mr / qa-handoff) as they are built.
3. The cost gate, mode resolution, and unreliable-flag are all decided by
   `aflow run` — honor its `mode` and any `cost_limit` block.

The per-phase descriptions below are **human-facing narration**; `aflow run`
decides when to advance. (The slice covers `analyze → design → first-implement`;
the later phases are still driven by the prose until their gates exist.)

### 0.1 — Initialize config, metrics, rollback, unreliable flag

Run this initialization **once per fresh run only** (skip when resuming an existing `metrics.json`).

#### a) Initialize `.pipeline/config.json` (run-scoped overrides)

```bash
mkdir -p .pipeline
```

This file holds operational state that persists across runs (currently: design-source circuit-breaker flags). If absent, create with defaults derived from `.alea.yaml`:

```json
{
  "design_source": {
    "figma": { "enabled": true },
    "image": { "enabled": false },
    "markup": { "enabled": false }
  }
}
```

The set of adapter keys comes from `.alea.yaml::design_source.adapters`. Initial `enabled` values are copied from the same source. `pipeline-feedback` flips these to `false` when the hallucination threshold is exceeded.

If the file already exists, read and use it. Never overwrite values set by the user or by `pipeline-feedback`.

#### b) Unreliable flag

When `.pipeline/metrics/history.jsonl` exists, compute the flag with the tested
aggregator (do not count by hand):

```bash
aflow metrics \
  --window <config.pipeline.unreliable_threshold.runs_window> \
  --manual-threshold <config.pipeline.unreliable_threshold.manual_corrections_per_run> \
  --bad-runs <config.pipeline.unreliable_threshold.bad_runs_required> \
  --format json
# → read .unreliable_flag (bool)
```

If `unreliable_flag` is true:

```
⚠ UNRELIABLE FLAG: <N>/<window> recent runs had ≥<threshold> manual corrections.
  Forcing mode: guided (overrides --mode).
  Run `aflow metrics` for details.
  Improve pipeline accuracy before using semi/auto.
```

Force `effective_mode = "guided"`.

#### c) Rollback tag

```bash
git tag "pipeline-<ticket_id>-start" 2>/dev/null || true
```

(The `|| true` silences re-tag errors if the tag exists from a prior run.)

#### d) Initialize `metrics.json`

```json
{
  "ticket_id": "<ticket_id>",
  "mode": "<effective_mode>",
  "rollback_tag": "pipeline-<ticket_id>-start",
  "phases_completed": [],
  "estimated_cost_usd": 0.00,
  "cost_warn_usd": <from config>,
  "cost_stop_usd": <from config>,
  "started_at": "<ISO8601 now>",
  "last_updated": "<ISO8601 now>"
}
```

### Cost-tracking helper

After completing each phase, update `metrics.json`:

1. Append the phase name to `phases_completed`.
2. Add the phase's estimated cost to `estimated_cost_usd`.
3. Update `last_updated`.

Then evaluate the cost gate:

```
If estimated_cost_usd >= cost_stop_usd:
  ⛔ COST LIMIT REACHED: $<X.XX> (limit: $<cost_stop_usd>)
  Work preserved in .pipeline/runs/<ticket_id>/
  Rollback available: git checkout pipeline-<ticket_id>-start
  Re-run /aflow-pipeline <ticket_id> to resume from the last checkpoint.
  Stop immediately — do not proceed to the next phase.

If estimated_cost_usd >= cost_warn_usd:
  ⚠ COST WARNING: $<X.XX> reached the warning threshold ($<cost_warn_usd>).
  Continue, but consider whether remaining phases justify the cost.
```

---

### Phase 1 — Analyze ticket

Follow ALL instructions in [`/aflow-analyze-ticket`](aflow-analyze-ticket.md), passing `<ticket_id>` and `--ticket-file <path>` if provided.

After completion, update `metrics.json` with phase `"analyze"` (+$0.05) and run the cost gate.

Read `analysis.json["type"]`:

- `feature` → continue to **Feature Flow** below.
- `bugfix` → continue to **Bugfix Flow** below.

---

## Bugfix Flow

> The phase order and gates below are **enforced by `aflow run`** (see The driver loop). The descriptions here are human-facing narration of what each phase does; the referee decides when to advance.

### Phase 1B — Gate 0: Human checkpoint

Present a short summary of `analysis.json` and wait for approval:

```
══════════════════════════════════════════════
GATE 0 — Human checkpoint (bugfix)
══════════════════════════════════════════════
Review the analysis above.
Edit .pipeline/runs/<ticket_id>/analysis.json directly if anything is wrong.

Type 'yes' to continue with implementation.
Type 'no' or describe corrections to re-run analysis.
```

In `auto` mode: skip this gate UNLESS the unreliable flag forced `guided`. In `semi` and `guided`: always wait.

### Phase 2B — Implement bugfix

Follow ALL instructions in [`/aflow-implement-bugfix`](aflow-implement-bugfix.md) for `<ticket_id>`.

If quality validations fail after 3 retries:

```
Implementation blocked after 3 attempts.
Last error: <error detail>
Partial work preserved. Run /aflow-implement-bugfix <ticket_id> to continue manually.
```

Stop.

**Phase commit:** stage files listed in `.pipeline/runs/<ticket_id>/implementation.md::files_changed` and commit:

```bash
git add <each file from implementation.md::files_changed>
if ! git commit -m "pipeline(<ticket_id>): phase 2 — bugfix implemented"; then
  echo "⛔ Phase commit failed (nothing staged, or a hook blocked it). Stopping — do not continue."
  # stop the pipeline; the work is preserved and the rollback tag is intact.
fi
```

Update `metrics.json` with phase `"bugfix_impl"` (+$0.20). Run cost gate.

### Phase 3B — Run gates

Follow ALL instructions in [`/aflow-run-gates`](aflow-run-gates.md) for `<ticket_id>`, with `--gate bugfix`.

Update `metrics.json` with phase `"gate_bugfix"` (+$0.04). Run cost gate.

If gates fail (BLOCKER/CRITICAL after 3 retries):

```
Gate failed. See issues above.
Partial work preserved at .pipeline/runs/<ticket_id>/
Fix the issues and re-run /aflow-run-gates <ticket_id>.
```

Stop.

### Phase 3.5B — Code review (semantic)

Follow ALL instructions in [`/aflow-code-review`](aflow-code-review.md) for `<ticket_id>`.
This is the semantic-correctness gate the analyzers can't cover (logic, naming,
dead code, swallowed exceptions). Its checklist intentionally overlaps the
analyzers as **defense-in-depth** — do not skip it because `/aflow-run-gates` passed.

Update `metrics.json` with phase `"code_review"` (+$0.08). Run cost gate.

Handle `code_review.json::approved` by mode:

- **Not approved** (any `blocker`/`critical` finding): present the findings.
  - `guided` | `semi`: wait — fix the code and re-run `/aflow-code-review`, or accept with explicit override.
  - `auto`: STOP (semantic findings can't be auto-fixed reliably). Report and preserve work.
- **Approved** (only `major`/`minor`): show findings as informational; in `guided` ask `Continue to create MR? (yes/no)`, else continue.

### Phase 4B — Create MR + QA handoff

Follow ALL instructions in [`/aflow-create-mr`](aflow-create-mr.md), then [`/aflow-qa-handoff`](aflow-qa-handoff.md), each for `<ticket_id>`.

Show the final report (see [Final Report (Bugfix)](#final-report-bugfix) below).

---

## Feature Flow

> The phase order and gates below are **enforced by `aflow run`** (see The driver loop). The descriptions here are human-facing narration of what each phase does; the referee decides when to advance.

### Phase 2 — Design feature

Follow ALL instructions in [`/aflow-design-feature`](aflow-design-feature.md) for `<ticket_id>`. The design phase walks `analysis.json::attachments[]` and delegates to the first enabled design-source adapter that matches.

After spec generation, update `metrics.json` with phase `"design"` (+$0.20). Run cost gate.

Present **Gate 0**:

```
══════════════════════════════════════════════
GATE 0 — Spec approval (feature)
══════════════════════════════════════════════
Review the spec summary above.
Edit .pipeline/runs/<ticket_id>/spec.json directly for any tweak.

Type 'yes' to approve and start implementation.
Type 'no' or describe corrections to refine the spec (max 2 refinement passes).
```

In `auto` mode: skip UNLESS unreliable flag is set. In `semi` and `guided`: always wait.

On approval: set `spec.json["approved"] = true`.

### Phases 3..N — Implement layers, one per layer in config order

Iterate over `config.architecture.layers` in the order they appear in `.alea.yaml`. For each layer named `<layer>`:

#### Implementation step

Follow ALL instructions in `/implement-<layer>` (e.g., `/aflow-implement-domain`, `/aflow-implement-infrastructure`, `/aflow-implement-presentation`) for `<ticket_id>`. The command name MUST exist under [`core/commands/`](.) — if it doesn't, this layer cannot be implemented automatically and the pipeline stops with a clear message.

If quality validations fail after 3 retries:

```
Implementation of <layer> blocked after 3 attempts.
Partial work preserved. Run /implement-<layer> <ticket_id> to continue manually.
```

Stop.

**Phase commit:** stage files listed in `.pipeline/runs/<ticket_id>/<layer>_impl.md::files_changed` and commit:

```bash
git add <each file from <layer>_impl.md::files_changed>
if ! git commit -m "pipeline(<ticket_id>): phase <N> — <layer> implemented"; then
  echo "⛔ Phase commit failed (nothing staged, or a hook blocked it). Stopping — do not continue."
  # stop the pipeline; the work is preserved and the rollback tag is intact.
fi
```

Update `metrics.json` with phase `"<layer>_impl"` (+ the layer's estimated cost: domain $0.15, infrastructure $0.15, presentation $0.25, others $0.20 default).

#### Layer gate

Follow ALL instructions in [`/aflow-run-gates`](aflow-run-gates.md) with `--gate <layer>` for `<ticket_id>`.

Update `metrics.json` with phase `"gate_<layer>"` (+ the gate's estimated cost from `config.gates.<layer>` × $0.03).

Handle results by priority (same rules as `/aflow-run-gates` internally enforces):

- **BLOCKER / CRITICAL:** auto-fix, retry up to 3 times, stop if still failing.
- **MAJOR:** in `guided`, ask "Fix or continue?"; in `semi`/`auto`, continue with a warning.
- **MINOR:** show as informational, continue.

**Mode checkpoint after gate:**

- `guided`: present results and ask `Continue to <next_layer or "final review">? (yes/no)`.
- `semi` | `auto`: if the gate passed, continue automatically; if failed, stop with the issues.

### Phase 6 — Review feature

Follow ALL instructions in [`/aflow-review-feature`](aflow-review-feature.md) for `<ticket_id>`.

Update `metrics.json` with phase `"review"` (+$0.08). Run cost gate.

**Gate Final per mode:**

- `guided`: present compliance report and ask `Continue to functional validation? (yes/no)`.
- `semi`: **STOP HERE** — this is the Gate Final for `semi` mode. Present the report and wait for explicit approval before continuing.
- `auto`: if passed, continue; if failed, stop with the issues.

### Phase 6.5 — Functional validation

Follow ALL instructions in [`/aflow-validate-functional`](aflow-validate-functional.md) for `<ticket_id>`.

Update `metrics.json` with phase `"validate"` (+$0.05). Run cost gate.

**Mode checkpoint:**

- `guided`: ask `Continue to code review? (yes/no)`.
- `semi` | `auto`: if passed, continue automatically.

### Phase 6.7 — Code review (semantic)

Follow ALL instructions in [`/aflow-code-review`](aflow-code-review.md) for `<ticket_id>`.
This is the semantic-correctness gate the analyzers can't cover (logic, naming,
dead code, swallowed exceptions). Its checklist intentionally overlaps the
analyzers as **defense-in-depth** — do not skip it because the gates passed.

Update `metrics.json` with phase `"code_review"` (+$0.08). Run cost gate.

Handle `code_review.json::approved` by mode:

- **Not approved** (any `blocker`/`critical` finding): present the findings.
  - `guided` | `semi`: wait — fix the code and re-run `/aflow-code-review`, or accept with explicit override.
  - `auto`: STOP (semantic findings can't be auto-fixed reliably). Report and preserve work.
- **Approved** (only `major`/`minor`): show findings as informational; in `guided` ask `Continue to create MR? (yes/no)`, else continue.

### Phase 7 — Create MR + QA handoff

Follow ALL instructions in [`/aflow-create-mr`](aflow-create-mr.md), then [`/aflow-qa-handoff`](aflow-qa-handoff.md), each for `<ticket_id>`.

---

## Final Report (Bugfix)

```
══════════════════════════════════════════════
Pipeline Complete: <ticket_id> (bugfix)
══════════════════════════════════════════════
✓ Phase 1: Analysis (bugfix)
✓ Phase 2: Implementation (<N> files changed)
✓ Phase 3: Gates (all passed)
✓ Phase 3.5: Code review — approved
✓ Phase 4: MR created — <MR URL>
✓ Phase 4: QA handoff generated

Mode:              <effective_mode>
Estimated cost:    ~$<estimated_cost_usd>
Rollback tag:      pipeline-<ticket_id>-start
Run artifacts:     .pipeline/runs/<ticket_id>/
══════════════════════════════════════════════

Run /aflow-pipeline-feedback <ticket_id> after the MR is merged.
```

## Final Report (Feature)

```
══════════════════════════════════════════════
Pipeline Complete: <ticket_id> (feature)
══════════════════════════════════════════════
✓ Phase 1:    Analysis — feature detected
✓ Phase 2:    Design spec — approved
✓ Gate 0:     Spec checkpoint
<for each layer in config order:>
✓ Phase <N>:  <layer> (<N> things created)
✓ Gate <N>:   <layer> — passed
✓ Phase 6:    Review — all criteria verified, coverage OK
✓ Phase 6.5:  Functional validation — passed
✓ Phase 6.7:  Code review — approved
✓ Phase 7:    MR created — <MR URL>
✓ Phase 7:    QA handoff generated

Mode:              <effective_mode>
Estimated cost:    ~$<estimated_cost_usd>
Rollback tag:      pipeline-<ticket_id>-start
Design source:     <spec.design_source.adapter or "none">
Run artifacts:     .pipeline/runs/<ticket_id>/
══════════════════════════════════════════════

Run /aflow-pipeline-feedback <ticket_id> after the MR is merged to improve future runs.
```

---

## Failure handling

| Failure | Behavior |
|---|---|
| `.alea.yaml` missing / invalid | Stop at Phase 0 with schema error. |
| Cost limit reached | Stop. Work is preserved. Resume removes nothing. |
| Implementation retries exhausted | Stop. Show last error, point user to the layer-specific command for manual recovery. |
| Gate retries exhausted | Stop. Issues are listed; user fixes and re-runs `/aflow-run-gates`. |
| Adapter not found (ticket-source or design-source) | Stop at the phase that needed it, with the missing adapter name. |
| Unreliable flag triggers | Force `guided`. The pipeline continues but every gate becomes interactive. |

## What `/aflow-pipeline` does NOT do

- Does not bypass any individual phase command. It always delegates — never inlines analyzer invocations, adapter prompts, or schema writes.
- Does not edit consumer source files directly. All edits go through `/implement-*` commands.
- Does not enforce a specific number of layers — the count and order come from `config.architecture.layers`. Three (domain/infrastructure/presentation) is convention, not a constraint.
- Does not call AI APIs directly. The whole pipeline is markdown prompts executed by an AI-driven CLI. The operations these prompts rely on (command invocation, shell execution, file I/O) are defined platform-agnostically in [`references/README.md`](references/README.md); each platform has an adapter, e.g. [`references/claude-code-tools.md`](references/claude-code-tools.md).
- Does not push the MR or comment on Asana/Linear/Jira — those are `/aflow-create-mr` and (future) `/notify-ticket` responsibilities.
