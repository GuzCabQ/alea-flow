# ALEA

> **Architecture, Lint, Engineering, Automation.** A Dart package that
> ports any Flutter project from a ticket to a merge request through a
> deterministic, config-driven pipeline.

ALEA is **agnostic** to the consumer project's:

- **State manager** — Riverpod (manual), Bloc, GetX, Provider, … add a new one by writing one code-gen adapter.
- **Ticket source** — Asana, Jira, Linear, Trello, plain file, … add a new one by writing one ticket-source adapter.
- **Design source** — Figma, image, markup, Sketch, … add a new one by writing one design-source adapter.
- **Routing package**, **theme conventions**, **DI container**, **MR provider** — declared by the consumer in one YAML file.

Everything project-specific lives in **`.alea.yaml`**. Everything reusable lives in this package.

---

## Status

**v0.1.1** — every architectural phase (0 through 9) is complete and
green. Parity testing against a real consumer project precedes the
permanent `1.0.0` tag.

| Phase | Capability | Tests |
|---|---|---|
| 0  | Architectural invariants — `PackageBoundaryAnalyzer` enforces them in CI | 13 |
| 1  | Observability — `RunJournal` JSONL with PII redaction | 22 |
| 2  | Design token catalog (`dart_source` + `json` adapters) | 45 |
| 3  | Pure matching library + token resolvers (palette / type-scale / layout / component-lookup) | 96 |
| 4  | Visual fidelity with catalog (`color_not_in_catalog`, `typography_not_in_catalog`, …) | 7 |
| 5  | Widget inventory builder + `SymbolDigest` (≥70% token reduction) | 38 |
| 6  | Wiring cohesion analyzer (config-driven DI/route registration check) | 10 |
| 7  | Executable code-gen (Riverpod-manual + Bloc adapters; idempotent + rollback) | 29 |
| 8  | Cacheable context packet (TTL + hash invalidation) | 19 |
| 9  | Consolidated CLI (`aflow analyze \| match \| scaffold \| inventory \| journal \| context`) | 11 |
| 10 | Monorepo + bootstrap — `aflow init` (project / feature templates) + external token catalog source ([ADR-0011](docs/adr/0011-monorepo-and-bootstrap-strategy.md)) | 11 |
| 11 | Existing-project bootstrap — `aflow init --template config` ([ADR-0012](docs/adr/0012-init-template-config.md)) | 37 |
| | | **625 total** (run `dart test` for the current total) |

<!-- TODO(next release): the per-phase "Tests" column above is stale/approximate
     and does not account for cross-cutting + newer analyzer tests
     (testing/flutter_antipatterns/code_complexity were added in 0.1.1).
     The graph implementation was extracted to dart_source_graph ^0.1.0 (ADR-0022),
     reducing the inline test count.
     Recount tests per phase and reconcile the column so it sums to 625. -->

---

## Quickstart

From an existing Flutter (or Dart) project to a working ALEA setup in
three steps. Each step is copy-pasteable as-is from inside your project
root.

### 1 — Install ALEA

```bash
dart pub global activate --source path /path/to/alea
# or, once published:
# dart pub global activate alea_flow
```

Optionally compile to a native executable (eliminates Dart VM cold start):

```bash
cd /path/to/alea
./tool/compile.sh
# `bin/aflow` is now a self-contained ~10MB binary
```

### 2 — Generate `.alea.yaml` from your project

Inside your existing Flutter (or Dart) project root:

```bash
aflow init --template config
```

This reads your `pubspec.yaml`, scans the filesystem for canonical
Clean Architecture layer folders (`lib/src/{domain,infrastructure,
presentation}/` and theme), and writes a starter `.alea.yaml`. Every
generated field carries a comment documenting its origin:

- `# inferred from <X>` — auto-detected from your `pubspec.yaml`
  (state management, routing, Flutter vs Dart project).
- `# detected at <path>` — folder confirmed by the filesystem scan.
- `# default` — industry-standard fallback; adjust if needed.
- `# PLACEHOLDER` — could not auto-detect; **human action required**.

Open `.alea.yaml`, search for `# PLACEHOLDER`, and adjust those blocks
to match your project. Common cases that produce placeholders:

- Layer folders not under `lib/src/<layer>/` or `lib/<layer>/`
  (for example, `data/` instead of `infrastructure/`, Spanish names
  like `dominio/`, or feature-first layouts under
  `lib/features/<feature>/<layer>/`).
- A `pubspec.yaml` with no known state-management or routing dependency.

Detection is intentionally conservative in this release. To resolve the
placeholders above automatically, run the **`/aflow-complete-config`** command
(an AI prompt under [`core/commands/`](core/commands/)): it builds the
code-knowledge-graph for your project and proposes `architecture.layers`
paths plus `may_import` / `forbid_imports` from your **real dependency
edges** — handling non-canonical names and feature-first layouts — then
shows a diff for you to approve. It also flags import cycles and any
domain layer that imports `package:flutter`. The broader diagnostics-driven
flow is tracked in
[Proposal 0001](docs/proposals/0001-adoption-flow-overhaul.md); the full
configuration reference lives in
[`docs/CONSUMER_INTEGRATION.md`](docs/CONSUMER_INTEGRATION.md).

### 3 — Run your first analysis

```bash
aflow analyze --gate domain --format human
```

ALEA loads `.alea.yaml`, runs the domain-layer gate, and prints findings
to the terminal. If you have not yet created the layer folders, this is
the moment they will be flagged — the gate is the truth source about
whether your config matches reality.

For a **browsable, triage-first report** instead of the terminal wall, add
`--format html`:

```bash
aflow analyze --gate full --format html -o alea-reports/
```

This writes a self-contained `alea-reports/` folder (`index.html` + `styles.css` +
`app.js` + `report.json`) — open `alea-reports/index.html` in a browser. It surfaces
the few **blocking** findings (blocker/critical) above the many **advisory** ones
(major/minor), with grouping by severity / file / analyzer, live filters and search.
With `--format html`, `-o` is the output **directory** (default `alea-reports/`). Add
`alea-reports/` to your `.gitignore`.

---

## Which `init` template do I need?

The Quickstart above uses `--template config`. That is the right choice
for **existing** projects. Pick once, based on the state of your project:

| Your situation | Command | What it produces |
|---|---|---|
| Existing Flutter or Dart project with code | `aflow init --template config` | Only `.alea.yaml`, generated from your `pubspec.yaml` + filesystem scan (the [Quickstart](#quickstart) above). |
| Fresh project just created with `flutter create` | `aflow init --template project` | `.alea.yaml` + empty layer folders + a theme tokens stub + a `go_router` stub + `test/fakes/`. Defaults assume Riverpod + `go_router`; add the matching deps to your `pubspec.yaml` if you have not already. |
| New Dart feature package in a Melos / pub workspaces monorepo | `aflow init feature_x --template feature` | A Dart package skeleton with `.alea.yaml` pointing its token catalog at a sibling `design_system` package (see [ADR-0011](docs/adr/0011-monorepo-and-bootstrap-strategy.md)). |

If you ran `flutter create my_app` minutes ago, **use `--template project`** — the `config` flow expects an existing project to read from, and on a brand-new Flutter skeleton it will produce a `.alea.yaml` full of `# PLACEHOLDER` blocks because the layer folders do not yet exist.

---

## Other useful commands

Once `.alea.yaml` is in place, these subcommands become available:

```bash
# Resolve a hex color against your token catalog
aflow match color "#0066CC"

# Scaffold a Riverpod feature (state + notifier + screen)
aflow scaffold auth --layer presentation --style riverpod_manual

# Scan widgets and emit a JSON inventory
aflow inventory --output widget_inventory.json

# Build a context packet for the next LLM call
aflow context --run-directory .pipeline/runs/DEV-1234/

# Inspect the JSONL run journal
aflow journal --run-directory .pipeline/runs/DEV-1234/
```

---

## Running the ticket → PR pipeline

`.alea.yaml` enables a slash-command pipeline defined under
[`core/commands/`](core/commands/). These are markdown prompts intended
to be executed by an **AI-driven CLI** that supports user-invokable
instruction files. The package itself does not call any AI API directly.

Compatible tools (the registration mechanism varies by tool):

- Claude Code (custom commands or skill files)
- Cursor (commands via Composer)
- Gemini CLI
- Copilot CLI
- Codex

### Installing the commands into your agent

`aflow install-commands` deterministically installs the bundled prompts into
your AI agent platform. Run it from your project root:

```bash
# Interactive menu — select one or more platforms
aflow install-commands

# Non-interactive — specify platforms explicitly (or use "all")
aflow install-commands --platform claude
aflow install-commands --platform claude,gemini,codex,cursor
aflow install-commands --platform all

# Preview what would be written without touching the filesystem
aflow install-commands --platform all --dry-run
```

Four platforms are supported in v1:

| Platform | Destination | Notes |
|---|---|---|
| `claude` | `.claude/commands/<id>.md` | YAML frontmatter `description`; `$ARGUMENTS` native |
| `gemini` | `.gemini/commands/<id>.toml` | TOML format; `$ARGUMENTS` rewritten to `{{args}}` |
| `codex` | `~/.codex/prompts/<id>.md` (or `$CODEX_HOME/prompts/`) | **Global install** — covers all projects on the machine; Codex custom prompts are deprecated upstream in favour of skills, but remain functional |
| `cursor` | `.cursor/commands/<id>.md` | YAML frontmatter `name` + `description`; `$ARGUMENTS` kept as-is |

`aflow init --platform <id>` runs the same install at the end of
onboarding, so a single command bootstraps the config and the commands:

```bash
aflow init --template config --platform claude
```

For platforms not yet covered by a deterministic adapter, the agent-driven
fallback remains available:

```bash
aflow commands-path
# → prints the dir holding the prompts + INSTALL.md
# Open that dir's INSTALL.md in your agent and ask it to follow the steps.
```

See [ADR-0021](docs/adr/0021-deterministic-command-install.md) for the
design decisions and per-platform format details.

From inside a project that has `.alea.yaml`, point your AI tool at the
`core/commands/` folder of this package and ask it to follow
[`aflow-pipeline.md`](core/commands/aflow-pipeline.md) for a given ticket. The
pipeline drives the full flow: reads the ticket, generates a spec,
implements each architectural layer, runs gates per layer, reviews, and
creates the MR. All artifacts land in `.pipeline/runs/<ticket_id>/`.

Three execution modes are available via `.alea.yaml::pipeline.default_mode`:

| Mode | Stops at |
|---|---|
| `guided` | Every gate — explicit approval required before each phase. |
| `semi` | Gate 0 (spec approval) and Gate Final (review) only. |
| `auto` | Only when a validator fails. |

Other useful command files in the same folder, each invokable on its own:

- [`aflow-analyze-ticket.md`](core/commands/aflow-analyze-ticket.md) — parse a ticket into structured analysis.
- [`aflow-design-feature.md`](core/commands/aflow-design-feature.md) — turn an analysis into a spec.
- [`aflow-implement-domain.md`](core/commands/aflow-implement-domain.md), [`aflow-implement-infrastructure.md`](core/commands/aflow-implement-infrastructure.md), [`aflow-implement-presentation.md`](core/commands/aflow-implement-presentation.md) — per-layer implementation.
- [`aflow-implement-bugfix.md`](core/commands/aflow-implement-bugfix.md) — bugfix flow (no design phase).
- [`aflow-run-gates.md`](core/commands/aflow-run-gates.md) — invoke the analyzer suite for a layer.
- [`aflow-review-feature.md`](core/commands/aflow-review-feature.md), [`aflow-validate-functional.md`](core/commands/aflow-validate-functional.md) — pre-MR checks.
- [`aflow-create-mr.md`](core/commands/aflow-create-mr.md), [`aflow-qa-handoff.md`](core/commands/aflow-qa-handoff.md), [`aflow-merge.md`](core/commands/aflow-merge.md) — final delivery.
- [`aflow-complete-config.md`](core/commands/aflow-complete-config.md) — graph-grounded `.alea.yaml` enrichment: proposes layer paths + import rules from the code graph (see [Quickstart](#quickstart)).
- [`aflow-review-diff.md`](core/commands/aflow-review-diff.md) — standalone review over `git diff`, **no pipeline run required** (structural gates + graph-based regression check + code review).

The pipeline phases consult the code-knowledge-graph as a verified-fact source: `analyze-ticket` estimates blast radius (`graph-query impact`), `design-feature` finds reuse candidates (`neighbors`), `review-feature` flags untouched consumers as potential regressions, and `run-gates` warns on high-coupling hubs (`god-nodes`). The graph is built once and refreshed only when the tree changes (`aflow graph --ensure-fresh`).

The graph uses an **opt-out coverage** model: it collects every `.dart` under `lib/`, and a blind spot can exist only via an explicit `graph.exclude` glob (defaults exclude generated `*.g.dart`/`*.freezed.dart`). Layer paths only *classify* the collected set — files outside every declared layer are surfaced (never dropped) by `graph-query unlayered`, which `/aflow-complete-config` uses to propose declaring or excluding them. Declaration nodes carry a semantic `role` (e.g. `riverpod.notifier`, `getx.controller`, `flutter.widget`) derived from their supertype (extend via `graph.roles`); method/function nodes plus `calls` edges (by-name, marked `ambiguous`) let `graph-query state-flow` summarize which providers/controllers each role-tagged node depends on. See [ADR-0019](docs/adr/0019-graph-as-pipeline-and-config-engine.md) and [ADR-0020](docs/adr/0020-graph-slice-2-precision.md).

> **Implementation note.** The graph engine (builder, resolver, wiring-edge pass, query) now lives in the external [`dart_source_graph`](https://pub.dev/packages/dart_source_graph) package (`^0.1.0`), on which alea-flow depends. The `aflow graph` and `aflow graph-query` subcommands are unchanged thin wrappers — their flags, output schema, and exit codes are identical to the inline implementation. See [ADR-0022](docs/adr/0022-graph-extracted-to-package.md) for the extraction rationale and parity verification.

> **Maturity note.** The pipeline is the part of alea-flow that has not
> yet been validated against a real consumer project (see [Status](#status)
> — v0.1.1 awaits parity testing for the v1.0.0 tag). Treat this as a
> preview path that works in principle but may require human
> course-correction. Bug reports against `core/commands/` are welcome.

---

## Architecture

Ports & Adapters (hexagonal). Every external system is an adapter; every
algorithm is a service. Boundaries are enforced by the
[`PackageBoundaryAnalyzer`](lib/src/analyzers/package_boundary/analyzer.dart) running against the
ALEA tree itself on every CI build.

```
              ┌─────────────────────────────────────────────────────┐
              │                  bin/aflow.dart                      │
              │              (thin CLI shim — 22 LOC)               │
              └────────────────────────┬────────────────────────────┘
                                       │
              ┌────────────────────────▼────────────────────────────┐
              │                  lib/src/cli/                        │
              │  CommandRunner + 15 command classes                  │
              │  (init, analyze, match, scaffold, inventory,         │
              │   journal, context, redact, check-files-changed,     │
              │   validate-artifact, metrics, run, graph,            │
              │   graph-query, install-commands)                      │
              └────────────────────────┬────────────────────────────┘
                                       │
        ┌──────────────────────────────▼──────────────────────────────┐
        │                       Services                              │
        │  ──────────────────────────────────────────────────────     │
        │   lib/src/scaffolding/   lib/src/resolvers/                 │
        │   lib/src/inventory/     lib/src/matching/  (pure)          │
        │   lib/src/core/                                             │
        └──────────────────────────────┬──────────────────────────────┘
                                       │
                          ┌────────────▼────────────┐
                          │        Contracts        │
                          │   lib/src/contracts/    │
                          │   (the most stable      │
                          │    surface — every      │
                          │    other ring imports   │
                          │    from here)           │
                          └────────────▲────────────┘
                                       │
        ┌──────────────────────────────┴──────────────────────────────┐
        │                       Adapters                              │
        │  ──────────────────────────────────────────────────────     │
        │   lib/src/adapters/code_gen/{riverpod_manual,bloc}/         │
        │   lib/src/adapters/token_catalog/{dart_source,json}/        │
        │   (one folder per external system / framework)              │
        └─────────────────────────────────────────────────────────────┘
```

**Hard invariants** (enforced by CI — see [`docs/adr/0001-architectural-invariants.md`](docs/adr/0001-architectural-invariants.md)):

- `lib/src/contracts/` is pure — only `dart:core`, `dart:async`, `dart:convert`, `package:meta`.
- `lib/src/matching/` is pure — no I/O, no analyzer, no path.
- `lib/src/analyzers/` may not import `lib/src/adapters/`.
- `lib/src/core/` may not import `lib/src/adapters/` — adapter selection
  happens at runtime via name lookup against `ProjectConfig`.
- `lib/src/resolvers/`, `lib/src/inventory/`, `lib/src/scaffolding/`
  (services) may not import `lib/src/adapters/`.

---

## Project layout

```
alea/
├── bin/
│   └── alea.dart                ← CLI entry (delegates to AleaCliRunner)
├── lib/
│   ├── alea.dart                ← public barrel
│   ├── matching.dart            ← pure matching library (importable alone)
│   └── src/
│       ├── adapters/
│       │   ├── code_gen/{riverpod_manual,bloc}/
│       │   └── token_catalog/{dart_source,json}/
│       ├── analyzers/           ← 16 analyzers (layer_integrity, visual_fidelity, …)
│       ├── cli/
│       │   ├── cli_runner.dart
│       │   └── commands/{init,analyze,match,scaffold,inventory,journal,context,
│       │                  redact,check_files_changed,validate_artifact,
│       │                  metrics,run,graph,graph_query,install_commands}_command.dart
│       ├── contracts/           ← Ports (the stable API surface)
│       ├── core/
│       │   ├── config/loader.dart
│       │   ├── context/context_packet_builder.dart
│       │   ├── journal/
│       │   ├── registry.dart
│       │   ├── reporter.dart
│       │   └── runner.dart
│       ├── inventory/
│       │   ├── widget_inventory_builder.dart
│       │   └── symbol_digest.dart
│       ├── matching/            ← pure math (ΔE CIE2000, Jaccard, …)
│       ├── resolvers/           ← palette, type_scale, layout_metric, component_lookup
│       └── scaffolding/         ← template_engine, scaffold_executor, scaffold_verifier
├── docs/
│   ├── CONSUMER_INTEGRATION.md  ← step-by-step guide for consumer projects
│   └── adr/                     ← 18 architectural decision records
├── tool/
│   ├── check_alea_boundaries.dart  ← CI guard — runs PackageBoundaryAnalyzer on ALEA
│   └── compile.sh                  ← AOT compile to bin/aflow
├── test/                        ← 625 tests, mirrors lib/src/ layout (run `dart test` for the current total)
├── .alea.yaml                   ← ALEA's own consumer config (eats its dogfood)
└── pubspec.yaml
```

---

## Documentation

- [`docs/PROJECT_WALKTHROUGH.md`](docs/PROJECT_WALKTHROUGH.md) — **visual walkthrough** with mermaid diagrams + ordered reading list. Start here if you're new.
- [`docs/CONSUMER_INTEGRATION.md`](docs/CONSUMER_INTEGRATION.md) — the full guide for adopting ALEA in a new Flutter project.
- [`docs/adr/`](docs/adr/) — twenty-two architectural decision records, roughly one per phase (0001 = invariants; 0002 = run journal; … 0012 = existing-project bootstrap; 0013–0020 = HTML report, code-knowledge-graph resolution/wiring/query, self-package resolution, graph slice-2; 0021 = deterministic command install; 0022 = graph extracted to `dart_source_graph`).
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — the original design document.
- [`CHANGELOG.md`](CHANGELOG.md) — per-version changes.

---

## Development

```bash
cd alea
dart pub get

# Static analysis
dart analyze

# Tests (run `dart test` for the current total)
dart test

# Self-boundary check (ALEA enforces its own invariants)
dart run tool/check_alea_boundaries.dart

# Compile to native
./tool/compile.sh
```

---

## License

See [`LICENSE`](LICENSE) (TBD).
