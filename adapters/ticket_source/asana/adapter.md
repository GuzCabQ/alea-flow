# Asana Adapter — Fetch Prompt

This prompt is invoked by `/analyze-ticket` after it determines the asana adapter is selected. The prompt's job is to populate a `RawTicketPayload` and hand it back. It does NOT write `analysis.json` and does NOT do PII sanitization or classification — those are core's responsibilities.

## Inputs

- `ticket_id` — e.g. `DEV-1234`. Passed by `/analyze-ticket`.
- `config.ticket_source.config.asana.workspace_id` — optional, from `.alea.yaml`.
- `config.ticket_source.config.asana.project_id` — optional, from `.alea.yaml`.

## Steps

### 1. Locate the Asana task

Use the typeahead/search MCP tool to find the task whose readable id matches `ticket_id`:

```
mcp__claude_ai_Asana_2__asana_typeahead_search(
  query = ticket_id,
  workspace = workspace_id        # if provided
)
```

If `workspace_id` is set, restrict to that workspace. If `project_id` is set, additionally filter results to that project.

**Disambiguation rules:**

- Zero matches → throw `TicketFetchException(adapter: "asana", reason: "Task <ticket_id> not found")`.
- One match → proceed with its `gid`.
- Multiple matches → throw `TicketFetchException(reason: "Multiple tasks match <ticket_id>: <comma-separated permalinks>")`. Do NOT pick one heuristically.

### 2. Fetch task detail

```
mcp__claude_ai_Asana_2__asana_get_task(gid = <resolved_gid>)
```

Capture: `name`, `notes`, `assignee`, `tags`, `custom_fields`, `permalink_url`, `workspace.gid`.

### 3. Fetch attachments

```
mcp__claude_ai_Asana_2__asana_get_attachments_for_object(parent_gid = <gid>)
```

For each attachment, map to `{kind, uri, description}`:

| URL pattern | `kind` | `description` |
|---|---|---|
| Contains `figma.com` | `link` | `"figma"` |
| Extension `.png`, `.jpg`, `.jpeg`, `.webp`, `.gif` (host not figma) | `image` | original filename |
| Extension `.pdf`, `.doc`, `.docx`, `.xlsx`, `.csv` | `document` | original filename |
| Anything else | `link` | host name |

### 4. Parse acceptance criteria from notes

Scan `notes` (after HTML strip) for a section whose heading matches `^#+\s*(Criterios de aceptaci[oó]n|Acceptance Criteria|Success Criteria)\s*$` (case-insensitive).

If found: every line in that section starting with `-`, `*`, or `1.` (and variants) is one criterion. Strip the bullet/number prefix and any trailing whitespace.

If not found: leave `raw_acceptance: null`. Core will infer from description.

### 5. Detect figma links in notes body

In addition to figma attachments, scan `notes` for `https://www.figma.com/(file|design|proto)/[a-zA-Z0-9]+` URLs. For each match found that is NOT already in `raw_attachments`, append:

```yaml
{ kind: link, uri: <url>, description: "figma" }
```

### 6. Map remaining fields

| Common field | Source |
|---|---|
| `raw_title` | `task.name` (trim whitespace; reject if empty) |
| `raw_description` | `task.notes` after HTML strip |
| `raw_priority` | `task.custom_fields[*].name == "Priority"` → `.enum_value.name` (lowercased); else null |
| `raw_assignee` | `task.assignee.name` or null |
| `raw_labels` | `task.tags[*].name` |
| `raw_url` | `task.permalink_url` |

### 7. Build source_metadata

```yaml
source_metadata:
  gid: <task.gid>
  workspace_gid: <task.workspace.gid>
  fetched_at: <ISO8601 now>
  adapter_version: "1.0.0"
```

### 8. Return the payload

Return the assembled `RawTicketPayload` map to `/analyze-ticket`. Do NOT write any file. Do NOT redact anything. The caller will sanitize and persist.

## Error handling

Wrap any MCP tool failure into `TicketFetchException(adapter: "asana", reason: <descriptive>)`. Do not swallow errors — `/analyze-ticket` decides whether to fall back to the file adapter (only if `--ticket-file` was passed).

## What this prompt MUST NOT do

- ❌ Write to disk. The payload is returned in memory.
- ❌ Apply PII redaction. That's core's policy, applied uniformly across adapters.
- ❌ Classify the ticket type. That's core's logic based on payload + project state.
- ❌ Scan the consumer's codebase. The adapter only knows Asana.
- ❌ Decide between asana and file. That decision was already made before this prompt is invoked.
