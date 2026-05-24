# `adapters/` — Pluggable Implementations

Every "the answer depends on the project" decision is solved by an adapter. Adapters are looked up at runtime from `.alea.yaml`; `core/` never imports a specific adapter by path.

## Three adapter families

| Family | What it decides | Examples |
|---|---|---|
| `design-source/` | How to turn a design artifact into NDS | `figma/`, `image/`, `markup/` (HTML/JSX) |
| `code-gen/` | How to write Dart code from spec + NDS | `riverpod_manual/`, `bloc/`, `provider/` |
| `ticket-source/` | How to turn a ticket id into `analysis.json` | `asana/`, `linear/`, `file/` |

Each family has its own contract in [`../contracts/`](../contracts/). Each adapter folder is self-contained: source code, tests, reference docs, and scripts live together.

## Why split this way

Open/Closed Principle: adding a new state-management style does not touch the Figma adapter. Adding a new design tool does not touch the code generator. Each cross-cutting decision has its own axis.

Single Responsibility: an adapter has exactly one job. The flutter-ui SKILL's failure was packing 5 jobs (extract + audit + theme + gen + QA) into one unit. Here, "audit" and "theme mapping" are shared utilities in `design-source/_common/` because all design-source adapters need them; "extract" is per-adapter; "gen" is its own family; "QA" lives in `../analyzers/` and `../gates/`.

## How adapters are selected

The consumer's `.alea.yaml` declares which adapter to use per family:

```yaml
ticket_source:
  adapter: asana
design_source:
  default: figma
state_management:
  style: riverpod_manual          # selects code-gen/riverpod_manual/
```

Core resolves the adapter name to a folder, loads its `adapter.dart` (or equivalent), and invokes the contract method. If the adapter is absent or fails to load, core emits a config error — never falls back to a different adapter silently.

## Shared utilities (`_common/`)

When two or more adapters in the same family need the same helper, it goes in that family's `_common/`. Examples:

- `design-source/_common/widget-audit.md` — used by every design-source adapter to score reuse against the project's widget catalog.
- `design-source/_common/theme-map.md` — used by every design-source adapter to match colors to theme tokens.
- `code-gen/_common/layout-decision-tree.md` — used by every code-gen adapter to choose `Column` vs `ListView.builder` vs `Stack`.

`_common/` is a flat namespace within its family; it does NOT cross families. If you find yourself wanting to share between `design-source/_common/` and `code-gen/_common/`, the right answer is almost always to put it in a contract.
