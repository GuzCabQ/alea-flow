# `gates/` — Validation Pipeline

Gates orchestrate analyzers and other validators (coverage, format, fidelity score) and decide PASS/FAIL per policy. Gates are what `core/run-gates` invokes.

## Difference from `analyzers/`

- An **analyzer** runs rules and reports issues. It does not decide pass/fail.
- A **gate** decides pass/fail. It may run multiple analyzers and apply thresholds (e.g. "fail if any analyzer emits a `blocker`" or "fail if coverage in domain < 95%").

## Folders

| Folder | Concern |
|---|---|
| `domain/` | Runs analyzers relevant to the domain layer; checks coverage threshold |
| `infra/` | Same for infrastructure |
| `presentation/` | Same for presentation |
| `bugfix/` | Lighter gate for bugfix workflows |
| `fidelity/` | **New.** Visual fidelity score from NDS vs generated code (port of flutter-ui Agent 5 FidelityScore) |

## Convention

Each gate folder contains:

```
<name>/
├── gate.dart            ← gate logic (composes analyzers)
├── gate_test.dart       ← integration tests
└── README.md            ← what analyzers it runs, what thresholds it applies
```

## Gate composition rules

- A gate may invoke any number of analyzers.
- A gate may NOT invoke another gate directly. Use `core/run-gates` to sequence gates.
- A gate's pass/fail depends on (a) analyzer issue severities, (b) external metrics (coverage %, fidelity score), (c) thresholds from `.alea.yaml`.
- Gate names are conventional labels used to scope analyzer execution; the actual analyzer list per gate is configurable via `.alea.yaml`.
