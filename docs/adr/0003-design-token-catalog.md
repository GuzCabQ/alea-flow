# ADR-0003 — Design Token Catalog: abstract over where tokens live

- **Status:** Accepted
- **Date:** 2026-05-23
- **Phase:** 2

## Context

The pre-redesign tooling read tokens from a hardcoded `StyleColors`
class in Dart source. Any project that named its tokens differently
(`Palette`, `AppColors`, JSON-based) was unsupported. Worse, tests had
to spin up a Dart parser even when they only needed a list of colors.

## Decision

Introduce a `DesignTokenCatalog` contract
(`lib/src/contracts/design_token_catalog.dart`) with a sealed
`DesignToken` hierarchy: `ColorToken`, `TypographyToken`, `SpacingToken`,
`NamedToken`. The catalog returns tokens by family.

Two adapters ship out of the box:

- `DartSourceTokenCatalogAdapter` — scans Dart source via AST. Class
  name comes from `theme.token_catalog.conventions.color_class`
  (default `StyleColors`). Recognizes `Color(0xFF…)`,
  `Color.fromARGB`, and `Color.fromRGBO` constructors.
- `JsonTokenCatalogAdapter` — reads a Style-Dictionary-style JSON tree.
  Walks nested maps, treats any node with a `value` key as a leaf.

Adapter selection happens via `buildTokenCatalog(config)` factory based
on `.alea.yaml::theme.token_catalog.adapter`.

## Consequences

**Positive:**

- Consumers swap data sources by editing one YAML field.
- Resolvers (Phase 3) and analyzers (Phase 4) consume the catalog
  through the contract — never the implementation. Adding a third
  source (`tokens-studio`, HTTP-backed, etc.) is a new adapter folder,
  no other code changes.
- The sealed `DesignToken` hierarchy makes resolver switches
  exhaustively type-checked.

**Negative:**

- Two adapters means two test fixtures. Manageable.
- `NamedToken.value` is `Object?` (free-form). Resolvers that consume
  custom families have to validate the shape themselves.

## References

- `lib/src/contracts/design_token_catalog.dart` — contract.
- `lib/src/adapters/token_catalog/dart_source/adapter.dart` — Dart-AST adapter.
- `lib/src/adapters/token_catalog/json/adapter.dart` — JSON adapter.
- `lib/src/adapters/token_catalog/factory.dart` — runtime selection.
- 45 tests across the family.
