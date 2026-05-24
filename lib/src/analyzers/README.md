# `analyzers/` — Static Analysis Rules

Each subfolder is one analyzer. Every analyzer implements `Analyzer` from [`../contracts/analyzer.dart`](../contracts/analyzer.dart) (TBD) and emits `List<AnalysisIssue>`.

## Difference from `gates/`

- **Analyzers** run rules over Dart source files. They are stateless, idempotent, and parallel-safe. They emit issues with severity (`minor` / `major` / `critical` / `blocker`).
- **Gates** orchestrate analyzers + other validators (coverage, fidelity score, lint, format) and decide PASS/FAIL based on policy.

A gate runs many analyzers. An analyzer runs once and reports.

## Folders (initial set, ported from `tools/pipeline/lib/src/analyzers/`)

| Folder | Concern |
|---|---|
| `layer_integrity/` | Clean Architecture import rules between layers (config-driven) |
| `widget-purity/` | `build()` purity, no side effects, no I/O |
| `build_method_complexity/` | `build()` length and nesting depth (renamed from `widget_reuse_analyzer`) |
| `state-mgmt/` | State-management framework conventions, preset per code-gen style |
| `testing/` | Test placement, naming, override targets |
| `flutter-antipatterns/` | Common Flutter pitfalls |
| `design-principles/` | SOLID + DDD checks at the syntactic level |
| `dry-detection/` | Duplication across files |
| `code-complexity/` | Cyclomatic complexity per function |
| `performance/` | Known performance hazards |
| `project-conventions/` | Naming, file structure, conventions declared in `.alea.yaml` |
| `security/` | Common security mistakes |
| `visual-fidelity/` | **New.** From flutter-ui Agent 5 critical checks: emoji-as-icon, button-without-content, gradient-degraded, asset-broken, ignored-widget_hint, missing-fit. |

## Convention

Each analyzer folder contains:

```
<name>/
├── analyzer.dart          ← implements Analyzer
├── analyzer_test.dart     ← unit tests with fixtures
├── README.md              ← what it checks and why
└── presets/               ← (only if applicable) preset rules per consumer style
    ├── riverpod_manual.yaml
    └── bloc.yaml
```

Issues emitted include: file path, line number, severity, rule id, human-readable message, suggested fix.

## Config-driven, not project-specific

No analyzer hardcodes project paths, package names, layer structures, or framework names. Everything comes from `ProjectConfig`. An analyzer that needs to know "what is the domain layer" reads `architecture.layers.domain.paths` from config — never `lib/src/domain/`.
