# `asana/` — Ticket Source Adapter

Implements [`TicketSourceAdapter`](../../../contracts/ticket_source_adapter.dart) for Asana.

## When this adapter is selected

`/analyze-ticket` selects this adapter when:

- `.alea.yaml::ticket_source.adapter == "asana"`, AND
- the ticket ref provides a `ticketId` (e.g. `DEV-1234`).

If `/analyze-ticket` is invoked with `--ticket-file <path>`, the `file/` adapter takes over regardless of config — see [`../file/README.md`](../file/README.md).

## Output

This adapter returns a `RawTicketPayload` (untyped map). Core (`/analyze-ticket`) then:

1. Applies PII sanitization (RFC, CURP, CLABE, card, phone).
2. Classifies `type` (feature / bugfix) from title + description keywords.
3. Extracts structured fields (`affected_layers`, `affected_files`, type-specific blocks) from the payload + consumer project scan.
4. Writes `.pipeline/runs/<ticket_id>/analysis.json` per [`../../../contracts/schemas/analysis.schema.yaml`](../../../contracts/schemas/analysis.schema.yaml).

The adapter does NOT sanitize, classify, or extract — those are core's concerns.

## Dependencies

- An MCP server named `mcp__claude_ai_Asana` must be registered in the consumer's Claude Code config. The adapter does not authenticate Asana directly — it relies on the MCP server to be already authenticated.
- Optional consumer config under `ticket_source.config`:
  - `asana.workspace_id` — scope task lookup to a specific workspace.
  - `asana.project_id` — further scope to a project (faster lookup, fewer false matches).

## Conformance to RawTicketPayload

| Common field | Asana source | Notes |
|---|---|---|
| `raw_title` | `task.name` | Required — empty title is a failure. |
| `raw_description` | `task.notes` (HTML stripped) | Required. |
| `raw_acceptance` | Markdown parse of "Criterios de aceptación" / "Acceptance Criteria" section in `task.notes` | Null if no parseable section found; core then falls back to inferring from description. |
| `raw_attachments` | `task.attachments[*]` mapped to `{kind, uri, description}` | `kind` resolved by URL pattern: figma.com → `link` (with `description: "figma"` hint); png/jpg/gif → `image`; else `link`. |
| `raw_priority` | `task.custom_fields.priority.enum_value.name` or `null` | |
| `raw_assignee` | `task.assignee.name` or `null` | |
| `raw_labels` | `task.tags[*].name` | |
| `raw_url` | `task.permalink_url` | Required when reachable. |
| `source_metadata.gid` | `task.gid` | Asana's internal task identifier. Surfaced for traceability. |
| `source_metadata.workspace_gid` | `task.workspace.gid` | |

## Failure modes

| Condition | Behavior |
|---|---|
| MCP server not registered / unauthenticated | Throw `TicketFetchException(adapter: "asana", reason: "MCP unavailable")`. Core may fall back to file adapter if `--ticket-file` was provided. |
| Ticket id not found | Throw `TicketFetchException(reason: "Task DEV-XXXX not found in workspace")`. |
| Ambiguous ticket id (multiple matches) | Throw `TicketFetchException(reason: "Multiple tasks match DEV-XXXX: <list>")`. Core surfaces the candidate list to the user. |
| Network / transient | Retry once with 2s backoff; on second failure, raise. |

## Why this adapter does so little

Adapter responsibility = transport. Anything that applies regardless of source (PII rules, type classification, layer inference) lives in core. This keeps each new adapter (Linear, Jira, file) tiny: define the field mapping table above, the failure modes, and the conformance checks. No business logic.

## Implementation

See [`adapter.md`](adapter.md) for the step-by-step prompt that `/analyze-ticket` invokes when this adapter is selected.

## Fixtures

(TBD — when the asana MCP fixture format is decided, fixtures live under `fixtures/`.)
