# ADR-0010 — CLI Consolidation: six subcommands, one binary, no exit() in libs

- **Status:** Accepted
- **Date:** 2026-05-23
- **Phase:** 9

## Context

The pre-redesign tooling shipped 22 separate Dart binaries
(`new_module.dart`, `match_color.dart`, `gen_primer.dart`,
`check_wiring.dart`, …). Each had its own argument parser, its own
help text, its own cold-start cost. Discovery was hard; help text drifted.

## Decision

### One binary, six subcommands

`bin/aflow.dart` is a 22-line shim that delegates to
`AleaCliRunner` (in `lib/src/cli/cli_runner.dart`). Subcommands:

| Subcommand | Purpose | Implementation |
|---|---|---|
| `analyze`   | Run analyzer registry, emit gate report.            | wraps `AnalyzerRunner` + builds the token catalog |
| `match`     | Resolve a hex/size/weight/metric against the catalog. | wraps the Phase 3 resolvers |
| `scaffold`  | Generate a feature scaffold.                         | wraps `CodeGenOrchestrator` |
| `inventory` | Scan widgets, emit JSON.                             | wraps `WidgetInventoryBuilder` |
| `journal`   | Inspect the run journal (summary or jsonl).          | reads `JsonlRunJournal` |
| `context`   | Build (or reuse) the context-packet.                 | wraps `ContextPacketBuilder` |

Each subcommand is a `Command<int>` from `package:args`. Adding a
seventh subcommand is one new file under `lib/src/cli/commands/` plus
one line in `AleaCliRunner._wire()`.

### No `exit()` in libraries

`AleaCliRunner.run(args)` returns `Future<int>`. The exit code is
forwarded by the `bin/aflow.dart` shim. Tests invoke the runner directly
and assert on the returned int — no subprocess spawning, no global
state.

### AOT native compile

`tool/compile.sh` runs `dart compile exe bin/aflow.dart -o bin/aflow`,
producing a ~10 MB native binary with sub-50ms cold start. Important
because skills invoke the CLI many times per run.

## Consequences

**Positive:**

- Discoverability: `aflow --help` lists every operation in one place.
- Performance: AOT native eliminates per-invocation Dart VM cold start.
- Testability: every subcommand has a smoke test in `test/cli/` that
  invokes the runner with synthetic argv and asserts on exit codes
  + side effects.
- Help text consistency: `package:args` `CommandRunner` enforces a
  uniform `alea help <command>` shape.

**Negative:**

- The runner imports from many layers (analyzers, adapters, services,
  contracts) — it's the outer ring. The boundary rules deliberately
  leave `lib/src/cli/` unconstrained.
- Argument names are not yet 100% consistent across subcommands
  (e.g. `--run-directory` vs `--output`). Documented as a follow-up
  for v1.1.

## References

- `bin/aflow.dart`.
- `lib/src/cli/cli_runner.dart`.
- `lib/src/cli/commands/{analyze,match,scaffold,inventory,journal,context}_command.dart`.
- `tool/compile.sh`.
- `test/cli/cli_runner_test.dart` — 11 smoke tests.
