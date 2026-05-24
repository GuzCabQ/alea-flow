# Bugfix Layer Generation (Riverpod Manual)

Targeted edits to existing files. Unlike feature layers which generate code from a spec, the bugfix flow modifies existing implementations to fix a defect described in `analysis.json`.

## Inputs

From the `CodeGenRequest` (with `layer: bugfix`):

- `spec` — null (bugfix tickets skip `/design-feature` and therefore have no spec).
- The slash command reads `.pipeline/runs/<ticket_id>/analysis.json` directly:
  - `bug_description`, `root_cause_hypothesis`, `affected_layers`, `affected_files`, `success_criteria`.
- `config` — full `ProjectConfig`.

## Strategy

The bugfix flow has three sub-phases:

1. **Confirm root cause** — read every file in `affected_files`. Verify the hypothesis. If it doesn't match what's in code, refine before changing anything.
2. **Apply minimal edits** — change only what the fix requires. No refactors, no "while we're here" cleanup. The bugfix flow is about the smallest possible diff.
3. **Regression-test** — write or extend tests so the bug cannot return silently.

## Step 1 — Confirm root cause

For each file in `analysis.json::affected_files`:

1. Read the file.
2. Locate the code path implied by `root_cause_hypothesis`.
3. Trace one of the success criteria through the code and identify the divergence point.

If the hypothesis turns out wrong:

- Write the corrected hypothesis to `<run_directory>/bugfix_investigation.md`.
- Continue to step 2 with the corrected hypothesis.
- Do NOT silently change the hypothesis — preserve both for the reviewer.

If after reading all files the hypothesis cannot be confirmed:

```
Bug cannot be located from analysis. The hypothesis says <X> but the code shows <Y>.
Affected files: <list>
Stop and ask the user to provide more context.
```

Throw `CodeGenException(adapter: "riverpod_manual", layer: bugfix, reason: "root cause not confirmed")`.

## Step 2 — Apply minimal edits

For each change:

- The diff per file should be the smallest possible to satisfy the success criteria.
- Preserve every line of code that isn't directly involved in the bug.
- Preserve formatting, including blank lines around the changed region.
- If a fix requires a small refactor (e.g. extract a method to enable testing), do it — but limit the refactor to the file(s) being edited.

### Riverpod-manual specific bugfixes

Common bug patterns and the canonical fix:

| Symptom | Likely cause | Fix |
|---|---|---|
| State doesn't update after an action | Missing `ref.mounted` check after `await` | Add `if (!ref.mounted) return;` before the `state = ...` line |
| Widget rebuilds infinitely | `ref.watch` inside a method (not `build`) | Replace with `ref.read` |
| State is stale on re-entry to a screen | `Notifier.build()` doesn't reload | Add `unawaited(_load())` to `build()` or invoke `ref.refresh(provider)` on screen entry |
| Test fails with "notifier not mounted" | Widget test overrides the notifier instead of the repository | Change override to `repositoryProvider.overrideWithValue(FakeXxxRepository(...))` |
| Build error: "X isn't a subtype of Y" | DTO `fromJson` reads a key with the wrong type | Cast to the expected type; add a defensive null check if the API can omit the field |
| Visual fidelity issue: emoji where icon expected | `Image.asset` path is unknown; fallback emoji was emitted | Locate the asset, replace emoji with the correct `.asset()` call |

When the bug doesn't match any pattern above, apply general debugging discipline:

- Check `ref.mounted` after every `await` in the affected notifier.
- Verify state's `copyWith` is the only path that mutates state.
- Confirm the page handles every status from the notifier's state enum.

## Step 3 — Regression test

For every bug fixed, add ONE test that fails on the buggy version and passes on the fixed version.

Placement:

- Bug in a notifier method → `<test_path>/<feature>/providers/<name>_notifier_test.dart`. Add a test case to the existing group; do not create a new file unless the group doesn't exist yet.
- Bug in a page's state handling → `<test_path>/<feature>/pages/<name>_page_test.dart`.
- Bug in a DTO mapping → `<test_path>/<feature>/dtos/<name>_test.dart`. Include the exact JSON payload that triggered the bug.
- Bug in a value object factory → `<test_path>/<feature>/value_objects/<name>_test.dart`.

Test naming: `'fixes <ticket_id>: <one-line description>'`. Future readers grep the ticket ID and find the regression.

## Step 4 — Document and report

Write `<run_directory>/implementation.md` (bugfix runs use `implementation.md`, not a per-layer name):

```markdown
# Bugfix Implementation: <ticket_id>

## Root Cause (confirmed)
<the verified hypothesis>

## Hypothesis Correction (if applicable)
- Original: <original hypothesis from analysis.json>
- Corrected: <what was actually wrong>

## Files Changed
- <path> — <one-line description of the change>

## Edits Per File
- <path>
  - Removed: <N> lines
  - Added: <N> lines
  - Diff summary: <short prose>

## Regression Tests Added
- <test path> — <test name>

## Manual QA Steps (when automated test is insufficient)
- <one-line steps for QA to verify>

## files_changed
<one path per line>

## metrics
- files_modified: <N>
- lines_added: <N>
- lines_removed: <N>
- regression_tests_added: <N>
- hypothesis_was_correct: <bool>
```

## CodeGenResult

Return:

```
CodeGenResult(
  createdFiles: <new files only — usually just test files>,
  modifiedFiles: <every file edited>,
  reportPath: <run_directory>/implementation.md,
  metrics: { ... from the report ... },
)
```

## Hard rules

- No refactor beyond what the fix requires.
- No formatting churn — preserve existing style EXACTLY.
- No new dependencies. If the fix seems to need a new package, escalate to the consumer instead of adding it.
- All [`../../_common/flutter-defaults.md`](../../_common/flutter-defaults.md) rules apply to any new code emitted.
- Riverpod-manual invariants apply to any new state-management code.

## What this prompt MUST NOT do

- ❌ Rewrite a notifier from scratch when a one-line fix would do.
- ❌ Add new entities, DTOs, repositories, providers, or pages. Bugfix flow is for existing code.
- ❌ Change the bug's location to "code I'd rather change". Stay on the affected_files list.
- ❌ Skip the regression test. Every fix gets a test.
- ❌ Touch unrelated files. If you find another bug while fixing this one → document it in the report and ask the consumer to open a new ticket. Don't fix both in one MR.
