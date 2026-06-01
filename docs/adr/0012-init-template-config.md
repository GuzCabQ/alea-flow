# ADR-0012 — `alea init --template config` (`.alea.yaml` from an existing project)

- **Status:** Accepted
- **Date:** 2026-05-25
- **Phase:** 11
- **Related proposal:** [Proposal 0001 — Adoption Flow Overhaul](../proposals/0001-adoption-flow-overhaul.md), Item B (subset).

## Context

[ADR-0011](0011-monorepo-and-bootstrap-strategy.md) introduced `alea init` with two templates — `project` (scaffolds a Flutter app skeleton) and `feature` (scaffolds a monorepo feature package). Both templates assume the consumer is starting from scratch.

Adoption testing surfaced a third, more common case: **the consumer already has a Flutter project** (often non-trivial, with existing tests and architecture) and just needs to add `.alea.yaml` to it. Today this means hand-authoring ~60 lines of YAML by copying the README example and editing every field. That is the single largest barrier to first use and contradicts the project's stated promise — *"from ticket to PR with quality guaranteed, accessible to any Flutter developer"* — recorded in [Proposal 0001](../proposals/0001-adoption-flow-overhaul.md).

The full plan (Proposal 0001 Item B) calls for a diagnostics-driven `init` that consumes a `DiagnoseReport` from a separate `alea diagnose` command. That plan is **deferred** pending the first real consumer, per the v1.0.0 prerequisite in [README.md](../../README.md).

This ADR ships a much smaller subset: a third template, `config`, that reads `pubspec.yaml` and a tiny filesystem scan and writes a starter `.alea.yaml`. No diagnostics. No real layer detection across variants. No interactive prompts. Just enough to remove the "60 lines from scratch" friction.

## Decision

Add `--template config` to the existing `alea init` command. When invoked, it:

1. Reads `pubspec.yaml` from `--output` (default: cwd).
2. Detects only what can be detected unambiguously from a single source.
3. Writes `.alea.yaml` with traceable per-field comments.
4. Emits explicit `# PLACEHOLDER` blocks for everything not detected.

### Detection scope (v1)

Two pure modules under `lib/src/cli/init/`:

**`pubspec_reader.dart`** — parses `pubspec.yaml` and infers:

| Field | Rule |
|---|---|
| `project.package_name` | `pubspec.yaml::name` (required; reader throws if missing) |
| `testing.framework` | `flutter_test` if `flutter` dep is present; else `dart_test` |
| `state_management.style` | `flutter_riverpod`/`riverpod` → `riverpod_manual`; `flutter_bloc`/`bloc` → `bloc`; `provider` → `provider`; `get` → `getx`. Falls back to `null` if none. |
| `routing.package` | `go_router` → `go_router`; `auto_route` → `auto_route`. Falls back to `null`. |

When two state managers coexist (e.g. `flutter_riverpod` + `provider`), the more specific dependency wins by hardcoded order. Disambiguation across genuinely mixed codebases is deferred to Item A of Proposal 0001.

**`layer_scanner.dart`** — filesystem scan, restricted to canonical English Clean Architecture names in two locations:

- `lib/src/<layer>/` (preferred)
- `lib/<layer>/` (fallback)

…for the layers `domain`, `infrastructure`, `presentation`, and `theme`. **Anything else returns `null`**: `data/` (Clean Architecture alternative), Spanish names (`dominio/`, `presentacion/`), feature-first layouts (`lib/features/<x>/<layer>/`), `ui/` instead of `presentation/`, etc.

### Generation contract

The third module, **`config_generator.dart`**, is a pure function: given `PubspecData` and `LayerPaths`, it returns the YAML content as a `String`. The caller writes the file.

Every field in the output carries a comment with one of four origins, listed in the file's header as a marker legend:

| Marker | Meaning |
|---|---|
| `# inferred from <X>` | Auto-detected from pubspec dependency `<X>` |
| `# detected at <path>` | Folder found by filesystem scan |
| `# default` | Industry-standard fallback; consumer may adjust |
| `# PLACEHOLDER` | Could not auto-detect; human action required |

`PLACEHOLDER` blocks include:
- A short explanation of why detection failed.
- Common alternatives in real Flutter projects (e.g. for `infrastructure`: `lib/data/`, `lib/src/data/`, `lib/features/<x>/data/`).
- An explicit pointer to [`docs/proposals/0001-adoption-flow-overhaul.md` § Item A](../proposals/0001-adoption-flow-overhaul.md) — so frequent manual edits surface as evidence to activate full detection.

### Command surface

The existing `alea init` signature is preserved. Only the `--template` allowed list grows:

```
alea init [<package_name>]
  --template, -t   project | feature | config   (default: project)
  --output, -o     Directory to write into (default: cwd)
  --force          Overwrite existing files
  --dry-run        Print the plan, write nothing
  --style          (ignored when --template=config)
  --design-system-path  (ignored when --template=config)
```

Under `--template config`:
- The positional package name is **ignored** (the name comes from `pubspec.yaml`); a `stderr` note is emitted.
- The only file written is `.alea.yaml` at `<output>/.alea.yaml`.
- Validation of the package name uses the same regex as the existing flows (`[a-z][a-z0-9_]*`). Invalid → exit 64.

### Exit codes (config flow)

| Code | Meaning |
|---|---|
| 0 | Success (file written, or `--dry-run` completed) |
| 1 | `pubspec.yaml` missing, unreadable, or malformed |
| 2 | `.alea.yaml` already exists and `--force` not passed |
| 64 | Pubspec name invalid (matches EX_USAGE convention of other flows) |

## Consequences

### Positive

- New consumers reach a working `.alea.yaml` in one command instead of hand-editing 60 lines.
- Every field is traceable: future-self (or a reviewer) can tell apart auto-detected values from defaults and placeholders.
- `PLACEHOLDER` blocks act as evidence-collection points: every manual edit a consumer makes is a signal pointing back to Proposal 0001 Item A, building the case for diagnostics-driven detection.
- Zero impact on existing `--template project` and `--template feature` flows (orthogonal addition).
- The three modules (`pubspec_reader`, `layer_scanner`, `config_generator`) are pure functions, testable with goldens and not coupled to each other.

### Negative

- The 60% of Flutter projects that don't use canonical English layouts (Spanish-named, `data/` instead of `infrastructure/`, feature-first) get more `PLACEHOLDER` blocks than auto-filled fields. The marketing line cannot be *"alea init writes your config"* — it must be *"alea init writes the config it can detect; you fill in the rest"*.
- A consumer who is unfamiliar with Clean Architecture might be confused by `# forbid_imports: ["package:flutter/"]` in the domain layer. Acceptable cost — this is foundational to the architecture alea-flow enforces.
- We are recording assumptions in code about what counts as "canonical": only English, only two locations. If those assumptions are wrong, the placeholder rate will be high. That is precisely the evidence Proposal 0001 Item A needs.

### Neutral

- Adds `lib/src/cli/init/` as a new sub-module. The three files import only `dart:io`, `package:yaml`, `package:path`, plus the relative siblings within `init/`. No reach into `adapters/`, `core/`, `analyzers/`, `resolvers/`, `inventory/`, `scaffolding/`, or other restricted modules. The existing `.alea.yaml::package_boundaries` does not constrain `lib/src/cli/` (consistent with the rest of the CLI layer being unrestricted as the orchestration entry point) and this ADR does not introduce a new rule. If a future module under `lib/src/cli/init/` reaches across boundaries, this is the point to revisit and add an explicit constraint.
- Tests: `pubspec_reader_test.dart`, `layer_scanner_test.dart`, `config_generator_test.dart`, plus an extended `init_command_test.dart`. ~37 new test cases.

## Explicitly out of scope

The following were considered and **deferred** to Proposal 0001 (with concrete triggers):

- **Multi-source state-management detection.** Disambiguating projects that ship multiple state managers (Bloc for legacy, Riverpod for new code). Decision is by first-match order today.
- **Non-canonical layer detection.** `data/`, Spanish, feature-first, `ui/`, `business_logic/`, etc.
- **Diagnostics-driven generation.** Cross-referencing actual imports against `pubspec.yaml` declarations; detecting style of tests, error handling, naming. All of that is Item A of Proposal 0001.
- **Interactive prompts.** v1 is silent — no questions asked. The output documents itself.
- **`--update` / merge with an existing `.alea.yaml`.** Today the policy is binary: refuse or `--force`. Merging that preserves manual edits is Item B of Proposal 0001 (full enrichment).
- **Schema validation of the generated YAML.** The generator emits syntactically valid YAML by construction; validation against `contracts/schemas/project-config.schema.yaml` (which is itself TBD) is deferred.

## Alternatives considered

### A. Single interactive `alea init` that always asks questions

Rejected. Interactivity adds significant complexity for marginal value at this stage. The output already self-documents via comments. If a real consumer reports that they cannot answer a placeholder without help, that triggers reopening this decision.

### B. Run a full filesystem walk to detect any layout variant

Rejected for v1. Honest detection across variants (Spanish, `data/`, feature-first, `ui/`, etc.) requires the heuristics and confidence levels designed in Proposal 0001 Item A. Half-doing it here would either over-promise (mis-detect) or under-deliver (miss common cases). Better to mark explicitly *not detected* and let the consumer fill in.

### C. Generate via the existing `TemplateEngine` (string templating)

Rejected. The output has many conditional branches (placeholder vs detected, Flutter vs Dart project, theme detected vs not). Templating would devolve into ugly nested conditionals. A direct string builder is clearer to read, easier to test, and produces deterministic output for goldens.

## References

- [Proposal 0001 — Adoption Flow Overhaul](../proposals/0001-adoption-flow-overhaul.md) — the larger plan this subset advances.
- [ADR-0011 — Monorepo strategy and zero-to-running bootstrap](0011-monorepo-and-bootstrap-strategy.md) — introduced the original `alea init` and its two templates.
- [ADR-0001 — Architectural invariants](0001-architectural-invariants.md) — boundary rules extended to cover `lib/src/cli/init/`.
