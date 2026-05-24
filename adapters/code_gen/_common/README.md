# `code_gen/_common/` — Shared logic across code-gen adapters

Two pieces of generation logic repeat verbatim across every code-gen adapter (riverpod_manual, bloc, provider, getx, ...) because they're framework-agnostic Flutter concerns:

| Concern | Document |
|---|---|
| Which layout widget to emit (`Column` vs `ListView.builder` vs `Stack` vs `Row`) given an NDS pattern | [`layout-decision-tree.md`](layout-decision-tree.md) |
| Defaults Flutter assumes that NDS doesn't specify (image fit, text overflow, asset existence, emoji ban) | [`flutter-defaults.md`](flutter-defaults.md) |

## Why these live here, not in each adapter

- The decisions are about Flutter's widget tree, not about state management. `Column` vs `ListView.builder` is the same answer whether the code uses Riverpod, Bloc, or Provider.
- Centralizing them keeps adapters tight: each adapter focuses ONLY on its style's idioms (notifiers vs blocs vs change-notifiers).
- The [`visual_fidelity`](../../../lib/src/analyzers/) analyzer (step 8) verifies that generated code respects these rules — having one source of truth means the analyzer and the generator stay in sync.

## How adapters invoke this

Each code-gen adapter's `layers/presentation.md` references these documents directly:

```
For each NDS element, pick the Flutter widget per `_common/layout-decision-tree.md`.
After emitting any image, text, or button, validate against `_common/flutter-defaults.md`.
```

The shared rules are non-negotiable. An adapter MAY add stricter rules on top (e.g. "Riverpod widgets must extend ConsumerWidget when reading state") but MUST NOT loosen any rule in `_common/`.

## Scripts

The Dart helper at [`scripts/pre-commit.template.sh`](scripts/) (TBD in step 9) is a parameterized pre-commit script: each consumer's `.alea.yaml::mr.pre_push` list is materialized into a real script that `create-mr` invokes before pushing.
