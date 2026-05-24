# `/implement-infrastructure` — Implement Infrastructure Layer

Generates the infrastructure layer: DTOs + repository implementations + tests. Reads `spec.json::data`, dispatches to the configured code-gen adapter.

## Usage

```
/implement-infrastructure DEV-XXXX
```

> Renamed from `/implement-infra` to match the layer name in `.alea.yaml::architecture.layers.infrastructure`. The convention is `/implement-<layer_name>` where `<layer_name>` exactly matches a key under `architecture.layers`.

## Steps

### 1. Load config and spec

1. Read `.alea.yaml`; validate.
2. Read `.pipeline/runs/<ticket_id>/spec.json`. Verify `approved: true`. Stop on missing or unapproved.
3. Verify `domain_impl.md` exists. If not, warn and continue (domain files must exist on disk regardless).

### 2. Resolve code-gen adapter

`adapters/code_gen/<config.state_management.style>/`. Stop if not found.

### 3. Dispatch to the adapter

Follow ALL instructions in [`adapters/code_gen/<style>/adapter.md`](../../adapters/code_gen/) with `layer: infrastructure`. The adapter routes to `layers/infrastructure.md`, which:

- Reads `spec.data.{dtos, repositories}` and `spec.domain.entities` (for DTO→entity mappings).
- Writes files under `config.architecture.layers.infrastructure.paths`.
- Generates DTO round-trip tests + repository tests with fake `ApiClient`.
- Returns `CodeGenResult`.

### 4. Run quality validations

```bash
flutter analyze <files from CodeGenResult>
dart format --set-exit-if-changed <same>
flutter test <test paths> --coverage
```

Coverage threshold: `config.coverage.thresholds.infrastructure` (the reference consumer default: 80).

### 5. Write `infrastructure_impl.md`

Produced by the adapter at `<run_dir>/infrastructure_impl.md`. Verify the `## files_changed` section is populated.

### 6. Display summary

```
══════════════════════════════════════════════
Infrastructure Implementation: <ticket_id>
══════════════════════════════════════════════
Adapter:      <style>
DTOs:         <N> created
Repositories: <N> created (implements: <list>)
Endpoints:    <N> mapped
Tests:        <N> written

✓ flutter analyze — 0 issues
✓ dart format    — clean
✓ flutter test   — <N> tests, coverage <XX>%
══════════════════════════════════════════════

Saved to .pipeline/runs/<ticket_id>/infrastructure_impl.md
Next: /run-gates <ticket_id> --gate infrastructure  OR  /implement-presentation <ticket_id>
```

## What this command MUST NOT do

- ❌ Add `package:` dependencies to the consumer's pubspec.
- ❌ Generate code that imports from the consumer's presentation layer (`config.architecture.layers.infrastructure.forbid_imports` enforces).
- ❌ Use codegen annotations (`@JsonSerializable`, `@freezed`) — DTOs are hand-written by the adapter.
