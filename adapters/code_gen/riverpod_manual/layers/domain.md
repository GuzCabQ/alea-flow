# Domain Layer Generation (Riverpod Manual)

Generates pure Dart code for the domain layer: entities, value objects, repository contracts. **No Flutter imports. No codegen. No external dependencies beyond `dart:*`.**

## Inputs

From the `CodeGenRequest`:

- `spec.domain.entities` — list of `EntitySpec` per [`spec.schema.yaml`](../../../../contracts/schemas/spec.schema.yaml).
- `spec.domain.value_objects` — list of `ValueObjectSpec`.
- `spec.domain.repository_contracts` — list of `RepositoryContractSpec`.
- `config.architecture.layers.domain.paths` — where to write files.
- `config.architecture.layers.domain.forbid_imports` — what the generated code must NOT import.

## Output

Files written under the domain layer path. For each entity / value object / repository contract, one file:

```
<domain_path>/
├── entities/
│   ├── <entity_name>.dart
│   └── ...
├── value_objects/
│   ├── <vo_name>.dart
│   └── ...
└── repositories/
    ├── <repo_name>.dart                    ← abstract class
    └── ...
```

Subfolder layout follows the consumer's existing domain organization. If `<domain_path>/entities/` already exists, write there; otherwise create. Same for value_objects and repositories.

## Generation rules

### Entities

For each `EntitySpec`:

```dart
class <Name> {
  const <Name>({
    required this.<field1>,
    this.<field2>,
    // ...
  });

  final <Type1> <field1>;
  final <Type2>? <field2>;
  // ...

  // copyWith for every entity — Riverpod manual convention.
  <Name> copyWith({
    <Type1>? <field1>,
    <Type2>? <field2>,
  }) => <Name>(
    <field1>: <field1> ?? this.<field1>,
    <field2>: <field2> ?? this.<field2>,
  );

  // Equality + hashCode when entity will be compared (rule of thumb: ALWAYS).
  @override
  bool operator ==(Object other) =>
      other is <Name> &&
      other.<field1> == <field1> &&
      other.<field2> == <field2>;

  @override
  int get hashCode => Object.hash(<field1>, <field2>);
}
```

If `EntitySpec.validations` is non-empty, add an assert in the constructor body:

```dart
const <Name>(...)
    : assert(<validation predicate>, '<readable error>'),
      assert(...);
```

For validations too complex for `assert` (e.g. cross-field checks involving negations), use a private `_invariant()` method called from the constructor — but only when truly necessary.

### Value objects

Same shape as entities but with stricter invariants. Every value object MUST:

- Be `const`-constructable.
- Have a `private` constructor and a public factory that validates: `factory <Name>.create(...) { ... }`.
- Implement `==` and `hashCode` based on ALL fields (value objects are value-equal by definition).
- Have a `toString` override for debugging.

Example:

```dart
class Email {
  const Email._(this.value);

  final String value;

  factory Email.create(String input) {
    final trimmed = input.trim();
    if (!_pattern.hasMatch(trimmed)) {
      throw FormatException('Invalid email: $input');
    }
    return Email._(trimmed);
  }

  static final _pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  bool operator ==(Object other) => other is Email && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Email($value)';
}
```

### Repository contracts (abstract classes)

```dart
abstract class <Name> {
  <signature1>;
  <signature2>;
  // ...
}
```

Signatures come verbatim from `RepositoryContractSpec.methods[*].signature`. Add documentation comments above each method when `throws` is non-empty:

```dart
abstract class ExampleRepository {
  /// Throws [NotFoundException] when no entity with [id] exists.
  /// Throws [NetworkException] on transport failure.
  Future<Entity> getById(String id);
}
```

## Forbidden imports

NEVER import:

- `package:flutter/*` (domain is pure Dart).
- Any path under the consumer's `infrastructure` or `presentation` layer (per `config.architecture.layers.domain.forbid_imports`).
- Any `*.g.dart` (no codegen).
- External packages that pull in Flutter transitively. Allowed: pure Dart packages from pub (`collection`, `meta`, `equatable` — though `equatable` is discouraged since we use manual `==`).

The `layer_integrity` analyzer (step 4) re-verifies this. Don't rely on the analyzer — get it right at generation time.

## Tests

For each entity/value object/repository contract, generate unit tests under the consumer's test path mirroring the source layout:

```
test/<feature_slug>/
├── entities/
│   └── <entity_name>_test.dart
├── value_objects/
│   └── <vo_name>_test.dart
└── repositories/
    └── <repo_name>_test.dart           ← contract test (verifies any impl satisfies the contract)
```

Test patterns:

- Entity test: construct, copyWith permutations, equality. AAA.
- Value object test: factory validation (success + every failure path), equality, toString.
- Repository contract test: parameterized helper that any impl can run against.

`config.testing.fakes_path` is where contract-test helpers live (e.g. `test/fakes/<repo>_contract_test.dart`).

## Output report

Write `<run_directory>/domain_impl.md`:

```markdown
# Domain Implementation: <ticket_id>

## Entities Created
- <relative path to entity file> — fields: [<list>]; validations: <count>

## Value Objects Created
- <path> — invariants: <count>

## Repository Contracts Created
- <path> — methods: <count>

## Tests Created
- <path> — <N> tests covering [entity construction | factory validation | contract conformance | ...]

## files_changed
- <path>
- <path>
- ...

## metrics
- entities_count: <N>
- value_objects_count: <N>
- repositories_count: <N>
- lines_generated: <N>
- estimated_coverage: <X.XX>     # estimate based on test density; visual_fidelity / coverage gate verifies
```

The `files_changed` section is machine-readable: one path per line under that header. `/pipeline` reads this list to stage commits.

## CodeGenResult

Return to the dispatcher:

```
CodeGenResult(
  createdFiles: <list of newly-created absolute paths>,
  modifiedFiles: <list of touched-but-existing absolute paths — usually empty for domain>,
  reportPath: <run_directory>/domain_impl.md,
  metrics: {
    'entities_count': <N>,
    'value_objects_count': <N>,
    'repositories_count': <N>,
    'lines_generated': <N>,
    'estimated_coverage': <float>,
  },
)
```

## Determinism

Same spec → same Dart output bytewise. The order of declarations (entities → value objects → repositories) and the field order within each declaration MUST be stable and follow the spec's order. Tests rely on this for golden-file comparison.
