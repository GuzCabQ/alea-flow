---
description: Invokes the ALEA CLI analyzers against changed files, then runs flutter analyze and flutter test with coverage, reporting results and retrying auto-fixable issues.
---
# `/aflow-run-gates` — Run Quality Gates

Invokes the ALEA CLI to run registered analyzers against changed files, then layers in `flutter analyze` and `flutter test --coverage`. Reports results, applies severity policy, and retries auto-fixable issues.

## Usage

```
/aflow-run-gates DEV-XXXX [--gate <layer>]
```

`--gate` defaults to the gate that matches the most recent implementation phase (see step 2). It's a label only — the analyzers that actually run come from `.alea.yaml::analyzers.enabled`.

## Steps

### 1. Load config and locate the run

1. Read `.alea.yaml` from project root; validate.
2. Verify `.pipeline/runs/<ticket_id>/` exists. If not:
   ```
   Error: run directory .pipeline/runs/<ticket_id>/ not found.
   Nothing to gate. Run /aflow-analyze-ticket first.
   ```
   Stop.

### 2. Determine changed files

Read every `<layer>_impl.md` (or `implementation.md` for bugfix) under `<run_dir>/`. Collect each file listed in their `## files_changed` section. Also run `git diff --name-only HEAD` to capture anything not reported by impl markdowns. Union both lists; keep only `.dart` files.

If empty:
```
Warning: no modified .dart files detected for <ticket_id>.
Nothing to gate. Run /implement-* first.
```
Stop.

### 3. Resolve the gate label

`--gate <X>` if provided. Otherwise infer from the most recent impl file:
`presentation_impl.md` → `presentation`; `infrastructure_impl.md` → `infrastructure`; `domain_impl.md` → `domain`; `implementation.md` → `bugfix`.

### 4. Invoke the ALEA CLI

```bash
aflow analyze \
  --project-root . \
  --gate <gate> \
  --format human \
  --run-directory .pipeline/runs/<ticket_id>/ \
  --output-file .pipeline/runs/<ticket_id>/gate_report.json \
  --changed-files <file1> \
  --changed-files <file2> \
  ...
```

The CLI loads `.alea.yaml`, runs analyzers from `config.analyzers.enabled` against the changed files, and writes the JSON report. Human-readable output goes to stdout.

The CLI's exit code is `0` on pass, `1` on fail. Capture it.

### 5. Run Flutter-level validations

```bash
flutter analyze <each layer path from config> <each test path from config>
flutter test --coverage
```

`flutter analyze` paths come from `config.architecture.layers.*.paths` plus relevant test directories. If `flutter analyze` returns issues, propagate them as `major` issues into the gate report.

### 6. Coverage check

From `coverage/lcov.info` (or wherever `flutter test --coverage` writes), extract coverage for each file in the gate's scope. Apply `config.coverage.thresholds.<layer>`:

- `presentation` layer threshold defaults to 70.
- `infrastructure` to 80.
- `domain` to 95.

(All values from `config.coverage.thresholds.<layer>` — never hardcoded.)

If any file is below threshold, append a `major` issue to the gate report under analyzer `coverage`.

### 7. Apply severity policy and retry

Read the assembled gate report:

- **BLOCKER:** try to auto-fix (move imports, invert dependencies, fix layer violations). Re-run the CLI on the affected file. Retry up to 3 times. If still failing:
  ```
  BLOCKED: <rule> in <file>:<line>
  <message>
  Requires manual intervention. Run /aflow-run-gates <ticket_id> after fixing.
  ```
  Stop with exit-code-equivalent of 1.

- **CRITICAL:** same retry loop (3 attempts). Common fixes: extract complex branches, replace broken asset paths with TODO placeholders, add `fit:` to image widgets, replace emoji-as-icon with Image.asset.

- **MAJOR:** in `guided` mode → ask `Fix or continue? (fix/continue)`. In `semi`/`auto` → log and continue.

- **MINOR:** informational only.

### 7b. High-coupling hub warning (graph-verified, non-blocking)

```bash
aflow graph --ensure-fresh -o .pipeline/graph.json --project-root .
aflow graph-query god-nodes -i .pipeline/graph.json --format json
```

If any file in the gate's changed-file scope appears among the top hubs, append a `minor` informational issue under analyzer `coupling`: `"<file> is a high-coupling hub (degree N) — changes here warrant extra review"`. This never blocks the gate; it is a signal for the human reviewer.

### 8. Display summary

```
══════════════════════════════════════════════
Gate <gate>: <ticket_id>
Status: PASSED ✓ | FAILED ✗
══════════════════════════════════════════════
  ✓ layer_integrity        — 0 issues
  ✓ widget_purity          — 0 issues
  ✗ visual_fidelity        — 2 issues
    [BLOCKER] lib/.../foo.dart:42 → button without content
    fix: Add a child Text("...") or Image.asset(...) ...
  ✓ flutter analyze        — 0 issues
  ✓ flutter test           — N tests passed
  ✓ coverage               — <layer>: XX% (threshold YY%)

Total: N issues (B blockers, C criticals, M majors, m minors)
══════════════════════════════════════════════

[PASSED]: Continue to next phase.
[FAILED]: Fix the issues above and re-run /aflow-run-gates <ticket_id>.
```

## What this command MUST NOT do

- ❌ Reimplement analyzer logic. All analysis goes through the CLI.
- ❌ Hardcode coverage thresholds. They come from `config.coverage.thresholds`.
- ❌ Hardcode analyzer names in retry strategies. The CLI returns rule_ids; auto-fix logic dispatches on `rule_id` prefix.
- ❌ Skip schema validation of the gate report. Always validate against [`gate-report.schema.yaml`](../../contracts/schemas/gate-report.schema.yaml) before claiming success.
