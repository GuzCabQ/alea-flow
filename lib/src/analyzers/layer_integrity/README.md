# `layer_integrity` analyzer

Enforces the layered architecture declared by the consumer project in `.alea.yaml::architecture.layers`. Detects forbidden cross-layer imports between Dart source files.

## What it checks

For every Dart file that falls under one of the configured layer paths, the analyzer parses its `import` directives and flags any whose canonical URI starts with a prefix listed in that layer's `forbid_imports`.

## Required config

```yaml
architecture:
  layers:
    <layer_name>:
      paths: [<dir>, ...]          # required — file→layer matching
      may_import: [<layer>, ...]   # documentation (not enforced by this analyzer)
      forbid_imports:              # the actual rules
        - "<uri prefix>"
        - "<uri prefix>"
```

`forbid_imports` is the source of truth. `may_import` is human-facing documentation that other tools (docs, IDE hints) may consult; this analyzer ignores it.

## Algorithm

1. **Bucket files by layer.** Each file's project-relative path is matched against `layers[*].paths`. Matching is prefix-based with trailing-slash enforcement, so `lib/src/domain/` does NOT match `lib/src/domain_helpers/foo.dart`. Files not in any layer are skipped.
2. **Parse imports** via `package:analyzer`'s AST.
3. **Canonicalize each import URI:**
   - `dart:...` and `package:...` URIs pass through unchanged.
   - Relative imports are resolved against the importing file's directory, then rewritten to `package:<own_package>/...` when they land under `lib/`.
4. **Match against `forbid_imports`.** If a canonical URI starts with any forbidden prefix, emit one `blocker` issue. Stop checking that directive (one issue per `import` line, never duplicates).

## Severity

`Severity.blocker` always. Consumers wanting to demote use `.alea.yaml::analyzers.severity_overrides.layer_integrity: <severity>`; the runner applies the override after the analyzer emits — not here.

## Issue shape

Each issue emitted matches `contracts/schemas/gate-report.schema.yaml::AnalysisIssue`:

| Field | Example |
|---|---|
| `file` | `lib/src/domain/entities/foo.dart` (project-relative) |
| `line` | `5` (line of the `import` directive) |
| `rule` | `Layer integrity: domain must not import package:my_app/src/infrastructure/` |
| `rule_id` | `layer_integrity/domain_imports_package_my_app_src_infrastructure` |
| `message` | `domain must not import from forbidden layer: package:my_app/src/infrastructure/foo.dart` |
| `suggested_fix` | `Move the imported symbol to domain, or invert the dependency via an interface owned by domain.` |
| `severity` | `blocker` |

## Parity with the original analyzer

Source: [`tools/pipeline/lib/src/analyzers/layer_integrity_analyzer.dart`](../../../../../tools/pipeline/lib/src/analyzers/layer_integrity_analyzer.dart).

The original hardcodes:
- Package name `my_app`
- Layer enum `{domain, infrastructure, presentation}`
- Path segment pattern `src/<layer>/`
- Violation matrix: `domain → {infra, presentation}` blocked, `infra → presentation` blocked, `presentation → *` allowed

The port produces equivalent output for the first two rows of the violation matrix when given the equivalent config.

**Intentional improvement over the original (closes a known gap):**
The original analyzer's matrix allowed `presentation → infrastructure`, but [CLAUDE.md](../../../../../CLAUDE.md) of the existing pipeline states the actual project rule: *"presentation consumes domain only"*. The new analyzer enforces this whenever the consumer config declares it — i.e. when `architecture.layers.presentation.forbid_imports` contains the infrastructure prefix. The example config in [`config/examples/my_app.yaml`](../../../../config/examples/my_app.yaml) sets this. Consumers who want the original's lax behavior can leave `presentation.forbid_imports` empty.

This is a behavior change. Step 11 of [MIGRATION.md](../../../../MIGRATION.md) (smoke test on the reference consumer) is expected to surface extra `presentation → infrastructure` issues that the original missed. Those issues are real architectural violations; resolving them is a separate task tracked under `my_app` cleanup, not under the migration itself.

For the rows where the analyzers agree exactly:

```yaml
project:
  package_name: my_app
architecture:
  layers:
    domain:
      paths: [lib/src/domain/]
      forbid_imports:
        - "package:my_app/src/infrastructure/"
        - "package:my_app/src/presentation/"
    infrastructure:
      paths: [lib/src/infrastructure/]
      forbid_imports:
        - "package:my_app/src/presentation/"
    presentation:
      paths: [lib/src/presentation/]
      forbid_imports: []           # asymmetric: presentation can import domain
```

The parity criterion enforced in [`../../../../test/analyzers/layer_integrity/analyzer_test.dart`](../../../../test/analyzers/layer_integrity/analyzer_test.dart) is: for every file in the reference consumer's `lib/`, the set of `(file, line)` pairs emitted by the port equals the set emitted by the original.

## What this analyzer does NOT do

- Does NOT validate that `may_import` is consistent with `forbid_imports`. They're two views of the same rule; the analyzer trusts `forbid_imports`.
- Does NOT check transitive imports. If layer A imports a public symbol from layer B, and that symbol internally imports forbidden layer C, this analyzer does not flag A.
- Does NOT enforce file naming or class naming. Those belong to other analyzers (`project_conventions`).
- Does NOT analyze relative imports that escape `lib/` (e.g. `import '../../tool/foo.dart'`). Out of scope — those almost never exist in real Flutter projects.
