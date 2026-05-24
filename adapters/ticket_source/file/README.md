# `file/` — Ticket Source Adapter (Local File)

Implements [`TicketSourceAdapter`](../../../contracts/ticket_source_adapter.dart) for local files.

## When this adapter is selected

Either:

1. `/analyze-ticket DEV-XXXX --ticket-file <path>` is invoked → this adapter is forced regardless of `.alea.yaml::ticket_source.adapter`. The flag wins.
2. `.alea.yaml::ticket_source.adapter == "file"` AND a ticket ref provides a `filePath` → selected by config.
3. The configured adapter (e.g. asana) failed AND `--ticket-file` was provided as fallback → selected as fallback.

## Why this adapter is always present

Two reasons:

1. **Testing.** Every analyzer, gate, and code-gen adapter test runs against a fixture ticket. The file adapter is the only one with no external dependencies, so tests use it.
2. **Offline runs.** When the consumer's ticket system is unreachable (network, auth lapse, MCP down), users can paste the ticket into a markdown file and continue working.

## Output

Same `RawTicketPayload` shape as other adapters — see [`../README.md`](../README.md).

## Supported formats

The adapter reads the file extension to choose a parser:

| Extension | Parser | Use when |
|---|---|---|
| `.md`, `.markdown` | Markdown section convention (below) | Hand-written or pasted tickets |
| `.json` | JSON matching `RawTicketPayload` directly | Tickets exported from a system that already normalizes |
| `.yaml`, `.yml` | YAML matching `RawTicketPayload` directly | Same |

JSON and YAML files are returned as-is after structural validation. Markdown is the interesting case — see below.

## Markdown convention

The adapter expects the following section structure. Section names are matched case-insensitively, with Spanish or English variants accepted.

```markdown
# {raw_title}

## {Descripción | Description}
{raw_description body — markdown allowed, may span multiple paragraphs}

## {Criterios de aceptación | Acceptance Criteria | Success Criteria}
- {criterion 1}
- {criterion 2}
- {criterion 3}

## {Adjuntos | Attachments}    <!-- optional -->
- [figma](https://www.figma.com/file/...)
- [screenshot](./local-image.png)

## {Prioridad | Priority}      <!-- optional -->
high

## {Etiquetas | Labels}        <!-- optional -->
- backend
- urgent
```

### Required sections

- `H1` heading → `raw_title`.
- A section named `Descripción`/`Description` → `raw_description`.
- A section named `Criterios de aceptación`/`Acceptance Criteria`/`Success Criteria` → `raw_acceptance` (list of bullet items, prefix stripped).

If any required section is missing, throw `TicketFetchException(adapter: "file", reason: "Missing section: <name>")`.

### Optional sections

- `Adjuntos`/`Attachments` — bullet list. Each item is one of:
  - Markdown link `[label](url)` → `{kind: <inferred>, uri: <url>, description: <label>}`.
  - Plain URL → `{kind: <inferred>, uri: <url>, description: null}`.
- `Prioridad`/`Priority` — single line; mapped to enum if recognized.
- `Etiquetas`/`Labels` — bullet list of plain strings.

`kind` inference follows the same URL pattern table as the asana adapter.

### Figma link detection

Even when not in an `Attachments` section, any `https://www.figma.com/(file|design|proto)/...` URL found in the description body is added to `raw_attachments` with `description: "figma"`.

## Implementation

See [`adapter.md`](adapter.md).

## Fixtures

- [`fixtures/example-feature.md`](fixtures/example-feature.md) — feature ticket with figma link and 3 acceptance criteria.
- [`fixtures/example-bugfix.md`](fixtures/example-bugfix.md) — bugfix ticket with no figma link.

These fixtures are used by every test that needs a representative ticket without network or MCP dependencies.

## What this adapter MUST NOT do

- ❌ Write to disk (purely a reader).
- ❌ Apply PII redaction.
- ❌ Infer ticket type, affected layers, or attempt to scan the consumer codebase.
- ❌ Resolve relative paths in attachments against any filesystem — `uri` is returned verbatim.
