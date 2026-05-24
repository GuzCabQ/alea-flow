# ADR-0007 — Wiring Cohesion: config-driven DI/route registration check

- **Status:** Accepted
- **Date:** 2026-05-23
- **Phase:** 6

## Context

The pre-redesign tool `check_wiring.dart` was a 436-line script using
`String.contains` to verify that every `*Service` in the project was
registered in `lib/src/injector.dart` and every `*Screen` had a
matching `GetPage` in `controller_pages.dart`. It hardcoded GetX
conventions and substring matching, which both false-positives and
false-negatives.

ALEA needs a checker that:

1. Works across state-management stacks (Riverpod + go_router,
   Bloc + auto_route, GetX + GetPage, …) without code changes.
2. Is AST-based — no substring guessing.
3. Surfaces a clear "this class isn't registered" issue.

## Decision

New analyzer `WiringCohesionAnalyzer`
(`lib/src/analyzers/wiring_cohesion/analyzer.dart`). Reads
`architecture.wiring.rules[]` from `.alea.yaml`:

```yaml
architecture:
  wiring:
    rules:
      - name: services
        class_pattern: "*Service"
        manifest_file: lib/src/injector.dart
        registration_call: registerSingleton
      - name: routes
        class_pattern: "*Screen"
        manifest_file: lib/src/config/routes.dart
        registration_call: GoRoute        # or GetPage, AutoRoute…
```

Implementation:

- **Candidate discovery**: walks `architecture.layers.*.paths` (or
  `WiringRule.scanPaths` when set), parses every `.dart` file via AST,
  collects `ClassDeclaration` whose name matches `class_pattern` (glob:
  `*` at start/end/both).
- **Registration discovery**: parses the manifest file's AST. A
  `_RegistrationCollector` visitor walks `MethodInvocation` and
  `InstanceCreationExpression` nodes whose name matches
  `registration_call` (supports bare names like `registerSingleton`,
  dotted forms like `Get.put`, and type-argument forms like
  `registerSingleton<AuthRepository>(...)`).
- **Issue emission**: when a candidate doesn't appear in the
  registration set, emits `wiring_cohesion/<rule_name>/missing_registration`
  (severity blocker).

The analyzer ships zero presets — it does not know that
`registerSingleton` is get_it, or that `GoRoute` is go_router. The
consumer's `.alea.yaml` declares all of it.

## Consequences

**Positive:**

- Same analyzer covers every stack. The Phase 6 test suite proves it
  with three real-world fixture sets (Riverpod+go_router, Bloc+auto_route,
  GetX+GetPage) — zero analyzer changes between them.
- AST-based means refactors that change formatting don't break
  detection. Renaming a class IS caught (the class declaration shows
  up under the new name, the manifest still references the old).
- Glob patterns let consumers narrow the rule (e.g. `*Impl` to skip
  abstract bases).

**Negative:**

- Higher-order registration (e.g. iterating a list of classes and
  calling `register` in a loop) escapes detection. Documented in the
  troubleshooting section of `docs/CONSUMER_INTEGRATION.md`.
- Identifiers that happen to share a name with a class trigger a
  false positive (e.g. a local variable `AuthService` shadowing the
  type). Mitigation: PascalCase identifiers inside an argument tree
  are usually classes; misuse is rare.

## References

- `lib/src/analyzers/wiring_cohesion/analyzer.dart`.
- `lib/src/contracts/project_config.dart` — `WiringConfig`, `WiringRule`.
- `lib/src/core/config/loader.dart` — `_parseWiring`.
- `test/analyzers/wiring_cohesion/` — 10 tests with 3 fixture stacks.
