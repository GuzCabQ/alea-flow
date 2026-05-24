# Infrastructure Layer Generation (Riverpod Manual)

Generates DTOs (Data Transfer Objects) with hand-written JSON serialization and repository implementations that fulfill the domain contracts. **No codegen. No `@JsonSerializable`. No `.g.dart`.**

## Inputs

From the `CodeGenRequest`:

- `spec.data.dtos` — list of `DtoSpec` per [`spec.schema.yaml`](../../../../contracts/schemas/spec.schema.yaml).
- `spec.data.repositories` — list of `RepositoryImplSpec`.
- `spec.domain.entities` — for the DTO → entity mapping.
- `config.architecture.layers.infrastructure.paths` — where to write files.
- `config.architecture.layers.infrastructure.forbid_imports`.

## Output

```
<infrastructure_path>/
├── dtos/
│   ├── <dto_name>.dart
│   └── ...
└── repositories/
    ├── <repo_impl_name>.dart
    └── ...
```

## Generation rules

### DTOs

For each `DtoSpec`:

```dart
import '<domain entity path>';

class <Name> {
  const <Name>({
    required this.<field1>,
    this.<field2>,
    // ...
  });

  final <Type1> <field1>;
  final <Type2>? <field2>;
  // ...

  factory <Name>.fromJson(Map<String, dynamic> json) => <Name>(
    <field1>: json['<json_key1>'] as <Type1>,
    <field2>: json['<json_key2>'] as <Type2>?,
    // ...
  );

  Map<String, dynamic> toJson() => {
    '<json_key1>': <field1>,
    '<json_key2>': <field2>,
    // ...
  };

  <DomainEntity> toDomain() => <DomainEntity>(
    <domainField1>: <field1>,
    <domainField2>: <field2>,
    // ...
  );

  factory <Name>.fromDomain(<DomainEntity> entity) => <Name>(
    <field1>: entity.<domainField1>,
    <field2>: entity.<domainField2>,
    // ...
  );
}
```

#### JSON key mapping

`DtoSpec.json_fields[*]` declares each `{json, dart, type}` triple. Use these EXACTLY:

- `json_fields[*].json` is the wire key (snake_case from the API).
- `json_fields[*].dart` is the Dart field name (camelCase).
- `json_fields[*].type` is the Dart type (`String`, `int?`, `List<Foo>`, `DateTime`).

#### Type-specific parsing

| Dart type | `fromJson` pattern |
|---|---|
| `String` / `int` / `double` / `bool` | `json['k'] as Type` |
| nullable primitive | `json['k'] as Type?` |
| `DateTime` | `DateTime.parse(json['k'] as String)` |
| `DateTime?` | `json['k'] != null ? DateTime.parse(json['k'] as String) : null` |
| `List<Foo>` (Foo is a DTO) | `(json['k'] as List<dynamic>).map((e) => Foo.fromJson(e as Map<String, dynamic>)).toList()` |
| `List<String>` etc. | `(json['k'] as List<dynamic>).cast<String>()` |
| enum | helper `parseFooEnum(json['k'] as String)` (defined in the same file) |
| `Foo` (nested DTO) | `Foo.fromJson(json['k'] as Map<String, dynamic>)` |

`toJson` mirrors `fromJson`: `DateTime` → `.toIso8601String()`, nested DTO → `.toJson()`, etc.

### Repository implementations

For each `RepositoryImplSpec`:

```dart
import '<domain repository contract path>';
import '<dto paths>';
import '<api client dependency>';

class <Name> implements <ContractName> {
  const <Name>(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<Entity> getById(String id) async {
    final response = await _apiClient.get('/path/$id');
    final dto = ExampleDto.fromJson(response.data as Map<String, dynamic>);
    return dto.toDomain();
  }

  // implement every method from the contract
}
```

Endpoint paths come from `RepositoryImplSpec.endpoints[*]` when provided. When the spec doesn't declare an endpoint, the AI infers from the ticket description; emit a `// TODO: confirm endpoint <method> <path>` comment so the reviewer catches it.

### Forbidden imports

NEVER import:

- Any path under the consumer's `presentation` layer (per `config.architecture.layers.infrastructure.forbid_imports`).
- Any `*.g.dart`.
- Flutter framework — infrastructure is plain Dart that may use Flutter-aware HTTP packages (`dio`, `http`), but not widgets.

## Tests

For each DTO:

- `<feature>/dtos/<dto_name>_test.dart` — round-trip JSON test (parse a sample payload → toJson → equals the original), domain mapping test (`toDomain` and `fromDomain` are inverses).

For each repository implementation:

- `<feature>/repositories/<repo_impl_name>_test.dart` — integration-style tests with a fake `ApiClient`. Cover happy path + at least one failure path per method.

Test conventions per `config.testing`:

- Pattern: AAA (when `pattern: aaa`).
- Fakes path: `<config.testing.fakes_path>/fake_api_client.dart`.
- No mocktail unless `prefer_fakes_over_mocks: false` in config.

## Output report

Write `<run_directory>/infrastructure_impl.md` following the same shape as `domain_impl.md`, with sections:

- `## DTOs Created`
- `## Repository Implementations Created`
- `## Endpoint Mappings` (one per `RepositoryImplSpec.endpoints`)
- `## Tests Created`
- `## files_changed`
- `## metrics`

`metrics` includes: `dtos_count`, `repositories_count`, `lines_generated`, `estimated_coverage`.

## CodeGenResult

Return the standard `CodeGenResult` shape (see [`domain.md`](domain.md) for the template).

## Determinism

Same spec → same Dart output bytewise. Declaration order follows spec order; method order within an impl follows contract method order.
