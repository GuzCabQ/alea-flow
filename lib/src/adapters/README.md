# `lib/src/adapters/` — Executable adapters

Executable Dart implementations of the ports declared in `lib/src/contracts/`.
Each adapter lives under its family directory and implements the
corresponding contract interface.

Layout convention:

```
lib/src/adapters/
  <family>/                # token_catalog, ticket_source, design_source, …
    <impl>/                # dart_source, json, asana, figma, …
      adapter.dart         # implements the contract
      README.md            # adapter-specific knobs and conventions
    factory.dart           # selects an impl by name from ProjectConfig
```

## Boundary rules (enforced by PackageBoundaryAnalyzer)

- ✅ Adapters MAY import from `lib/src/contracts/` (the ports they implement).
- ✅ Adapters MAY import from `lib/src/matching/` (pure libraries).
- ✅ Adapters MAY use `dart:io`, file/network/process — they are the outer ring.
- ✅ Adapters MAY import other adapters within the same family via the family
  factory.
- ❌ Adapters MUST NOT be imported by `lib/src/core/` (would couple
  orchestration to specific external systems — see ADR-0001 invariant 4).
- ❌ Adapters MUST NOT be imported by `lib/src/analyzers/` (would invert the
  dependency direction — see ADR-0001 invariant 2).

## Distinction from `alea/adapters/` (top-level)

The top-level `alea/adapters/` directory contains **markdown prompts** read
by skills. The `lib/src/adapters/` directory you are in contains **Dart
code**. The two are complementary: prompts describe behavior to the LLM;
Dart code provides deterministic resolution where the LLM should not
hallucinate.
