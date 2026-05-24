# `contracts/` — Cross-Process Schemas

This folder holds the YAML schemas for artifacts that travel between processes — `.pipeline/runs/<id>/*.json` and `*.yaml` files produced by one phase and consumed by another. These schemas are language-agnostic specifications: any tool (markdown command, Dart code, Python helper, IDE plugin) can validate against them.

> **Looking for the Dart contract interfaces?** They moved to [`../lib/src/contracts/`](../lib/src/contracts/) to follow Dart package convention. They are exported from the package barrel at [`../lib/alea.dart`](../lib/alea.dart). Each Dart contract maps to one schema family here (e.g. [`lib/src/contracts/analyzer.dart`](../lib/src/contracts/analyzer.dart) ↔ [`schemas/gate-report.schema.yaml`](schemas/gate-report.schema.yaml)).

## Why schemas are at the top level (not under `lib/`)

Schemas are read by:

- Markdown commands under [`../core/commands/`](../core/) at runtime.
- Markdown adapter prompts under [`../adapters/*/*/adapter.md`](../adapters/).
- Dart code under [`../lib/src/`](../lib/).
- Python tooling (rare, but allowed under [`../adapters/design_source/_common/scripts/`](../adapters/design_source/_common/scripts/)).
- External validators (CI, IDE plugins).

If they lived under `lib/`, only Dart-package-aware tooling could find them. At the top level, they're discoverable by anything.

## Stability versioning

Each schema declares `contract_version: <semver>` at its head and `contract_status: draft | stable`. While in `draft`, breaking changes do not require a major bump. Once `stable`, every breaking change requires a major bump and a corresponding entry in `../CHANGELOG.md` if it affects how consumers write `.alea.yaml`.

## Folders

| File | Producer | Consumer(s) |
|---|---|---|
| [`schemas/analysis.schema.yaml`](schemas/analysis.schema.yaml) | `core/analyze-ticket` | `design-feature`, `implement-bugfix`, `validate-functional`, `review-feature` |
| [`schemas/spec.schema.yaml`](schemas/spec.schema.yaml) | `core/design-feature` | `implement-*`, `review-feature`, `validate-functional` |
| [`schemas/nds.schema.yaml`](schemas/nds.schema.yaml) | design-source adapters | code-gen adapters, `visual_fidelity` analyzer |
| [`schemas/gate-report.schema.yaml`](schemas/gate-report.schema.yaml) | `core/run-gates` | `review-feature`, `create-mr`, `pipeline-feedback` |
| [`schemas/project-config.schema.yaml`](schemas/project-config.schema.yaml) | (consumer's `.alea.yaml`) | every module |

## What does NOT live here

- Dart interfaces (those are in `../lib/src/contracts/`).
- Implementation. Schemas are interface and type declarations only.
- Anything project-specific. Schemas describe shapes that ALL consumers conform to.
- Validators. The Dart-side parser/validator for these schemas lives in `../lib/src/core/config/loader.dart` (TBD).
