# `config/` — Consumer Configuration

This folder defines the contract a consuming Flutter project signs by adding `.alea.yaml` to its repo root.

## What lives here

- `examples/` — concrete `.alea.yaml` files for real projects, kept as reference and used as fixtures for tests.
  - `my_app.yaml` — the reference consumer's configuration. Equivalent to the hardcoded values in the current pipeline.
- (Schema lives in [`../contracts/schemas/project-config.schema.yaml`](../contracts/schemas/project-config.schema.yaml).)

## How consumers use it

1. Copy `examples/my_app.yaml` (or any other example closest to your project's stack) to your project root as `.alea.yaml`.
2. Edit values to match your project: package name, layer paths, state-management style, ticket adapter, design source, brand colors, coverage thresholds.
3. Run `/pipeline DEV-XXXX` from your project root.

ALEA validates `.alea.yaml` against `project-config.schema.yaml` on every run. Validation errors stop execution at Gate 0 with a clear message.

## What is configurable vs hardcoded

Everything that varies between Flutter projects must be in `.alea.yaml`:

- Project identity (package name, pubspec path).
- Layer structure (paths, allowed imports between layers).
- State management style (selects code-gen adapter).
- Routing package and router file location.
- Theme location, brand colors, fonts.
- Testing conventions (framework, fakes path, AAA, override targets, prefer-fakes-over-mocks).
- Coverage thresholds per layer.
- Ticket system (selects ticket-source adapter).
- Design source preferences (selects design-source adapter; figma circuit-breaker thresholds).
- MR policy (single-commit-amend vs others; pre-push commands).
- Pipeline operational settings (cost limits, modes, unreliable-flag thresholds).

What stays hardcoded in the package:

- Slash command structure (resume semantics, artifact filenames, state machine).
- Contract schemas.
- Adapter selection mechanism.
- Cross-cutting policies that apply to every consumer (PII sanitization patterns, asset-existence check, emoji prohibition for figma source).

## Adding a new example

1. Create `examples/<project_slug>.yaml` matching `project-config.schema.yaml`.
2. Include comments explaining any non-obvious choices.
3. Use the example as a fixture for adapter tests if it covers a new shape (e.g. first Bloc-based project, first Linear project).
