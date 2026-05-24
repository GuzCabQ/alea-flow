# `/merge` — Merge Policy Reference

Documents how ALEA expects the consumer's feature branch to be merged. **This command does not execute the merge** — merging is a human decision (review approvals, CI gates, deployment timing). The command is a checklist.

## Usage

```
/merge DEV-XXXX
```

## Steps

### 1. Load config and verify state

1. Read `.alea.yaml`; validate.
2. Read `.pipeline/runs/<ticket_id>/final_report.json` and `validation_report.json`. Verify `passed: true` / `overall_passed: true`.
3. Verify the MR exists (`final_report.json::mr_url` populated).

### 2. Pre-merge checklist (display, do not execute)

```
══════════════════════════════════════════════
Pre-Merge Checklist: <ticket_id>
══════════════════════════════════════════════
✓ Spec approved at Gate 0
✓ Every layer implemented:
   <list per config.architecture.layers>
✓ Every gate passed (analyzers + flutter analyze + coverage thresholds)
✓ Review: <N>/<N> success criteria met, spec drift = 0
✓ Functional validation: <N> automated + <N> manual covered
✓ MR created: <mr_url>

Pending (human responsibility):
☐ Code review approvals (per consumer's policy)
☐ CI pipeline green
☐ QA sign-off (see <run_dir>/qa_handoff.md)
☐ Stakeholder approval (if required by ticket priority)
══════════════════════════════════════════════
```

### 3. Merge mode reference

Per `config.mr.policy`:

| Policy | Merge command (executed manually) | Notes |
|---|---|---|
| `single-commit-amend` | `gh pr merge --squash` (GitHub) or `glab mr merge --squash` | History stays linear. Original commits subsumed. |
| `single-commit-squash` | Same as above | Same outcome — already squashed locally. |
| `multi-commit` | `gh pr merge --merge` | Preserves the commit chain on main. |
| `custom` | Consumer's documented process | Read `config.docs.merge_doc` if set. |

### 4. Post-merge actions (informational)

After the MR is merged on the platform:

- Remove the rollback tag (now obsolete):
  ```bash
  git tag -d pipeline-<ticket_id>-start
  git push origin :refs/tags/pipeline-<ticket_id>-start
  ```
- Delete the feature branch locally + on origin:
  ```bash
  git branch -d <branch>
  git push origin --delete <branch>
  ```
- Run `/pipeline-feedback <ticket_id>` to capture this run's metrics into `.pipeline/metrics/history.jsonl` (which drives the unreliable-flag circuit breaker in the next run).

### 5. Display summary

```
══════════════════════════════════════════════
Merge Reference: <ticket_id>
══════════════════════════════════════════════
Policy:        <config.mr.policy>
MR:            <mr_url>
Status:        ready to merge | blocked

When merged manually:
  - Run /pipeline-feedback <ticket_id>
  - Delete branch + rollback tag
══════════════════════════════════════════════
```

## What this command MUST NOT do

- ❌ Execute the merge. ALEA does not own merge authority.
- ❌ Force-merge over failing CI.
- ❌ Auto-delete the rollback tag before the merge is confirmed in main.
