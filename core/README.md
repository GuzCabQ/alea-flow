# `core/` — Orchestration

Project-agnostic slash commands that drive the ticket-to-MR flow. Core knows the **shape** of the pipeline (analyze → design → implement → gate → MR → handoff) and the **state machine** that resumes runs. It does not know how Asana works, what Riverpod looks like, or where a project's layers live.

## What lives here

- `commands/` — the slash commands (`pipeline.md`, `analyze-ticket.md`, etc.). Each delegates to an adapter for anything project-specific.
- `scripts/` — operational scripts that work across consumers (metrics aggregation, etc.).

## What does NOT live here

- Any reference to `my_app`, `lib/src/domain/`, `Notifier`, GoRouter, or any other the reference consumer-specific value.
- Any direct call to Asana, Figma, or any external system. Those are routed through adapters.
- Any analyzer or gate logic. Those have their own folders.

## Contract with the rest of the package

| Module | How core uses it |
|---|---|
| `contracts/` | Reads schemas to know what shape artifacts must have. |
| `adapters/ticket_source/` | Looked up by name from `.alea.yaml`; invoked from `/analyze-ticket`. |
| `adapters/design_source/` | Looked up by name; invoked from `/design-feature`. |
| `adapters/code_gen/` | Looked up by name; invoked from `/implement-*`. |
| `analyzers/`, `gates/` | Run by `/run-gates` and `/review-feature` based on `.alea.yaml` selection. |
| `config/` | Reads consumer `.alea.yaml` once at the start of every `/pipeline` invocation. |

Slash commands stay short (≤300 lines) and prescriptive. Anything that grows beyond that is a sign a concern leaked out of an adapter or analyzer and should be pushed back down.
