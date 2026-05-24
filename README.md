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

**v0.1.0** — every architectural phase (0 through 9) is complete and
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
| | | **320 total** |

---

## Quickstart (consumer projects)

### 1 — Add `.alea.yaml` to your project root

Minimal config (see [`docs/CONSUMER_INTEGRATION.md`](docs/CONSUMER_INTEGRATION.md) for the full reference):

```yaml
config_version: "1.0.0"

project:
  package_name: my_app
  pubspec_path: pubspec.yaml

architecture:
  layers:
    domain:
      paths: [lib/src/domain/]
      forbid_imports: ["package:flutter/"]
    infrastructure:
      paths: [lib/src/infrastructure/]
      may_import: [domain]
    presentation:
      paths: [lib/src/presentation/]
      may_import: [domain]

state_management:
  style: riverpod_manual    # or bloc, provider, getx, …

routing:
  package: go_router
  router_path: lib/src/app/router.dart

theme:
  path: lib/src/theme/
  token_catalog:
    adapter: dart_source
    source: lib/src/theme/

testing:
  framework: flutter_test
  fakes_path: test/fakes/

coverage:
  thresholds: { domain: 95, infrastructure: 80, presentation: 70 }

ticket_source: { adapter: file }
design_source: { default: figma }

mr:
  policy: single-commit-amend
  branch_pattern: "feature/{ticket_id}-{slug}"
  pre_push: [dart format ., dart analyze, flutter test]

pipeline:
  default_mode: guided
  modes_available: [guided, semi, auto]
  cost_warn_usd: 3.0
  cost_hard_stop_usd: 5.0

gates:
  domain: [domain]
  infrastructure: [infra]
  presentation: [presentation]
```

### 2 — Install ALEA

```bash
dart pub global activate --source path /path/to/alea
# or in the future, when published:
# dart pub global activate alea
```

Compile to a native executable (eliminates Dart VM cold start):

```bash
cd /path/to/alea
./tool/compile.sh
# now `bin/aflow` is a self-contained ~10MB binary
```

### 3 — Run a subcommand

```bash
# Bootstrap a project skeleton (post `flutter create`) or a feature package
alea init my_app                              # default: --template project
alea init feature_wallet --template feature   # monorepo feature package

# Static analysis: produce a gate report
alea analyze --project-root . --gate domain --format human

# Resolve a hex color against your token catalog
alea match color "#0066CC"

# Scaffold a Riverpod feature (state + notifier + screen)
alea scaffold auth --layer presentation --style riverpod_manual

# Scan widgets and emit a JSON inventory
alea inventory --output widget_inventory.json

# Build a context packet for the next LLM call
alea context --run-directory .pipeline/runs/DEV-1234/

# Inspect the JSONL run journal
alea journal --run-directory .pipeline/runs/DEV-1234/
```

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
              │  CommandRunner + 6 command classes                   │
              │  (analyze, match, scaffold, inventory, journal,      │
              │   context)                                           │
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
│       │   └── commands/{analyze,match,scaffold,inventory,journal,context}_command.dart
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
│   └── adr/                     ← 10 architectural decision records
├── tool/
│   ├── check_alea_boundaries.dart  ← CI guard — runs PackageBoundaryAnalyzer on ALEA
│   └── compile.sh                  ← AOT compile to bin/aflow
├── test/                        ← 309 tests, mirrors lib/src/ layout
├── .alea.yaml                   ← ALEA's own consumer config (eats its dogfood)
└── pubspec.yaml
```

---

## Documentation

- [`docs/PROJECT_WALKTHROUGH.md`](docs/PROJECT_WALKTHROUGH.md) — **visual walkthrough** with mermaid diagrams + ordered reading list. Start here if you're new.
- [`docs/CONSUMER_INTEGRATION.md`](docs/CONSUMER_INTEGRATION.md) — the full guide for adopting ALEA in a new Flutter project.
- [`docs/adr/`](docs/adr/) — ten architectural decision records, one per phase (0001 = invariants; 0002 = run journal; … 0010 = CLI consolidation).
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — the original design document.
- [`CHANGELOG.md`](CHANGELOG.md) — per-version changes.

---

## Development

```bash
cd alea
dart pub get

# Static analysis
dart analyze

# Tests (run all 309)
dart test

# Self-boundary check (ALEA enforces its own invariants)
dart run tool/check_alea_boundaries.dart

# Compile to native
./tool/compile.sh
```

---

## License

See [`LICENSE`](LICENSE) (TBD).
