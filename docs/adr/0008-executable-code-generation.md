# ADR-0008 — Executable Code Generation with Plan + Execute + Verify

- **Status:** Accepted
- **Date:** 2026-05-23
- **Phase:** 7

## Context

Pre-redesign code generation was a 1000-line procedural Dart script
(`new_module.dart` in HORUS) that mixed argument parsing, filesystem
operations, hardcoded path constants, 20+ inline template strings, and
`exit(1)` error handling. Cross-stack support required forking. Failed
generations left the project in inconsistent states.

ALEA needs code generation that:

1. Works across state-management stacks (Riverpod, Bloc, Provider,
   GetX, …) without forking.
2. Is idempotent — running generate twice on the same input is a no-op.
3. Rolls back atomically on failure.
4. Verifies generated code against the SAME analyzers that human code
   must satisfy.
5. Contains zero string concatenation to build Dart source.

## Decision

### Plan / Execute / Verify split

- **Adapter** (`CodeGenAdapter`) returns a `ScaffoldPlan` — immutable
  description of `GeneratedFile[]` and `WiringPatch[]`. Adapters do
  no I/O.
- **`ScaffoldExecutor`** applies the plan to disk:
  - `create` when the file doesn't exist.
  - `modify` when content differs (md5 comparison) — previous content
    captured for rollback.
  - `skip` when content matches existing.
- **`ScaffoldVerifier`** runs analyzers (default:
  `LayerIntegrityAnalyzer` + `WiringCohesionAnalyzer`) on the
  just-written files. Returns issues + a `passed` bool.
- **`CodeGenOrchestrator`** glues them together: build plan →
  execute → verify → rollback on failure.

### Template engine

`TemplateEngine.render(template, vars)` — mustache-like with
`{{name}}`, `{{name|fallback}}`, `{{!comment}}`. Templates are WHOLE
multi-line strings; the engine substitutes tokens via
`replaceAllMapped` without concatenation. Missing required variables
throw `TemplateRenderException` — typos in template names cannot
silently emit `{{accidental_typo}}` into generated source.

Templates are Dart `const String` constants in
`lib/src/adapters/code_gen/<style>/templates.dart` — separate file from
the adapter so editing the layout never touches Dart logic.

### Two reference adapters

- `RiverpodManualCodeGen`: state + notifier + screen for `Notifier<State>`.
- `BlocCodeGen`: sealed state + sealed event + bloc + screen.

Both consume the same `CodeGenRequest`, return their own `ScaffoldPlan`,
and produce files at paths declared by
`architecture.layers.<layer>.paths`.

## Consequences

**Positive:**

- Adding a new state-management style = new folder under
  `lib/src/adapters/code_gen/<style>/`. Zero changes to executor,
  verifier, orchestrator, or contracts.
- Rollback is byte-exact: a failed verifier guarantees the filesystem
  returns to its pre-generation state.
- Idempotency means `aflow scaffold demo` is safe to run repeatedly in
  CI — second run reports `skipped` for every file.
- Layer-integrity and wiring-cohesion analyzers automatically gate the
  generated code — humans and generators are held to the same bar.
- Cross-layer relative imports (e.g. `presentation/.../screen.dart`
  importing `domain/.../notifier.dart`) are computed from the
  declared paths — never hardcoded. Changing
  `architecture.layers.domain.paths` shifts the import without
  touching templates.

**Negative:**

- Adapter authors duplicate helper functions (`_pascal`, `_camel`,
  `_relativeImport`) across adapters. Justified by adapter
  independence: editing one adapter cannot break another.
- Templates are Dart `const String` constants, not external files.
  Easier distribution (no asset bundle) at the cost of one Dart edit
  per template change.

## References

- `lib/src/contracts/scaffolding.dart`.
- `lib/src/contracts/code_gen_adapter.dart`.
- `lib/src/scaffolding/template_engine.dart`.
- `lib/src/scaffolding/scaffold_executor.dart`.
- `lib/src/scaffolding/scaffold_verifier.dart`.
- `lib/src/scaffolding/code_gen_orchestrator.dart`.
- `lib/src/adapters/code_gen/{riverpod_manual,bloc}/`.
- 29 tests across scaffolding services + adapters.
