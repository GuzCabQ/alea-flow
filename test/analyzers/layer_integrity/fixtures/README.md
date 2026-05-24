# Layer integrity test fixtures

Synthetic mini-project mimicking a typical layered Flutter codebase. Used
by [`../analyzer_test.dart`](../analyzer_test.dart).

## Structure

```
fixtures/
└── lib/src/
    ├── domain/
    │   ├── valid_pure.dart                            ← 0 issues
    │   ├── violation_imports_infra.dart               ← 1 blocker
    │   ├── violation_imports_flutter.dart             ← 1 blocker
    │   └── violation_imports_presentation_relative.dart  ← 1 blocker (tests relative imports)
    ├── infrastructure/
    │   ├── valid_imports_domain.dart                  ← 0 issues
    │   └── violation_imports_presentation.dart        ← 1 blocker
    └── presentation/
        ├── valid_imports_domain.dart                  ← 0 issues
        └── violation_imports_infra.dart               ← 1 blocker
```

## Why these files don't need to be syntactically valid Flutter

The analyzer parses imports only — class bodies are irrelevant. Each fixture has
a minimal class declaration so the file parses as a Dart compilation unit. None
of these files need to compile against real Flutter — they exist only as input
to `package:analyzer`'s AST parser.

## The fixture's package name

The fixtures use `package:sample_app/...` imports as a representative
package URI. The test config supplied to the analyzer sets
`project.package_name: sample_app` to match. Other tests that need a
different package name can build their own config; they don't have to reuse
these fixture files.
