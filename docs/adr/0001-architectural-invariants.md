# ADR-0001 — Architectural Invariants of ALEA

- **Status:** Accepted
- **Date:** 2026-05-23
- **Phase introduced:** 0 (Salvaguardas Arquitectónicas)

## Context

ALEA is a distributable Dart package whose purpose is to orchestrate the
ticket → MR pipeline for any Flutter consumer project (state-management
agnostic, ticket-source agnostic, design-source agnostic). Its long-term
value depends on the integrity of its internal layering — Ports & Adapters
plus a pure-math library that callers can import without dragging I/O.

The pre-redesign tooling that motivated ALEA drifted into a procedural
collection of 22 CLI binaries with hardcoded paths, inline string
templates, and no enforced internal boundaries. The intent of this ADR
is to make sure ALEA does not repeat that pattern.

## Decision

The following invariants are declared **non-negotiable**. They are
enforced by `PackageBoundaryAnalyzer` running against the ALEA tree on
every CI build (`dart run tool/check_alea_boundaries.dart`). The rules
live in `alea/.alea.yaml::architecture.package_boundaries`.

### Invariant 1 — Contracts purity

`lib/src/contracts/` may depend only on `dart:core`, `dart:async`,
`dart:convert`, and `package:meta`.

**Forbidden:**
`dart:io`, `dart:ffi`, `dart:mirrors`, `package:analyzer/`, `package:path/`,
`package:yaml/`, `package:args/`, anything under `package:alea/src/`.

**Rationale:** contracts are the most stable layer. They are imported by
both analyzers and adapters; any I/O or third-party dependency here forces
that cost on every consumer.

### Invariant 2 — Analyzer isolation

`lib/src/analyzers/` may not import from `lib/src/adapters/`.

**Rationale:** analyzers consume the contracts that adapters implement,
not the implementations themselves. Direct import would invert the
dependency arrow of the hexagonal design.

### Invariant 3 — Matching purity

`lib/src/matching/` (introduced in Phase 3) is a pure-math library: color
distance, fuzzy scoring, numeric quantization. It must remain importable
in any Dart context — including non-Flutter and AOT-restricted ones —
without pulling I/O or heavy dependencies.

**Forbidden:** `dart:io`, `dart:ffi`, `package:analyzer/`, `package:path/`,
`package:yaml/`, `package:args/`.

**Rationale:** matchers are also exposed via the CLI for direct use, but
the CLI plumbing layers them in `bin/`. The library itself must stay
side-effect-free.

### Invariant 4 — Core orchestration boundary

`lib/src/core/` (runner, registry, reporter, context, journal) may not
import directly from `lib/src/adapters/`. Adapter selection happens at
runtime via name lookup against `ProjectConfig`, never by static import.

**Rationale:** preserves the agnosticism of ALEA to any specific
external system (Asana, Figma, Riverpod, Bloc, GetX). Without this rule,
the core would silently bind to one set of adapters.

## Consequences

**Positive:**

- Any PR that violates these invariants fails CI before review.
- The bus factor of ALEA stays high: any contributor can read the four
  rules above and immediately know what is and is not allowed.
- ALEA's portability is enforced automatically; consumers can adopt the
  package knowing it will not pull unexpected dependencies.

**Negative:**

- Genuine refactors that need to reshuffle layers must update both the
  code and `.alea.yaml`; this ADR must be revised before relaxing any
  rule.
- The CI guard adds ~3 seconds to every build.

## Adding or relaxing a rule

1. Open a follow-up ADR (e.g. `0002-relax-matching-import-X.md`).
2. State the concrete need that motivates the change.
3. Update `alea/.alea.yaml::architecture.package_boundaries`.
4. Update this ADR's invariant list, leaving the original wording in a
   "Historical" section so the change is auditable.

## References

- Phase 0 of the implementation plan: PackageBoundaryAnalyzer (current).
- `alea/lib/src/analyzers/package_boundary/analyzer.dart` — enforcement.
- `alea/.alea.yaml` — declared boundaries.
- `alea/tool/check_alea_boundaries.dart` — CI guard.
- `alea/test/analyzers/package_boundary/analyzer_test.dart` — guarantees
  the analyzer behaves as specified.
