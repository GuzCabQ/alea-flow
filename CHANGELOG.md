# Changelog

All notable changes to `alea_flow` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-05-24

Initial release of `alea_flow` — the Flutter pipeline tool from
the ALEA (AI-Led Engineering Assistant) suite. Drives any Flutter project
from a ticket to a merge request through a deterministic, config-driven
pipeline.

### Added

#### CLI (`aflow`)

Seven subcommands compiled to a single ~10MB native binary via
`tool/compile.sh`:

- `aflow init` — bootstrap a project skeleton (Flutter app) or a feature
  package (Dart-only, for monorepos). Configurable state-management style;
  idempotent with `--dry-run` and `--force`.
- `aflow analyze` — run all analyzers for a configured gate and emit a
  gate report (human or JSON).
- `aflow match` — resolve a hex color / typography / spacing value against
  the consumer's design token catalog.
- `aflow scaffold` — generate a feature scaffold via the configured
  code-gen adapter.
- `aflow inventory` — scan widget classes and emit a JSON inventory.
- `aflow journal` — inspect a run's JSONL journal.
- `aflow context` — build (or reuse) a cacheable context-packet for the
  next LLM call (TTL + hash invalidation).

#### Analyzers (16)

`layer_integrity`, `package_boundary`, `visual_fidelity`, `code_complexity`,
`build_method_complexity`, `flutter_antipatterns`, `widget_purity`,
`widget_inventory`, `wiring_cohesion`, `state_mgmt`, `testing`, `security`,
`performance`, `project_conventions`, `dry_detection`, `design_principles`.

Each emits structured `AnalysisIssue` with severity
(`minor` / `major` / `critical` / `blocker`), `ruleId`, and a
`suggestedFix` string.

#### Adapter families

- **Ticket sources** — `asana`, `file`.
- **Design sources** — `figma`, `image` (stub), `markup` (stub).
- **Code generators** — `riverpod_manual`, `bloc`.
- **Token catalog** — `dart_source` (AST-parses `static const Color`
  classes), `json` (Style Dictionary).

Adding a new adapter means a new folder under `adapters/<family>/<name>/`
implementing the family's contract. Core and other adapters are not
touched.

#### Architecture

- **Hexagonal (Ports & Adapters).** Core depends on `contracts/`, never on
  a specific adapter. Selection happens by name lookup against
  `.alea.yaml` at runtime.
- **Self-enforcing.** `PackageBoundaryAnalyzer` runs against the
  `alea_flow` tree itself in CI via
  `tool/check_alea_boundaries.dart`.
- **Pure matching library** (`lib/matching.dart`) — ΔE CIE2000, Jaccard,
  fuzzy score, snap-to-steps. No I/O, importable standalone.
- **Idempotent code generation** with rollback via `ScaffoldExecutor`.

#### Monorepo support (ADR-0011)

- `aflow init --template feature` scaffolds a Dart feature package whose
  token catalog points at a sibling `design_system/` package.
- `theme.token_catalog.source` accepts paths outside the project root
  (e.g. `../design_system/lib/`).
- Clear `ProjectConfigException` at config-load time when an external
  source path does not exist.

#### Configuration & docs

- Consumer config schema:
  [`contracts/schemas/project-config.schema.yaml`](contracts/schemas/project-config.schema.yaml).
- Example consumer config:
  [`config/examples/sample_app.yaml`](config/examples/sample_app.yaml).
- Eleven Architectural Decision Records under
  [`docs/adr/`](docs/adr/).
- Visual walkthrough with mermaid diagrams:
  [`docs/PROJECT_WALKTHROUGH.md`](docs/PROJECT_WALKTHROUGH.md).
- Step-by-step onboarding:
  [`docs/CONSUMER_INTEGRATION.md`](docs/CONSUMER_INTEGRATION.md).

### Tested

- 320 unit and smoke tests across analyzers, adapters, resolvers,
  scaffolding, inventory, and the CLI runner.
- All package boundary invariants self-enforced (0 violations).

[Unreleased]: https://github.com/GuzCabQ/alea-flow/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/GuzCabQ/alea-flow/releases/tag/v0.1.0
