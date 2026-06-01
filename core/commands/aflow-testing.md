---
description: Displays the effective testing conventions for the consumer project, derived from .alea.yaml::testing, including framework, fakes directory, test pattern, and mock preferences.
---
# `/aflow-testing` — Testing Conventions Reference

Project-agnostic reference for how ALEA expects consumer projects to write tests. The actual rules come from `.alea.yaml::testing` and `config.testing`-aware analyzers (`testing` analyzer enforces them).

## Conventions ALEA respects

| Convention | Source | Default value |
|---|---|---|
| Test framework | `config.testing.framework` | `flutter_test` |
| Fakes directory | `config.testing.fakes_path` | `test/fakes/` |
| Test pattern | `config.testing.pattern` | `aaa` (Arrange / Act / Assert) |
| What widget tests override | `config.testing.override_target` | `repository` |
| Prefer fakes over mocks | `config.testing.prefer_fakes_over_mocks` | `true` |
| Fake class naming | `config.testing.fake_class_pattern` | `Fake{Name}Repository` |

## When invoked

```
/aflow-testing
```

Displays the current effective conventions for the consumer's project. Useful before writing tests by hand.

## Steps

### 1. Load config

Read `.alea.yaml`; resolve `config.testing.*`.

### 2. Display the active rules

```
══════════════════════════════════════════════
Testing Conventions (from .alea.yaml)
══════════════════════════════════════════════
Framework:              <framework>
Fakes path:             <fakes_path>
Pattern:                <pattern>
Override target:        <override_target>   ← override THIS in widget tests, never the notifier
Prefer fakes over mocks: <true | false>
Fake naming:            <fake_class_pattern>

Reference docs:
  Testing guide:        <config.docs.testing_conventions or "not declared">
══════════════════════════════════════════════

The `testing` analyzer enforces:
  1. Every source file under a configured layer path has a matching test file
     at <projectRoot>/test/<same-relative-path>_test.dart.
  2. Test files don't import package:mockito or package:mocktail
     (when prefer_fakes_over_mocks = true).

Code-gen adapters generate tests following these conventions automatically
when /implement-* runs. Manual tests should follow the same rules.
```

### 3. Quick patterns

#### Widget test (Riverpod manual + repository override)

```dart
testWidgets('shows loaded state', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        exampleRepositoryProvider.overrideWithValue(
          FakeExampleRepository(items: [/* fixture data */]),
        ),
      ],
      child: const MaterialApp(home: ExamplePage()),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Item 1'), findsOneWidget);
});
```

#### Domain test

```dart
test('Email factory rejects invalid input', () {
  expect(() => Email.create('not-an-email'), throwsFormatException);
});
```

#### Repository contract test

```dart
// In test/fakes/fake_example_repository.dart
class FakeExampleRepository implements ExampleRepository {
  FakeExampleRepository({this.items = const []});
  final List<Entity> items;

  @override
  Future<Entity> getById(String id) async =>
      items.firstWhere((e) => e.id == id);
}
```

## What this command does NOT do

- ❌ Modify `config.testing` — those values are consumer-controlled in `.alea.yaml`.
- ❌ Generate test files. That's the code-gen adapter's job.
- ❌ Run any test. Use `flutter test` directly for that.
