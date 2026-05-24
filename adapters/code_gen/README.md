# `adapters/code_gen/`

Adapters that turn NDS + spec + project config into Dart code in the consumer project.

## Contract

Every folder here implements `CodeGenAdapter` from [`../../contracts/code_gen_adapter.dart`](../../contracts/code_gen_adapter.dart) (TBD).

Inputs:
- NDS (Normalized Design Spec) — what to render visually.
- `spec.json` — what to build per layer (entities, repositories, providers, pages).
- `ProjectConfig` — state-management style preferences, layer paths, testing conventions, routing package.

Output:
- Dart files written to the consumer project at the paths declared in `architecture.layers.*.paths`.
- An implementation report at `.pipeline/runs/<id>/<layer>_impl.md` summarizing what was created.

The adapter writes test scaffolding only if the consumer's `testing.framework` is set; the test contents themselves follow the adapter's own conventions (e.g. `riverpod_manual/` writes `ProviderScope` overrides of repository providers, never notifiers).

## Folders

| Folder | Style | Status |
|---|---|---|
| `riverpod_manual/` | Manual Riverpod: `Notifier<XxxState>`, `NotifierProvider`, plain Dart state with `copyWith`, no `@riverpod`, no `build_runner`, `ref.mounted` after every `await` | Primary adapter (port of current `implement-presentation.md` + flutter-ui Agent 4) |
| `bloc/` | flutter_bloc / hydrated_bloc | Stub for v1 (YAGNI) |
| `provider/` | provider package | Stub for v1 (YAGNI) |
| `_common/` | Shared across all code-gen styles (layout decision tree, Flutter defaults: image fit, text overflow, asset existence checks, emoji prohibition) | Always present |

## Why split by state-management style

The state-management style is the largest single source of project divergence in Flutter. Riverpod-manual generates very different code from Bloc, even given identical NDS + spec. Splitting on this axis means each adapter can encode its style's idioms tightly without conditionals.

Cross-style concerns (responsive layout, text overflow defaults, asset fit, emoji ban, image existence checks) live in `_common/` because they don't depend on the state framework.

## Adding a new adapter

1. Create `adapters/code_gen/<style>/`.
2. Implement `CodeGenAdapter`.
3. Add a README explaining: what state-management package it targets, what test patterns it generates, what files it creates per layer.
4. Add `<style>_test.dart` with golden-file fixtures (input NDS+spec → expected Dart output).
5. Add a preset for `state_mgmt` analyzer rules under `analyzers/state-mgmt/presets/<style>.yaml`.
6. Declare the adapter selectable in `state_management.style` in the project config schema.
