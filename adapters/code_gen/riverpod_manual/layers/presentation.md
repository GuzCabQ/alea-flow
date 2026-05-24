# Presentation Layer Generation (Riverpod Manual)

Generates the UI layer: notifiers (state holders), pages, widgets, route registration, and widget tests. This is the largest of the four layer prompts because it integrates three input streams (spec + NDS + decisions from widget_map/color_map) and applies the most rules.

## Inputs

From the `CodeGenRequest`:

- `spec.presentation.providers` — `ProviderSpec[]` (notifiers, state classes, actions).
- `spec.presentation.pages` — `PageSpec[]` (routes, states, names).
- `spec.presentation.widgets_reuse` — `WidgetReuseSpec[]` (USE_AS_IS / ADAPT decisions from `widget_map.yaml`).
- `spec.presentation.widgets_new` — `WidgetNewSpec[]` (CREATE_NEW decisions).
- `spec.presentation.routes` — list of route paths.
- `nds` — when `spec.design_source.status == "extracted"`. The element tree to render. Null otherwise (no design extraction).
- `widgetMap` — per-element decisions. Null when no NDS.
- `colorMap` — per-element color token resolution. Null when no NDS.
- `config.architecture.layers.presentation.paths`, `theme.*`, `routing.*`, `testing.*`.

## Pre-generation reading

Before writing any code:

1. Read `config.theme.path` to confirm available tokens (the actual `AppColors` / `AppTextStyles` class names and members).
2. Read every widget referenced by `widgets_reuse[*].file` to understand its current constructor surface. Required so `ADAPT` decisions don't break existing call sites.
3. Read `config.routing.router_path` to confirm the existing GoRouter pattern (or whatever package is configured).

## Output

```
<presentation_path>/<feature_slug>/
├── providers/
│   ├── <name>_notifier.dart        ← Notifier + State + Provider declarations
│   └── ...
├── pages/
│   ├── <name>_page.dart
│   └── ...
└── widgets/                        ← only for widgets_new (CREATE_NEW decisions)
    ├── <name>.dart
    └── ...
```

Plus:

- `config.routing.router_path` is modified in place to register new routes.
- Test files under the consumer's test path mirroring this layout.

## Generation order

1. **Providers first** — they're imported by pages. Skip if `spec.presentation.providers` is empty.
2. **New widgets next** — pages may compose them.
3. **Pages** — top-level for the feature.
4. **Routes** — register in the router file.
5. **Widget tests** — one test file per page, covering every state.

## 1. Providers (Notifier + State + Provider declarations)

For each `ProviderSpec`:

### State class

```dart
enum <Name>Status { initial, loading, loaded, error }

class <Name>State {
  const <Name>State({
    this.status = <Name>Status.initial,
    <state_fields with defaults>,
    this.error,
  });

  final <Name>Status status;
  <state_fields with `final`>
  final String? error;

  <Name>State copyWith({
    <Name>Status? status,
    <each field>?,
    String? error,
  }) => <Name>State(
    status: status ?? this.status,
    <each field>: <each field> ?? this.<each field>,
    error: error ?? this.error,
  );
}
```

`state_fields` come from `ProviderSpec.state_fields` verbatim (e.g. `List<Entity> items`).

### Notifier class

For synchronous notifiers (most cases):

```dart
class <Name>Notifier extends Notifier<<Name>State> {
  @override
  <Name>State build() {
    unawaited(_load());
    return const <Name>State();
  }

  Future<void> _load() async {
    state = state.copyWith(status: <Name>Status.loading);
    try {
      final result = await ref.read(<repositoryProvider>).<method>();
      if (!ref.mounted) return;
      state = state.copyWith(status: <Name>Status.loaded, items: result);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(status: <Name>Status.error, error: e.toString());
    }
  }

  // For each spec.actions entry, generate a method on the notifier.
  Future<void> <action_name>() async { ... }
}
```

For HTTP-loading notifiers where build itself is async, use `AsyncNotifier`:

```dart
class <Name>Notifier extends AsyncNotifier<<ReturnType>> {
  @override
  Future<<ReturnType>> build() async {
    return ref.read(<repositoryProvider>).<method>();
  }
}
```

### Provider declaration

```dart
final <camelCaseName>Provider = NotifierProvider<<Name>Notifier, <Name>State>(
  <Name>Notifier.new,
);
```

Or for `AsyncNotifier`:

```dart
final <camelCaseName>Provider = AsyncNotifierProvider<<Name>Notifier, <ReturnType>>(
  <Name>Notifier.new,
);
```

### Riverpod-manual invariants (NON-NEGOTIABLE)

- `ref.watch` ONLY in `build()`. In methods (`_load`, `refresh`, actions): use `ref.read`.
- After every `await` in a notifier method: `if (!ref.mounted) return;` BEFORE touching `state`.
- NO `@riverpod` annotation. NO codegen import. NO `.g.dart` file generated.
- State class is plain Dart with `copyWith`. NO `sealed class`. NO `@freezed`. NO `Equatable`.

## 2. New widgets (CREATE_NEW decisions)

For each `WidgetNewSpec`:

- Use `StatelessWidget` unless the widget itself needs `initState` / `dispose` / `AnimationController` (rare for content widgets — most stateful logic belongs to the notifier).
- `const` constructor when all props are constant-eligible.
- One responsibility per widget.
- Receive data by props from the constructor. NEVER read providers in leaf widgets — pass via props from the page.
- For lists with variable content, use `ListView.builder` per [`../../_common/layout-decision-tree.md`](../../_common/layout-decision-tree.md).

### When NDS is present for this widget

If `widget_map.yaml::<element_id>.decision == "CREATE_NEW"` AND the NDS element for it exists:

- Pick the root layout per [`../../_common/layout-decision-tree.md`](../../_common/layout-decision-tree.md).
- Apply `../../_common/flutter-defaults.md` rules: image fit, text overflow, asset existence, emoji ban, button content, gradient direction.
- Resolve every NDS color via `color_map.yaml`:
  - `USE_EXACT` / `USE_CLOSEST` → `AppColors.<tokenName>` (or whatever the consumer's theme class is — read from `config.theme.path`).
  - `CREATE_NEW` → emit the raw hex literal AS A LAST RESORT and add a `// TODO: token missing — design says <hex>` comment.
- Resolve every NDS background.opacity via `.withValues(alpha: <opacity>)` after the token lookup.

### When NDS is absent

Use the widget's props and the spec's description to make reasonable layout decisions. Follow `_common/` rules unconditionally.

## 3. Pages

For each `PageSpec`:

```dart
class <Name>Page extends ConsumerWidget {
  const <Name>Page({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(<providerName>);

    return Scaffold(
      appBar: AppBar(title: const Text('<Title>')),
      body: switch (state.status) {
        <Status>.loading => const Center(child: CircularProgressIndicator()),
        <Status>.error => ErrorMessage(message: state.error ?? ''),
        <Status>.loaded when state.<itemsField>.isEmpty => const EmptyState(message: '<empty message>'),
        <Status>.loaded => _Body(state: state),
        <Status>.initial => const SizedBox.shrink(),
      },
    );
  }
}
```

The `_Body` widget is private to the file and renders the loaded state. Extract it to its own widget when the page has > 100 lines.

### `ConsumerStatefulWidget` cases

Use `ConsumerStatefulWidget` ONLY when:

- You need `initState` / `dispose` for non-Riverpod resources (scroll controllers, animations).
- You need to close over `ref` in a callback that survives rebuilds.

Otherwise `ConsumerWidget` is sufficient and lighter.

### State handling rules

- Handle EVERY state in `PageSpec.states`. Missing a state is a `blocker` for the `visual_fidelity` analyzer.
- NO side effects in `build()` (no async calls, no provider modifications, no sorting/filtering). Those belong in the notifier.
- Use `const` constructors wherever possible — reduces rebuilds.

### NDS integration when present

When `nds` and `widget_map` are non-null AND a page has an NDS element associated:

- For each NDS element with `widget_map.decision == "USE_AS_IS"`: import the existing widget from `widget_map.<id>.file` and instantiate it with the NDS-derived props.
- For each `ADAPT` decision: call the widget with the new optional params per `widget_map.<id>.changes`.
- For each `CREATE_NEW` decision: instantiate the freshly-created widget from `widgets_new`.

## 4. Routes

Modify `config.routing.router_path` to register new routes. Pattern depends on the consumer's router package:

### GoRouter

```dart
GoRoute(
  path: '/example',
  builder: (context, state) => const ExamplePage(),
),
```

Insert in the routes list in alphabetical order of `path`. Preserve existing routes verbatim — never reorder or rewrite them.

### Other routers

Read the existing pattern in `config.routing.router_path` and follow it exactly. If the consumer uses AutoRoute, generate the AutoRoute-specific declaration. The slash command guarantees `config.routing.package` matches the actual router in use.

## 5. Widget tests

For each page, write a widget test covering EVERY state in `PageSpec.states`:

```dart
void main() {
  group('<NamePage>', () {
    testWidgets('shows loading indicator', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            <repositoryProvider>.overrideWithValue(
              Fake<Repo>(items: []),
            ),
          ],
          child: const MaterialApp(home: <Name>Page()),
        ),
      );
      await tester.pump();          // one frame — loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error when repository fails', (tester) async { ... });
    testWidgets('shows empty state when no items', (tester) async { ... });
    testWidgets('renders data when loaded', (tester) async {
      await tester.pumpWidget(...);
      await tester.pumpAndSettle();  // wait for async
      expect(find.text('Item 1'), findsOneWidget);
    });
  });
}
```

### Test rules (`config.testing`)

- **Override target:** `repository`, NEVER notifier. Read from `config.testing.override_target`; the rule is the rule because mocking the notifier hides bugs in the notifier logic.
- **Fakes:** `FakeXxxRepository implements XxxRepository` under `config.testing.fakes_path`. Generated when missing. No mocktail unless `prefer_fakes_over_mocks: false`.
- **Pattern:** AAA when `pattern: aaa`.
- **`pump()`** to verify the loading state (one frame). **`pumpAndSettle()`** for the final state.

## Output report

Write `<run_directory>/presentation_impl.md`:

```markdown
# Presentation Implementation: <ticket_id>

## Providers Created
- <path> — state: <Name>State (enum <Name>Status)

## Pages Created
- <path> — states: [<list>]

## Widgets Created (CREATE_NEW)
- <path>

## Widgets Reused (from widget_map)
- USE_AS_IS: <list of widget names + files>
- ADAPT: <list with the optional params added>

## Routes Registered
- <list of routes added to router file>

## Theme Tokens Used
- USE_EXACT: <list of tokenName, count>
- USE_CLOSEST: <list with delta_pct>
- CREATE_NEW (TODO): <list of raw hex values that need theme entries>

## Tests Created
- <path> — <N> tests, <states covered>
- <fakes_path>/fake_<repo>.dart — generated

## Dependencies Required (NOT auto-added)
- flutter_svg: ^X.Y.Z   ← needed when SvgPicture is used
- lottie: ^X.Y.Z        ← needed when Lottie is used

## files_changed
<one absolute or project-relative path per line>

## metrics
- providers_count: <N>
- pages_count: <N>
- widgets_created_count: <N>
- widgets_reused_count: <N>
- routes_count: <N>
- tests_count: <N>
- lines_generated: <N>
- estimated_coverage: <float>
```

## CodeGenResult

Return the standard `CodeGenResult`. `metrics` includes everything in the report's `metrics` section.

## Hard rules (always apply)

- All [`../../_common/layout-decision-tree.md`](../../_common/layout-decision-tree.md) rules apply.
- All [`../../_common/flutter-defaults.md`](../../_common/flutter-defaults.md) rules apply.
- Riverpod-manual invariants (above) apply.
- `config.architecture.layers.presentation.forbid_imports` is never violated.
- Generated tests follow `config.testing` exactly.

## What this prompt MUST NOT do

- ❌ Generate code that imports from the consumer's infrastructure layer (forbidden by `presentation.forbid_imports`).
- ❌ Use `@riverpod`, `build_runner`, or `.g.dart` regardless of NDS or spec content.
- ❌ Modify the consumer's `pubspec.yaml`. Document new dependencies in the report.
- ❌ Override notifiers in widget tests. Override repositories.
- ❌ Embed magic numbers for sizing — use the responsive sizing rules from `_common/`.
- ❌ Use raw hex literals when a theme token resolves — but DO emit them with a TODO comment when no token matches (CREATE_NEW from color_map).
