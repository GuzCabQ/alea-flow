# `bloc/` — Code Generation Adapter (Stub)

Stub for the `flutter_bloc` (and / or `hydrated_bloc`) style. Not implemented in v1.

## When this would be selected

`.alea.yaml::state_management.style == "bloc"`. No consumer has requested this yet.

## When to implement

A Flutter project that adopts `flutter_bloc` instead of manual Riverpod. The package is open to multiple style adapters by design (see [`../../../ARCHITECTURE.md`](../../../ARCHITECTURE.md) — Patterns section).

## Implementation outline (when ready)

Same four-file layer structure as `riverpod_manual/`:

```
bloc/
├── README.md
├── adapter.md            ← dispatcher
└── layers/
    ├── domain.md         ← identical to riverpod_manual (pure Dart)
    ├── infrastructure.md ← identical to riverpod_manual (no Flutter)
    ├── presentation.md   ← Bloc/Cubit specific
    └── bugfix.md         ← Bloc-aware bug patterns
```

The domain and infrastructure prompts can largely be copied — they don't depend on state management. Only `presentation.md` and `bugfix.md` need Bloc-specific content:

- `Bloc<Event, State>` or `Cubit<State>` instead of `Notifier<State>`.
- `BlocBuilder` / `BlocListener` / `BlocConsumer` instead of `ref.watch`.
- `context.read<Bloc>()` instead of `ref.read`.
- Test patterns: override via `RepositoryProvider`, use `bloc_test` package.
- Events as discriminated unions (often sealed classes — acceptable here since `bloc` style allows codegen).

## What changes vs Riverpod

| Concern | Riverpod Manual | Bloc |
|---|---|---|
| State holder | `Notifier<State>` | `Bloc<Event, State>` or `Cubit<State>` |
| Provider declaration | `NotifierProvider` | `BlocProvider` (per-subtree) or top-level provider |
| State class | Plain Dart with `copyWith` | Often sealed classes with subtypes per state; also plain with `copyWith` |
| Codegen | NONE | Optional `freezed` or hand-written; project-specific |
| Async safety | `ref.mounted` after await | `if (isClosed) return` after await in Bloc methods |
| Tests | Override the repository | Override the repository; use `blocTest` for state transitions |

## Why this is not in v1

YAGNI per [ARCHITECTURE.md](../../../ARCHITECTURE.md). Building unused adapters is overhead. The stub exists so adding bloc support later is "create a folder and 5 files", not "design a contract from scratch".
