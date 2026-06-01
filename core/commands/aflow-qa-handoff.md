---
description: Generates the QA handoff document combining automated coverage with manual steps from functional validation, so QA can verify the feature or bugfix end-to-end.
---
# `/aflow-qa-handoff` — QA Handoff

Generates the document QA reads to verify the feature/bugfix manually. Combines automated coverage with the manual steps surfaced by `/aflow-validate-functional`.

## Usage

```
/aflow-qa-handoff DEV-XXXX
```

## Steps

### 1. Load config + run artifacts

1. Read `.alea.yaml`; validate.
2. Read `.pipeline/runs/<ticket_id>/analysis.json`, `spec.json` (feature only), `validation_report.json`, and every `<layer>_impl.md` (or `implementation.md`).
3. Verify the MR was created (check `final_report.json::mr_url` set by `/aflow-create-mr`).

### 2. Build the handoff document

Write `.pipeline/runs/<ticket_id>/qa_handoff.md`:

```markdown
# QA Handoff: <ticket_id> — <title>

**Type:** <feature | bugfix>
**MR:** <mr_url>
**Branch:** <branch>
**Tester time estimate:** <derived from manual_steps count: 5 min × steps>

## What was built

<feature_description | bug_description>

## Automated test coverage

| Criterion | Test |
|---|---|
<for each entry in validation_report.criteria:>
| <criterion text> | <covered_by> — `<result>` |

## Manual verification needed

<for each entry in validation_report.manual_steps:>

### <criterion>

<for each step:>
- <step>

**Expected:** <last step describes the expected outcome>

## What changed (files)

<from union of files_changed in all impl markdowns, grouped by layer per config.architecture.layers>

## Test data

<if analysis.json had attachments[*] of kind document/image with description "test data": list here>
<otherwise: "No test data attached to the ticket — use staging defaults.">

## How to run locally

```bash
git checkout <branch>
flutter pub get
flutter run -d <device>          # consumer's preferred device
```

If the consumer's `.alea.yaml` declared run scripts (`config.docs.run_script` or similar), reference them here.

## Rollback

If a regression is found:
```bash
git checkout <rollback_tag from metrics.json>
```
The rollback tag is `pipeline-<ticket_id>-start` (created by `/aflow-pipeline` at run start).

## QA sign-off checklist

- [ ] All automated tests pass on the latest commit
- [ ] Manual steps above completed without surprises
- [ ] No console errors in the device log during the run
- [ ] Performance acceptable (no jank on target devices)
- [ ] Accessibility (if applicable to the change)
```

### 3. Display summary

```
══════════════════════════════════════════════
QA Handoff: <ticket_id>
══════════════════════════════════════════════
Automated criteria: <N> covered
Manual steps:       <N>
Files in scope:     <N>
Estimated QA time:  <N> minutes

Saved to .pipeline/runs/<ticket_id>/qa_handoff.md
══════════════════════════════════════════════

Paste the file's contents into the ticket comment OR attach it
(per consumer's QA workflow).
```

## What this command MUST NOT do

- ❌ Embed the full source diff. The MR URL is the authoritative source.
- ❌ Recommend test data the ticket didn't mention. Reference only what's in `analysis.json::attachments`.
- ❌ Speculate about device-specific behavior. Test instructions are generic; consumer's QA picks devices.
