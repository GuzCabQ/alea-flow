# `adapters/ticket_source/`

Adapters that turn a ticket identifier into a structured `analysis.json` for the rest of the pipeline.

## Contract

Every folder here implements `TicketSourceAdapter` from [`../../contracts/ticket_source_adapter.dart`](../../contracts/ticket_source_adapter.dart) (TBD).

Inputs:
- A ticket id (`DEV-1234`) OR a file path (`./tickets/DEV-1234.md`).
- `ProjectConfig`.

Output:
- A `RawTicketPayload` (untyped map) returned in memory to `/analyze-ticket`.

The adapter does NOT write `analysis.json`. Core (`/analyze-ticket`) takes the payload, applies PII sanitization, classifies the ticket type, extracts structured fields (`affected_layers`, `affected_files`, `new_components`, etc.), and writes `.pipeline/runs/<id>/analysis.json` per [`../../contracts/schemas/analysis.schema.yaml`](../../contracts/schemas/analysis.schema.yaml).

## RawTicketPayload — common shape

Every adapter MUST return a map with this shape. Fields prefixed with `raw_` are the un-processed inputs to core; their values are mapped to source-specific fields by each adapter.

```yaml
raw_title:         string                              # required, non-empty
raw_description:   string                              # required, non-empty (≥ 20 chars)
raw_acceptance:    list<string> | null                 # null when source has no parseable section
raw_attachments:   list<{kind, uri, description?}>     # may be empty list
raw_priority:      string | null                       # null when not provided
raw_assignee:      string | null
raw_labels:        list<string>                        # may be empty list
raw_url:           string | null                       # back-link to source system
source_metadata:   map<string, any>                    # adapter-specific extras (gid, file_path, etc.)
```

Attachment `kind` values: `link`, `image`, `document`, `video`, `other`. Figma URLs always get `kind: link` with `description: "figma"` (see the inference table in each adapter's README).

## Folders

| Folder | Source | Status |
|---|---|---|
| `asana/` | Asana MCP server | Primary adapter (port of current `analyze-ticket.md` Asana flow) |
| `file/` | Local markdown/JSON file passed via `--ticket-file` | Always present (used for testing and offline runs) |
| `linear/` | Linear MCP/API | Stub for v1 |
| `jira/` | Jira REST API | Not planned for v1 |

## Why this is its own family

Two reasons:

1. **Credentials and transport.** Each ticket system has different auth, rate limits, and field shapes. Keeping them as adapters prevents `core/` from ever knowing about API tokens or system-specific quirks.
2. **PII sanitization is policy, not transport.** The Mexico-specific patterns (RFC, CURP, CLABE, card, phone) live in `core/commands/analyze-ticket.md` because they apply regardless of source. The adapter only handles fetch + parse; redaction happens in core before anything is written to disk.

## Adding a new adapter

1. Create `adapters/ticket_source/<system>/`.
2. Implement `TicketSourceAdapter.fetch(ticketId, config) → RawTicket`.
3. Map raw fields to the `analysis.schema.yaml` shape.
4. Add `<system>_test.dart` with a fixture ticket payload.
5. Declare the adapter selectable in `ticket_source.adapter` in the project config schema.
