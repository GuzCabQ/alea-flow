# ALEA Architecture

## Goals

- **Distributable** — any Flutter project consumes ALEA via `.alea.yaml` + slash commands. No fork-and-patch.
- **Multi-source** — design sources, ticket systems, and code-gen styles are pluggable adapters.
- **Convention-neutral** — ALEA core makes no assumption about Riverpod manual vs Bloc, GoRouter vs AutoRoute, Asana vs Linear.
- **Single primary toolchain** — Dart-first. Python is only allowed for tooling where a Dart equivalent is non-trivial AND no Dart consumer needs it inline.
- **Backwards-runnable** — the existing pipeline at the repo root stays functional throughout the migration. Nothing here imports from there.

## Principles applied

| Principle | How ALEA respects it |
|---|---|
| **SoC** | Each layer owns exactly one concern: orchestration / contracts / adapters / analysis / gates / config. No layer touches another's internals. Specifically: the existing `flutter-ui/` SKILL mixes 5 concerns (extract + audit + theme + gen + QA) in one package; ALEA decomposes those into 3 separate adapters + 1 analyzer + 1 gate. |
| **DIP** | `core/` depends on `contracts/` (abstractions). `adapters/` *implement* `contracts/`. No reverse direction. Core never imports a specific adapter; it looks the adapter up by name from `.alea.yaml`. |
| **OCP** | Adding a new design source = a new folder under `adapters/design_source/`. Zero modifications to `core/` or `contracts/`. |
| **SRP** | Each adapter has one responsibility (e.g. "extract Figma → NDS", "generate Riverpod-manual code from NDS+spec"). Each analyzer has one rule family. Each gate has one validation policy. |
| **DRY** | Cross-source utilities (widget catalog scan, theme token extraction, color distance) live in `adapters/design_source/_common/`. Cross-codegen utilities (layout decision tree, Flutter defaults) live in `adapters/code_gen/_common/`. |
| **YAGNI** | Adapters not yet needed (`image/`, `markup/`, `linear/`, `bloc/`) are stubbed with a README and an empty interface implementation — filled when the first consumer needs them. |
| **KISS** | Consumers see one config file + one slash command (`/pipeline`). All adapter selection, gate sequencing, and contract translation is internal. |
| **Law of Demeter** | Modules communicate only via published contract artifacts written to `.pipeline/runs/<id>/` (`analysis.json`, `spec.json`, `nds.yaml`, `gate_report.json`). No direct module-to-module calls. |
| **High cohesion** | Each adapter folder contains its source-specific logic, scripts, tests, and reference docs together. Browsing `adapters/design_source/figma/` shows everything Figma-related in one place. |
| **Low coupling** | Adapters share NOTHING except `contracts/`. Replacing the Figma adapter does not touch the Bloc adapter, the Asana adapter, or any analyzer. |
| **Testability** | Each adapter, analyzer, and gate has a `*_test.dart` next to its source. Contract conformance is testable via golden artifacts in `contracts/schemas/_fixtures/`. |

## Patterns

ALEA is an application of three well-known patterns that converge on the same idea.

### Ports and Adapters (Hexagonal Architecture)

Coined by Alistair Cockburn. The application defines **ports** (interfaces) describing how it talks to the outside world. **Adapters** implement those ports for specific external systems. The application core knows the ports, never the adapters.

| Cockburn's term | ALEA's term | Example |
|---|---|---|
| Application core | `core/` (markdown slash commands) | `core/commands/pipeline.md` |
| Port (driven side) | Contract in `lib/src/contracts/` (Dart) + `contracts/schemas/` (YAML) | [`DesignSourceAdapter`](lib/src/contracts/design_source_adapter.dart) interface |
| Adapter | Folder in `adapters/<family>/<name>/` | [`adapters/design_source/figma/`](adapters/design_source/figma/) |
| Domain model | Canonical shapes | NDS, `RawTicketPayload`, `CodeGenResult` |

### Anti-Corruption Layer (DDD)

Eric Evans. Protects the domain model from the vocabulary and accidental shape of external systems. Every adapter is an ACL: it translates the external system's terms into the canonical shape and never lets the external terms leak past the boundary.

In ALEA: the canonical shapes ARE the protected vocabulary. Once an adapter emits `RawTicketPayload`, the rest of the pipeline doesn't know whether the source was Asana, Linear, Jira, or a local file. Once a design-source adapter emits NDS, no downstream module knows whether the source was Figma, Sketch, an image, or HTML.

### Gateway (Fowler PoEAA)

Same shape: an object encapsulating access to an external system. Different emphasis: Fowler stresses the gateway is a single point of access whose interface stays simple even when the underlying system is complex. Each adapter folder under `adapters/` is one gateway.

### The rule that ties them together

For every family of external dependency, there is exactly ONE canonical shape that flows into the application. No adapter-specific field, vocabulary, or value ever appears in the canonical shape — those are confined to the adapter's own implementation and to its `source_metadata` cubby.

| Family | Canonical shape | Defined in |
|---|---|---|
| Ticket sources (Asana, Linear, Jira, file, GitHub Issues, ...) | `RawTicketPayload` | [adapters/ticket_source/README.md](adapters/ticket_source/README.md) |
| Design sources (Figma, image, HTML/JSX, Sketch, Adobe XD, Penpot, Storybook, ...) | `NDS` (Normalized Design Spec) | [contracts/schemas/nds.schema.yaml](contracts/schemas/nds.schema.yaml) |
| Code-gen targets (Riverpod manual, Bloc, Provider, GetX, MobX, ...) | `CodeGenResult` | [contracts/code_gen_adapter.dart](contracts/code_gen_adapter.dart) |

### Leak detection — how to audit a schema or interface

When reading any contract, ask: "Does this contain a word, enum value, or field name that names a specific external system?" If yes, it's a leak.

Examples of leaks we caught and removed during design:

- `figma_link` as a top-level field in `analysis.schema.yaml` — replaced by `attachments[*].description: "figma"`.
- `figma_source: { mcp | none | disabled }` in `spec.schema.yaml` — replaced by `design_source: { status, adapter, nds_ref, attachment_uri }` where `adapter` is an opaque string.

Adding a new external system to ALEA (a new ticket system, a new design tool, a new state-management framework) must NOT require editing any contract, schema, or core command. Only a new folder under the relevant `adapters/<family>/` is allowed. If a contract change is required to onboard the new system, the contract was leaking and the fix is to remove the leak, not to extend the leak.

## Module dependency diagram

```
                    .alea.yaml (consumer config)
                              │
                              ▼
                  ┌───────────────────────┐
   ticket    ───► │                       │
   design    ───► │      core/            │ ───► MR
   project   ───► │   (orchestration)     │      QA handoff
                  └───────────────────────┘
                              │
                              │ depends on (DIP)
                              ▼
                  ┌───────────────────────┐
                  │     contracts/        │
                  │  (stable APIs)        │
                  └───────────────────────┘
                              ▲
                              │ implemented by
              ┌───────────────┼─────────────────┐
              ▼               ▼                 ▼
        ┌──────────┐    ┌──────────┐      ┌──────────┐
        │ adapters │    │analyzers │      │  gates   │
        └──────────┘    └──────────┘      └──────────┘
              │
        ┌─────┴──────┬───────────────┐
        ▼            ▼               ▼
   design-src     code-gen      ticket-src
   ├ figma/       ├ riverpod-   ├ asana/
   ├ image/       │  manual/    ├ linear/
   ├ markup/      ├ bloc/       └ file/
   └ _common/     ├ provider/
                  └ _common/
```

**Arrows point in the direction of dependency.** `core/` knows about `contracts/`. `adapters/` know about `contracts/`. Adapters do not know about each other. Core does not know about specific adapters.

## Module responsibilities

| Module | Reads | Writes | Knows about |
|---|---|---|---|
| `core/commands/analyze-ticket` | `.alea.yaml`, ticket-source adapter | `analysis.json` (per `contracts/schemas/analysis.schema.yaml`) | nothing about Asana/Linear/etc. — looks up adapter by name |
| `core/commands/design-feature` | `analysis.json`, `.alea.yaml`, design-source adapter | `spec.json` (includes `nds_ref` pointing to NDS YAML) | nothing about Figma/HTML/etc. — delegates extraction to the adapter |
| `core/commands/implement-*` | `spec.json`, NDS, `.alea.yaml`, code-gen adapter | `<layer>_impl.md`, Dart files in the consumer project | nothing about Riverpod vs Bloc — delegates to the adapter |
| `core/commands/run-gates` | impl files, `.alea.yaml` gate list | `gate_report.json` (per `contracts/schemas/gate-report.schema.yaml`) | nothing about specific analyzers — runs whatever `contracts/Analyzer` impls are configured |
| `core/commands/review-feature`, `validate-functional`, `create-mr`, `qa-handoff`, `merge` | run artifacts | their respective outputs | project-agnostic |
| `core/commands/pipeline` | all of the above | resume state in `.pipeline/runs/<id>/` | the state machine, modes, circuit breakers, cost tracking |
| `contracts/` | nothing | nothing | the public API surface — schemas + Dart interfaces |
| `adapters/design_source/<X>/` | design source URI (figma URL / image path / html), `.alea.yaml` | NDS YAML | one source format, nothing else |
| `adapters/code_gen/<X>/` | NDS, `spec.json`, `.alea.yaml` | Dart files + `<layer>_impl.md` | one state-management/architecture style |
| `adapters/ticket_source/<X>/` | ticket id or file, `.alea.yaml` | `analysis.json` | one ticket system, nothing else |
| `analyzers/<X>/` | Dart sources, `.alea.yaml` (for layer paths, conventions) | `List<AnalysisIssue>` | one rule family |
| `gates/<X>/` | impl artifacts, analyzer outputs | pass/fail + issues | one validation policy |
| `config/` | (consumer's `.alea.yaml`) | parsed `ProjectConfig` object | the consumer-facing schema |

## Contracts — the stability surface

The package's public API. Versioned independently from any individual adapter; breaking changes require a major bump and a migration note.

| Contract | Producer | Consumer(s) | Schema |
|---|---|---|---|
| `AnalysisResult` | ticket-source adapter | `design-feature`, `implement-*`, `validate-functional` | [`contracts/schemas/analysis.schema.yaml`](contracts/schemas/analysis.schema.yaml) (TBD) |
| `NDS` (Normalized Design Spec) | design-source adapter | `design-feature` (merged into spec), code-gen adapter, `visual_fidelity` analyzer | [`contracts/schemas/nds.schema.yaml`](contracts/schemas/nds.schema.yaml) |
| `Spec` | `design-feature` | `implement-*`, `review-feature` | [`contracts/schemas/spec.schema.yaml`](contracts/schemas/spec.schema.yaml) (TBD) |
| `ImplementationReport` | `implement-*` | `run-gates`, `review-feature`, `create-mr` | structured markdown, schema in [`contracts/schemas/implementation.schema.yaml`](contracts/schemas/implementation.schema.yaml) (TBD) |
| `AnalysisIssue` | analyzer | gate, reporter | Dart class in [`contracts/analyzer.dart`](contracts/analyzer.dart) (TBD) |
| `GateReport` | `run-gates` | `review-feature`, `create-mr`, `pipeline-feedback` | [`contracts/schemas/gate-report.schema.yaml`](contracts/schemas/gate-report.schema.yaml) (TBD) |
| `ProjectConfig` | consumer's `.alea.yaml` | every module | [`contracts/schemas/project-config.schema.yaml`](contracts/schemas/project-config.schema.yaml) (TBD) |

In v1 only `nds.schema.yaml` is written out — the rest are stubs that get filled as their modules mature.

## Consumer-side configuration

Each consuming project ships a `.alea.yaml` at its repo root. ALEA reads it once at the start of every `/pipeline` invocation. Example for the reference consumer: [`config/examples/sample_app.yaml`](config/examples/sample_app.yaml).

The package's analyzers, gates, and adapters all read from this config. None of the hardcoded `my_app`, `lib/src/domain/`, `Notifier<X>`, `#0066CC`, etc. that exist in the current pipeline appear in ALEA core or any analyzer — they exist only as values in the example config.

## Extension points

| To add… | You create… | You do NOT touch |
|---|---|---|
| A new design source (Penpot, Sketch, Storybook export) | `adapters/design_source/<name>/` implementing `DesignSourceAdapter`, emitting valid NDS | `core/`, `contracts/`, other adapters |
| A new code-gen style (Bloc, MobX, Provider, GetX) | `adapters/code_gen/<name>/` implementing `CodeGenAdapter` | `core/`, `contracts/`, other adapters |
| A new ticket system (Linear, Jira, GitHub Issues) | `adapters/ticket_source/<name>/` implementing `TicketSourceAdapter` | `core/`, `contracts/`, other adapters |
| A new analyzer | `analyzers/<name>/` implementing `Analyzer` | other analyzers, `core/` |
| A new gate | `gates/<name>/` implementing `Gate` | analyzers, `core/` |

See [docs/extending-the-pipeline.md](docs/extending-the-pipeline.md) (TBD) for step-by-step.

## What ALEA is NOT

- **Not a Flutter starter template.** ALEA orchestrates work on existing Flutter projects; it does not scaffold new ones.
- **Not a code generator alone.** Code-gen is one adapter among many; analysis and gates are equally first-class.
- **Not AI-vendor-specific.** Slash commands are markdown prompts — usable from Claude Code, Cursor, Copilot CLI, Gemini CLI, Codex. The package itself does not call any AI API directly.
- **Not multi-project monorepo aware in v1.** ALEA assumes one Flutter project per consumer. Monorepos can run ALEA per-package.
- **Not a replacement for `dart analyze` / `flutter test`.** ALEA wraps and gates them; it does not duplicate them.
