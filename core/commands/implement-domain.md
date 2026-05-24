# `/implement-domain` — Implement Domain Layer

Generates the domain layer for the feature. Reads `spec.json::domain`, dispatches to the configured code-gen adapter, writes pure-Dart entities + value objects + repository contracts + tests.

## Usage

```
/implement-domain DEV-XXXX
```

## Steps

### 1. Load config and spec

1. Read `.alea.yaml`; validate.
2. Read `.pipeline/runs/<ticket_id>/spec.json`. Verify `type: feature` AND `approved: true`. If not:
   ```
   Error: approved spec not found for <ticket_id>.
   Run /design-feature <ticket_id> and approve at Gate 0 first.
   ```
   Stop.

### 2. Resolve code-gen adapter

Look up `adapters/code_gen/<config.state_management.style>/`. If the folder doesn't exist:
```
Error: code-gen adapter "<style>" not found at adapters/code_gen/<style>/.
Either install the adapter or change `state_management.style` in .alea.yaml.
```
Stop.

### 3. Dispatch to the adapter

Follow ALL instructions in [`adapters/code_gen/<style>/adapter.md`](../../adapters/code_gen/) with `layer: domain`. The adapter routes to `layers/domain.md`, which:

- Reads `spec.domain.{entities, value_objects, repository_contracts}`.
- Writes files under `config.architecture.layers.domain.paths`.
- Generates unit tests under the consumer's test path.
- Returns a `CodeGenResult` listing created/modified files + metrics.

### 4. Run quality validations

```bash
flutter analyze <files from CodeGenResult.createdFiles + modifiedFiles>
dart format --set-exit-if-changed <same paths>
flutter test <test paths from CodeGenResult> --coverage
```

If any validation fails: propagate the error, do NOT proceed to step 5.

Coverage threshold: `config.coverage.thresholds.domain` (the reference consumer default: 95).

### 5. Write `domain_impl.md`

The code-gen adapter already produces this file. Verify it exists at `<run_dir>/domain_impl.md` and contains the `## files_changed` machine-readable section (one path per line). `/pipeline` reads this section to stage commits.

### 6. Display summary

```
══════════════════════════════════════════════
Domain Implementation: <ticket_id>
══════════════════════════════════════════════
Adapter:        <style>
Entities:       <N> created
Value objects:  <N> created
Contracts:      <N> created
Tests:          <N> written

✓ flutter analyze — 0 issues
✓ dart format    — clean
✓ flutter test   — <N> tests, coverage <XX>%
══════════════════════════════════════════════

Saved to .pipeline/runs/<ticket_id>/domain_impl.md
Next: /run-gates <ticket_id> --gate domain  OR  /implement-infrastructure <ticket_id>
```

## What this command MUST NOT do

- ❌ Write Dart code directly. The code-gen adapter is the only emitter.
- ❌ Modify the spec.
- ❌ Modify the consumer's `pubspec.yaml`.
- ❌ Skip validations. If a validation fails, the phase has not completed.
