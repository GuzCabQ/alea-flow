# `provider/` — Code Generation Adapter (Stub)

Stub for the `provider` package style (`ChangeNotifier` / `Provider` / `Consumer`). Not implemented in v1.

## When this would be selected

`.alea.yaml::state_management.style == "provider"`. No consumer has requested this yet.

## Implementation outline (when ready)

Same four-file layer structure as `riverpod_manual/`. Only the presentation and bugfix prompts diverge:

- `ChangeNotifier` (or `ValueNotifier` for simpler cases) instead of `Notifier`.
- `ChangeNotifierProvider` / `Provider.value` for declaration.
- `Consumer<T>` widget OR `context.watch<T>()` for reading.
- Tests: override via `ChangeNotifierProvider` in the widget tree, fake the repository.
- `addListener` / `removeListener` for fine-grained listening (rare).

## Why this is not in v1

Same as [`../bloc/README.md`](../bloc/README.md). YAGNI; build when a consumer needs it.
