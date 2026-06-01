---
description: Independent manual code review pass after gates pass, catching semantic correctness, naming clarity, dead code, and design smell that automated analyzers miss.
---
# `/aflow-code-review` — Manual Code Review Pass

Independent review of the implemented code. Runs after `/aflow-run-gates` passes but before `/aflow-create-mr`. Catches issues automated analyzers miss: semantic correctness, naming clarity, dead code, design smell.

## Usage

```
/aflow-code-review DEV-XXXX
```

## Steps

### 1. Load config + run artifacts

1. Read `.alea.yaml`; validate.
2. Read every `<layer>_impl.md` (or `implementation.md`). Collect `files_changed`.
3. Read `spec.json` (feature) or `analysis.json` (bugfix).

### 2. Review checklist (per file)

For each file in `files_changed`:

#### Domain layer (under `config.architecture.layers.domain.paths`)

- Entities use `final` fields + `const` constructors.
- `copyWith` preserves immutability (no mutation, returns new instance).
- `==` and `hashCode` are correctly overridden together (or both absent).
- Value objects' factory constructors validate AND have a private default constructor.
- No `dart:io`, `package:flutter`, or any infrastructure/presentation imports.
- Repository contracts are `abstract` / `abstract interface class`.

#### Infrastructure layer

- DTOs have explicit `fromJson` AND `toJson` (no `@JsonSerializable` codegen).
- `toEntity` / `fromDomain` are inverses where both exist.
- Repository implementations declare dependencies via constructor.
- Endpoint paths match the spec.
- No imports from the consumer's presentation layer.

#### Presentation layer

- `Notifier<XxxState>` (sync) or `AsyncNotifier<X>` (async). Never `@riverpod`.
- State class is plain Dart with `copyWith`. No sealed/freezed.
- `ref.watch` used ONLY in `build()`; methods use `ref.read`.
- Every `await` followed by `if (!ref.mounted) return;` before touching state.
- Every NDS-mapped element matches `widget_map.yaml`'s decision (USE_AS_IS imports, ADAPT passes the recommended params, CREATE_NEW exists at the recommended placement).
- Theme tokens used per `color_map.yaml`. No raw hex literals where `color_map.yaml` resolved a token.
- Every dynamic `Text` has `maxLines` + `overflow`.
- Every image-family widget has `fit:`.

#### Bugfix-specific

- Diff is the smallest possible to satisfy the success criteria.
- No formatting churn (preserve existing style).
- Regression test exists and is named `'fixes <ticket_id>: ...'`.
- No new dependencies added (escalate instead).

### 3. Common smells (call out without auto-fixing)

- Unused imports, dead functions, dead branches.
- Naming: variables like `data`, `value`, `result` when a domain term exists.
- Magic numbers that should be named constants.
- Catch blocks that swallow exceptions.
- Async functions returning `Future<void>` that should return data.

### 4. Write `code_review.json`

```json
{
  "ticket_id": "<ticket_id>",
  "timestamp": "<ISO8601>",
  "files_reviewed": <N>,
  "approved": true,
  "issues": [
    {
      "file": "<path>",
      "line": <int>,
      "severity": "blocker | critical | major | minor",
      "category": "<domain | infrastructure | presentation | bugfix | smell>",
      "message": "<one-line>",
      "suggested_fix": "<one-line>"
    }
  ]
}
```

`approved` is true iff there are no `blocker` or `critical` issues.

### 4b. Validate the report

Run `aflow validate-artifact --schema code_review --artifact <run_dir>/code_review.json`. If it exits non-zero, fix the report before continuing.

### 5. Display summary

```
══════════════════════════════════════════════
Code Review: <ticket_id>
══════════════════════════════════════════════
Files reviewed:  <N>
Approved:        ✓ | ✗

Issues by severity:
  Blocker:  <N>
  Critical: <N>
  Major:    <N>
  Minor:    <N>

Top findings:
  <list 5 most important — file:line + severity + message>
══════════════════════════════════════════════

Saved to .pipeline/runs/<ticket_id>/code_review.json
[Approved]: Proceed to /aflow-create-mr.
[Not approved]: Address blocker/critical issues and re-run /aflow-code-review.
```

## What this command does NOT do

- ❌ Modify code. Review only — issues are reported.
- ❌ Replace `/aflow-run-gates`. Gates check static rules; this is the human-flavored review.
- ❌ Run any tests or analyzers. Reads the impl files and the changed Dart sources only.
- ❌ Decide MR approval. That's the human reviewer's call. This is one input among many.
