# `core/` — Orchestration

Project-agnostic slash commands that drive the ticket-to-MR flow. Core knows the **shape** of the pipeline (analyze → design → implement → gate → MR → handoff) and the **state machine** that resumes runs. It does not know how Asana works, what Riverpod looks like, or where a project's layers live.

## What lives here

- `commands/` — the slash commands (`aflow-pipeline.md`, `aflow-analyze-ticket.md`, etc.). Each delegates to an adapter for anything project-specific.

## Standard config preamble (single source — do not re-specify per command)

Every command's first step is the same and is defined ONCE here; commands
reference this section instead of repeating it:

> **Load config.** Read `.alea.yaml` from the consumer project root. Validate it
> (the loader rejects malformed config). Stop with the offending field path on
> any error.

## Verification primitives (call code, don't re-specify in prose)

Commands MUST invoke these tested CLI commands rather than reproducing their
logic by hand (the "golden rule" — code-verified beats AI-claimed):

| Primitive | Replaces (prose) | Used by |
|---|---|---|
| `aflow redact` | hand-applied PII regex | `/aflow-analyze-ticket` |
| `aflow validate-artifact --schema <n>` | "validate against schema by eye" | `/aflow-analyze-ticket`, `/aflow-design-feature` |
| `aflow check-files-changed` | trusting an AI-authored `files_changed` | `/implement-*`, `/aflow-create-mr` |
| `aflow metrics` | hand-computed circuit-breaker arithmetic | `/aflow-pipeline`, `/aflow-pipeline-feedback` |
| `aflow analyze` | re-implementing analyzer rules | `/aflow-run-gates`, `/aflow-review-feature` |
| `aflow graph --ensure-fresh` + `aflow graph-query impact/neighbors/god-nodes` | blast radius traced by hand / "what does this touch" by eye | `/aflow-analyze-ticket`, `/aflow-design-feature`, `/aflow-review-feature`, `/aflow-run-gates` |
| `aflow graph-query structure/unlayered` | layer structure + code outside layers, eyeballed | `/aflow-complete-config` |
| `aflow graph-query state-flow` | "which widgets watch this provider/controller", guessed | `/aflow-design-feature`, `/aflow-review-feature` |

## What does NOT live here

- Any reference to `my_app`, `lib/src/domain/`, `Notifier`, GoRouter, or any other the reference consumer-specific value.
- Any direct call to Asana, Figma, or any external system. Those are routed through adapters.
- Any analyzer or gate logic. Those have their own folders.

## Contract with the rest of the package

| Module | How core uses it |
|---|---|
| `contracts/` | Reads schemas to know what shape artifacts must have. |
| `adapters/ticket_source/` | Looked up by name from `.alea.yaml`; invoked from `/aflow-analyze-ticket`. |
| `adapters/design_source/` | Looked up by name; invoked from `/aflow-design-feature`. |
| `adapters/code_gen/` | Looked up by name; invoked from `/implement-*`. |
| `analyzers/`, `gates/` | Run by `/aflow-run-gates` and `/aflow-review-feature` based on `.alea.yaml` selection. |
| `config/` | Reads consumer `.alea.yaml` once at the start of every `/aflow-pipeline` invocation. |

Slash commands stay short (≤300 lines) and prescriptive. Anything that grows beyond that is a sign a concern leaked out of an adapter or analyzer and should be pushed back down.
