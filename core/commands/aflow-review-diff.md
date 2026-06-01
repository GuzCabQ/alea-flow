---
description: Reviews uncommitted or branch changes via git diff without requiring a pipeline run directory, running all checks that do not depend on spec.json or analysis.json.
---
# `/aflow-review-diff` — Standalone review over `git diff` (no run directory)

Reviews uncommitted or branch changes without a pipeline run. For the developer who finished a ticket by hand and wants the review, not the full `/aflow-pipeline`. Runs every check that does not require `spec.json`/`analysis.json`, and is explicit about what it cannot verify without them.

## Usage

```
/aflow-review-diff [<base-ref>]
```

`<base-ref>` defaults to `HEAD` (review uncommitted changes). Pass a base like `main` to review a whole branch (`git diff main...HEAD`).

## Steps

### 1. Load config and resolve the changed files

1. Read `.alea.yaml` from the project root; validate. If missing → `Error: .alea.yaml not found. Run /aflow-complete-config or aflow init --template config first.` Stop.
2. Resolve changed `.dart` files:
   ```bash
   git diff --name-only <base-ref> -- '*.dart'        # default base-ref = HEAD
   ```
   If empty → `No changed .dart files vs <base-ref>. Nothing to review.` Stop.

### 2. Structural gates (no spec needed)

```bash
aflow analyze \
  --project-root . \
  --gate full \
  --format human \
  --changed-files <file1> --changed-files <file2> ...
```

Exit `0` = pass, `1` = issues. Report the analyzer findings as-is.

### 3. Graph-grounded regression check (no spec needed)

```bash
aflow graph --ensure-fresh -o .pipeline/graph.json --project-root .
# For each changed file:
aflow graph-query impact <changed-file> -i .pipeline/graph.json --format json
```

Any `impacted` consumer NOT in the changed-file set is a potential regression — a dependent of changed code that was not touched or re-tested. List them as `major` warnings.

### 4. Spec-independent code review (the subset of `/aflow-code-review` that needs no spec)

Apply, per changed file, only the checklist items that judge the code itself — NOT the ones that compare against a spec/NDS:

**Domain layer** (`config.architecture.layers.<domain>.paths`):
- `final` fields + `const` constructors; `copyWith` preserves immutability; `==`/`hashCode` overridden together or both absent; value-object factories validate with a private default ctor; no `dart:io`/`package:flutter`/infra/presentation imports; repository contracts are `abstract`.

**Infrastructure layer:**
- DTOs have explicit `fromJson` AND `toJson` (no codegen); `toEntity`/`fromDomain` are inverses; repository impls take deps via constructor; no presentation imports.

**Presentation layer:**
- `Notifier`/`AsyncNotifier` (never `@riverpod`); state class plain Dart with `copyWith`; `ref.watch` only in `build()`, methods use `ref.read`; every `await` followed by `if (!ref.mounted) return;`; every dynamic `Text` has `maxLines` + `overflow`; every image-family widget has `fit:`.

**Common smells (all layers):**
- Unused imports, dead functions/branches; vague names (`data`/`value`/`result` where a domain term exists); magic numbers; swallowed exceptions; `Future<void>` that should return data.

### 5. State what was NOT checked (honesty)

Print explicitly:

```
NOT verified (needs a pipeline run with spec.json / analysis.json):
  - success-criteria coverage (no ticket spec available)
  - spec ↔ implementation drift
  - NDS/widget_map/color_map conformance and endpoint-vs-spec matching
Run the full /aflow-pipeline if you need these.
```

### 6. Display summary

```
══════════════════════════════════════════════
Review (diff vs <base-ref>): <N> files
══════════════════════════════════════════════
Structural gates: PASSED ✓ | <N> issues
Regression (graph): <N> untouched consumers
Code review:        <N> findings (B/C/M/m)
NOT verified:       success-criteria, spec-drift, NDS conformance
══════════════════════════════════════════════
```

## What this command MUST NOT do

- ❌ Fabricate `.pipeline/runs/<id>/` artifacts to unlock the pipeline-coupled commands.
- ❌ Claim success-criteria coverage or spec-drift results — it has no spec. Say so (step 5).
- ❌ Modify code. Review only.
- ❌ Re-implement analyzer logic. All structural analysis goes through `aflow analyze`.
