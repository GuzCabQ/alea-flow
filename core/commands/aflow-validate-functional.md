---
description: Walks every success criterion from analysis.json, derives concrete test scenarios, and verifies behavior end-to-end via integration and widget tests as the last gate before MR creation.
---
# `/aflow-validate-functional` — Functional Validation

Walks every `success_criteria` from the analysis, derives concrete test scenarios, and verifies behavior end-to-end via integration/widget tests. Last gate before MR.

## Usage

```
/aflow-validate-functional DEV-XXXX
```

## Steps

### 1. Load config + run artifacts

1. Read `.alea.yaml`; validate.
2. Read `.pipeline/runs/<ticket_id>/analysis.json`, `spec.json`, `final_report.json` (when present).
3. Verify `spec.approved: true` AND `final_report.passed: true` (or skip the final-report check for bugfix runs).

### 2. Derive scenarios

For every entry in `analysis.json::success_criteria`:

1. Translate to a concrete given-when-then scenario when one isn't already in `analysis.json::acceptance_tests`.
2. Identify which existing widget test(s) cover it. Use the `files_changed` lists from `<layer>_impl.md` to find candidate test files.
3. Mark scenarios as `covered` (has a passing test that asserts the criterion) or `uncovered`.

### 3. Generate missing scenarios

For uncovered scenarios, generate widget tests at the consumer's test path mirroring `config.testing.fakes_path` conventions:

- Override repository providers per `config.testing.override_target`.
- AAA pattern when `config.testing.pattern == 'aaa'`.
- One test per criterion. Test name: `'criterion <N>: <criterion text trimmed to 80 chars>'`.

Write these new tests to the same file as the corresponding feature/page tests when possible.

### 4. Run the test suite

```bash
flutter test --reporter=json > <run_dir>/test_run.json
```

Parse the JSON output. For each criterion, find its matching test and verify the result.

### 5. Manual verification fallback

If a criterion cannot be automated (visual-only / multi-device / requires real backend), append it to `validation_report.json::manual_steps[]` with a step-by-step procedure for QA. These do NOT fail the gate; they're surfaced to `/aflow-qa-handoff`.

### 6. Write `validation_report.json`

```json
{
  "ticket_id": "<ticket_id>",
  "overall_passed": true,
  "timestamp": "<ISO8601>",
  "criteria": [
    {
      "text": "<criterion>",
      "covered_by": "<test file:test name>",
      "result": "passed | failed | manual",
      "evidence": "<short note or test ID>"
    }
  ],
  "manual_steps": [
    { "criterion": "<text>", "steps": ["<step 1>", "<step 2>"] }
  ],
  "tests_added": ["<path>"],
  "tests_failing": []
}
```

`overall_passed` is true iff every criterion has `result: passed` OR `result: manual` AND `tests_failing` is empty.

### 6b. Validate the report

Run `aflow validate-artifact --schema validation_report --artifact <run_dir>/validation_report.json`. If it exits non-zero, fix the report before continuing.

### 7. Display summary

```
══════════════════════════════════════════════
Functional Validation: <ticket_id>
══════════════════════════════════════════════
Status: PASSED ✓ | FAILED ✗

Criteria coverage:
  ✓ <criterion 1> — <test file:test name>
  ✓ <criterion 2> — <test file:test name>
  ⚠ <criterion 3> — manual verification required (see manual_steps)
  ✗ <criterion 4> — test failing: <reason>

Tests added in this validation pass: <N>
Tests failing:                       <N>
Manual steps for QA:                 <N>
══════════════════════════════════════════════

Saved to .pipeline/runs/<ticket_id>/validation_report.json
[PASSED]: Continue to /aflow-create-mr.
[FAILED]: Fix failing tests and re-run /aflow-validate-functional.
```

## What this command MUST NOT do

- ❌ Modify production code. It only adds tests.
- ❌ Mark a criterion as `passed` without a corresponding asserting test.
- ❌ Add tests that don't actually verify the criterion they're labeled for.
