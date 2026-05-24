# `/implement-bugfix` — Implement Bugfix

Applies targeted edits to existing files driven by `analysis.json::root_cause_hypothesis` and `analysis.json::affected_files`. Adds regression tests.

## Usage

```
/implement-bugfix DEV-XXXX
```

## Steps

### 1. Load config and analysis

1. Read `.alea.yaml`; validate.
2. Read `.pipeline/runs/<ticket_id>/analysis.json`. Verify `type: bugfix`. If not:
   ```
   Error: bugfix analysis not found for <ticket_id>.
   Run /analyze-ticket first (this command requires type: bugfix).
   ```
   Stop.

### 2. Resolve code-gen adapter

`adapters/code_gen/<config.state_management.style>/`. Stop if missing.

### 3. Dispatch to the adapter

Follow ALL instructions in [`adapters/code_gen/<style>/adapter.md`](../../adapters/code_gen/) with `layer: bugfix`. The adapter routes to `layers/bugfix.md`, which:

- Reads `analysis.json::{affected_files, root_cause_hypothesis, success_criteria}`.
- Confirms the hypothesis by inspecting code paths.
- Applies the smallest possible diff to fix the bug.
- Adds a regression test (one per bug fixed) named `'fixes <ticket_id>: <description>'`.
- Returns `CodeGenResult`.

### 4. Run quality validations

```bash
flutter analyze <files from CodeGenResult>
dart format --set-exit-if-changed <same>
flutter test <test paths>
```

No coverage threshold for bugfix — the regression test is what matters.

### 5. Write `implementation.md`

The adapter produces this at `<run_dir>/implementation.md`. Must include the corrected hypothesis (when the original was wrong), per-file change summaries, regression-test names, and `## files_changed`.

### 6. Display summary

```
══════════════════════════════════════════════
Bugfix Implementation: <ticket_id>
══════════════════════════════════════════════
Adapter:               <style>
Hypothesis confirmed:  <yes | corrected>
Files modified:        <N>
Lines added:           <N>
Lines removed:         <N>
Regression tests:      <N> added

✓ flutter analyze — 0 issues
✓ dart format    — clean
✓ flutter test   — <N> tests passed
══════════════════════════════════════════════

Saved to .pipeline/runs/<ticket_id>/implementation.md
Next: /run-gates <ticket_id> --gate bugfix
```

## What this command MUST NOT do

- ❌ Refactor beyond what the fix requires.
- ❌ Add new entities, providers, pages, or DTOs. Bugfix is for existing code.
- ❌ Touch files not in `analysis.json::affected_files` unless the corrected hypothesis explicitly requires it (and the deviation is documented in `implementation.md::Hypothesis Correction`).
- ❌ Skip the regression test.
