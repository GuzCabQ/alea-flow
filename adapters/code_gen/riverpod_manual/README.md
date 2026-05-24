# `riverpod_manual/` — Code Generation Adapter

Implements [`CodeGenAdapter`](../../../lib/src/contracts/code_gen_adapter.dart) for projects that use Riverpod **manually** — i.e. without code generation, without `@riverpod` annotations, without `build_runner`, and without `.g.dart` files. State is expressed as plain Dart classes with `copyWith`.

This is the style currently in use across Flutter projects (the reference consumer / `my_app` is the reference consumer).

## When this adapter is selected

`.alea.yaml::state_management.style == "riverpod_manual"` — this is the only signal. The slash commands `/implement-domain`, `/implement-infrastructure`, `/implement-presentation`, and `/implement-bugfix` all look up the configured style and route here.

## What this adapter generates

Per [`adapter.md`](adapter.md) (the dispatcher) and the per-layer files under [`layers/`](layers/):

| Layer | Output (paths come from `.alea.yaml::architecture.layers.<layer>.paths`) |
|---|---|
| `domain` | Pure Dart entities + value objects + repository contracts. NO Flutter imports. NO codegen. |
| `infrastructure` | DTOs with hand-written `fromJson` / `toJson`. Repository implementations. |
| `presentation` | `Notifier<XxxState>` + `NotifierProvider` (or `AsyncNotifierProvider`). Plain Dart state classes with `copyWith`. `ConsumerWidget` / `ConsumerStatefulWidget` pages. Widget tests that override the repository provider, never the notifier. Routes registered in the consumer's router. |
| `bugfix` | Targeted edits to existing files driven by `analysis.json::affected_files` + `root_cause_hypothesis`. Regression tests added or modified. |

## Style rules (NON-NEGOTIABLE)

These are the core conventions this adapter enforces. They come from [CLAUDE.md](../../../../CLAUDE.md) of the existing pipeline plus `.alea.yaml::state_management.rules`.

### State management

- `Notifier<XxxState>` for synchronous notifiers.
- `AsyncNotifier<XxxState>` for notifiers whose `build()` is awaited (HTTP loads).
- State classes are plain Dart with `copyWith`. **No `sealed class`. No `@freezed`. No `@riverpod`. No `.g.dart`.**
- Always check `ref.mounted` after every `await`.
- `ref.watch` ONLY inside `build()`. In methods (`_load`, `refresh`, etc.) use `ref.read`.

### Provider declarations

```dart
final exampleProvider = NotifierProvider<ExampleNotifier, ExampleState>(
  ExampleNotifier.new,
);
```

For HTTP-loading notifiers:

```dart
final exampleProvider = AsyncNotifierProvider<ExampleNotifier, List<Entity>>(
  ExampleNotifier.new,
);
```

### State class shape

```dart
enum ExampleStatus { initial, loading, loaded, error }

class ExampleState {
  const ExampleState({
    this.status = ExampleStatus.initial,
    this.items = const [],
    this.error,
  });

  final ExampleStatus status;
  final List<Entity> items;
  final String? error;

  ExampleState copyWith({
    ExampleStatus? status,
    List<Entity>? items,
    String? error,
  }) => ExampleState(
    status: status ?? this.status,
    items: items ?? this.items,
    error: error ?? this.error,
  );
}
```

### Page state switching

Every page handles all states from the spec via a `switch` over the enum:

```dart
return switch (state.status) {
  ExampleStatus.loading => const CircularProgressIndicator(),
  ExampleStatus.error => ErrorMessage(message: state.error ?? ''),
  ExampleStatus.loaded when state.items.isEmpty => const EmptyState(),
  ExampleStatus.loaded => ExampleList(items: state.items),
  ExampleStatus.initial => const SizedBox.shrink(),
};
```

### Testing

- Override **repositories**, NEVER notifiers. Per [`config.testing.override_target`](../../../config/examples/my_app.yaml) — currently `repository`.
- Use `FakeXxxRepository implements XxxRepository` in `test/fakes/`. No mocktail unless last resort.
- AAA pattern (Arrange / Act / Assert).
- `pump()` for verifying loading state; `pumpAndSettle()` for the final state.

## Folder structure

```
riverpod_manual/
├── README.md             ← you are here
├── adapter.md            ← dispatcher; routes by layer
└── layers/
    ├── domain.md         ← domain entities + repository contracts
    ├── infrastructure.md ← DTOs + repository impls
    ├── presentation.md   ← notifiers + pages + widgets + routing + tests (the largest)
    └── bugfix.md         ← targeted edits flow
```

## Conformance to `CodeGenAdapter`

| Contract field | This adapter's behavior |
|---|---|
| `name` | `riverpod_manual` |
| `supports(layer, config)` | Returns `true` for all four `CodeGenLayer` values when `config.state_management.style == "riverpod_manual"`. Returns `false` otherwise. |
| `generate(req)` | Reads `req.spec`, `req.nds` (when present), `req.config`. Writes Dart files under `req.config.architecture.layers.<layer>.paths`. Writes implementation report markdown at `req.runDirectory/<layer>_impl.md`. Returns `CodeGenResult` with file lists + report path + metrics (estimated coverage, files count, lines count). |

## Constraints this adapter respects

- The `_common/layout-decision-tree.md` and `_common/flutter-defaults.md` rules. ALL of them.
- The consumer's `architecture.layers.<layer>.forbid_imports` — generated code never violates these.
- The consumer's `theme.path` is the source of truth for color tokens. Generated code imports from there.
- The consumer's `routing.router_path` is where new routes are registered. The adapter modifies that file in place.
- `widget_map.yaml` decisions are honored: `USE_AS_IS` uses an existing widget unchanged, `ADAPT` passes the recommended new optional params, `CREATE_NEW` writes a new widget at the recommended placement.
- `color_map.yaml` decisions are honored: `USE_EXACT` and `USE_CLOSEST` use the resolved token; `CREATE_NEW` falls back to a raw hex literal (which the `visual_fidelity` analyzer then flags as a `theme_compliance` violation surfacing the issue to the human).

## What this adapter does NOT do

- Does NOT generate code in non-Riverpod styles. Bloc/Provider/MobX get their own adapters.
- Does NOT modify the consumer's `pubspec.yaml`. New package dependencies (`flutter_svg`, `lottie`) are flagged in the implementation report; the consumer adds them manually.
- Does NOT invoke `flutter test` or `dart format` directly. Quality validation lives in `/run-gates`.
- Does NOT decide the state-management style. The style is config-declared; this adapter just implements it.
- Does NOT call AI APIs directly. All generation happens by the AI executing this prompt.
