---
description: Reads a ticket via the configured adapter, sanitizes PII, classifies the ticket type, extracts structured fields, and writes analysis.json validated against the analysis schema.
---
# `/aflow-analyze-ticket` — Analyze Ticket

Reads a ticket via the configured ticket-source adapter, applies PII sanitization, classifies the ticket type, extracts structured fields, and writes `.pipeline/runs/<ticket_id>/analysis.json` validated against [`contracts/schemas/analysis.schema.yaml`](../../contracts/schemas/analysis.schema.yaml).

## Usage

```
/aflow-analyze-ticket DEV-XXXX [--ticket-file <path>]
```

## Architecture

This command is the first phase of the pipeline. Its job split:

- **Core (this command):** PII sanitization, type classification, structured-field extraction, schema validation, persistence. Source-agnostic.
- **Ticket-source adapter (delegated):** how to fetch the raw payload from the system (Asana MCP, file read, Linear API, etc.). One adapter is selected from [`.alea.yaml::ticket_source.adapter`](../../config/examples/sample_app.yaml); the `--ticket-file` flag forces the `file/` adapter regardless of config.

The adapter returns a `RawTicketPayload` (see [`adapters/ticket_source/README.md`](../../adapters/ticket_source/README.md) for the shape). Core then transforms it into `analysis.json`.

## Steps

### 1. Parse arguments and load config

1. Extract `ticket_id` from the first token of `$ARGUMENTS`.
2. Detect optional flags: `--ticket-file <path>`.
3. Read `.alea.yaml` from the consumer project root.
   - If missing → `Error: .alea.yaml not found at <root>. ALEA requires a consumer config. See alea/config/README.md.` Stop.
   - Validate against [`contracts/schemas/project-config.schema.yaml`](../../contracts/schemas/project-config.schema.yaml). On validation failure, surface the offending field path.

### 2. Resolve ticket-source adapter

```
if --ticket-file was provided:
  adapter_name = "file"                                  # flag overrides config
else:
  adapter_name = config.ticket_source.adapter
```

Verify a folder exists at `adapters/ticket_source/<adapter_name>/`. If not → `Error: ticket-source adapter "<name>" not found. Expected folder at adapters/ticket_source/<name>/.` Stop.

### 3. Invoke adapter to fetch RawTicketPayload

Follow ALL instructions in `adapters/ticket_source/<adapter_name>/adapter.md`, passing:

- `ticket_id` (the parsed ID)
- `file_path` (only when adapter is `file`)
- `config` (the loaded `ProjectConfig`)

The adapter returns a `RawTicketPayload` in memory. The adapter is responsible for raising `TicketFetchException` on any transport, auth, or parsing failure; this command surfaces those errors verbatim and stops.

### 4. Apply PII sanitization (by code, not by hand)

PII redaction is a deterministic, tested policy — **do not re-implement the
regex by hand.** Run the shared redactor via the CLI on every text field in the
payload (`raw_title`, `raw_description`, `raw_acceptance[*]`,
`raw_attachments[*].description`):

```bash
aflow redact --file <field-as-temp-or-stdin> --format json
# → {"text": "<redacted>", "redactions": {"curp": 2, "email": 1, ...}}
```

Use the returned `text` as the sanitized field value. The redactor covers
(for reference — it is the source of truth, not this table): RFC, CURP, CLABE,
card, MX phone, email; matching is conservative (isolated patterns only).

Build `pii_redactions[]` from the `redactions` counts the CLI returns — one
entry per `{pattern, field, count}`. Because redaction is code-run, the
`pii_sanitized: true` flag (step 9) is *earned*, not asserted.

> If `aflow` is unavailable in the environment, STOP and report — do not fall
> back to manual regex (that reintroduces the unverifiable path this step
> exists to remove).

### 5. Validate minimum format

After sanitization, verify:

- `raw_title` is non-empty.
- `raw_description` is non-empty AND ≥ 20 characters.
- `raw_acceptance` is non-null AND non-empty list, OR core can infer ≥1 success criterion from the description.

On any failure:

```
Error: ticket <ticket_id> does not meet minimum format requirements.
Missing: <list of fields>
Cannot continue. Fix the ticket or use --ticket-file with a well-formed file.
```

Stop.

### 6. Classify ticket type

Set `type` based on keywords in `raw_title` + `raw_description` (case-insensitive, accent-stripped):

| Type | Keywords (any of) |
|---|---|
| `bugfix` | bug, error, falla, fix, crash, no funciona, incorrecto, roto, broken, no muestra, no carga, exception, null, npe, regression |
| `feature` | agregar, nuevo, nueva, implementar, añadir, crear, feature, build, add, implement |

If neither set matches → default to `bugfix`.

If both sets match → prefer the one with the earliest occurrence in the title. Title beats description.

`refactor` from the original pipeline collapses into `bugfix` for v1 — same downstream flow (single implement phase + gates).

### 7. Extract structured fields

#### 7a. `affected_layers`

Look at the layer names declared in `config.architecture.layers`. For each layer name, check whether `raw_description` (sanitized) mentions:

- The layer name itself (e.g. `domain`, `infrastructure`, `presentation`).
- Synonyms inferred from the description: "no guarda en BD" / "doesn't save to DB" → infrastructure (or whatever layer the consumer named its data layer). "pantalla no muestra" / "screen doesn't show" → presentation. "validación incorrecta" / "wrong validation" → domain.

The keyword→layer mapping is heuristic; the result is a list of layer names that exist in `config.architecture.layers`. Never include a layer name that's not in config.

#### 7b. `affected_files`

Scan the consumer's source paths (each `architecture.layers[*].paths` directory) for files probably touched by this ticket:

- Files mentioned by name in the description.
- Files matching descriptive keywords (e.g., the ticket mentions "sales screen" → look in any directory matching `*sales*` under the configured layer paths).
- Files in `affected_layers` that match the feature area.

Output as project-relative paths. Cap at 20 entries (more than that is rarely useful and inflates the JSON).

**Ground the file list in real dependencies (don't stop at keywords).** After seeding candidate files from keywords above, build/refresh the graph and expand the list with the verified reverse-dependency closure:

```bash
aflow graph --ensure-fresh -o .pipeline/graph.json --project-root .
# For each seed file or symbol, find what transitively depends on it:
aflow graph-query impact <seed-file-or-symbol> -i .pipeline/graph.json --format json
```

Add the returned `impacted` ids' files to `affected_files` (these are the consumers a change here would ripple to). Keep the 20-entry cap; if the closure exceeds it, keep the closest (most directly impacted) and note the overflow. This replaces guessing the blast radius with the graph's verified edges. If `aflow` is unavailable, STOP and report — do not hand-trace dependencies.

#### 7c. Type-specific fields

**For `type: bugfix`:**

- `bug_description`: one paragraph summarizing what is broken (separate from `description` which echoes the full ticket body).
- `root_cause_hypothesis`: best inference of WHY the bug occurs and which code path likely causes it. Include `"uncertain — could be either A or B"` when not confident. Never invent a cause; if no signal in the ticket → write `"undetermined; needs investigation in <best-guess area>"`.

**For `type: feature`:**

- `feature_description`: one paragraph summarizing what must be built.
- `new_components`: approximate breakdown matching the `NewComponents` shape in the schema:
  - `entities`, `repository_contracts`, `dtos`, `screens`, `providers` — each a list of PascalCase names inferred from the ticket. Empty lists are fine for fields not implied by the ticket.

#### 7d. Provenance

- `ticket_source.adapter`: the adapter name used (e.g., `asana`, `file`).
- `ticket_source.fetched_at`: ISO 8601 timestamp at moment of fetch.
- `ticket_source.raw_url`: copied from `RawTicketPayload.raw_url` (back-link to source system).

### 8. Build attachments[]

Copy `RawTicketPayload.raw_attachments` verbatim into `attachments[]`. Then scan `raw_description` for inline `https://` URLs not already in `raw_attachments` and append:

- Each found URL → `{kind: <inferred by URL pattern>, uri: <url>, description: <hint>}`.
  - Host `figma.com` → `kind: link, description: "figma"`.
  - Host `sketch.cloud` → `kind: link, description: "sketch"`.
  - Otherwise → `kind: link, description: <host name>`.

**This is the SINGLE channel for design references.** There is no top-level `figma_link` field. `/aflow-design-feature` will walk `attachments[]` to find a usable design source.

### 9. Write `analysis.json`

```bash
mkdir -p .pipeline/runs/<ticket_id>
```

Build the JSON conforming to [`contracts/schemas/analysis.schema.yaml`](../../contracts/schemas/analysis.schema.yaml). Required fields:

- `ticket_id`, `type`, `title`, `description`, `success_criteria`, `created_at` (ISO 8601 now).

Optional but populated when applicable:

- `acceptance_tests`, `attachments`, `priority`, `assignee`, `labels`, `ticket_source`, `pii_redactions`, `affected_layers`, `affected_files`.

Type-specific (required per `required_when` rules in schema):

- `bugfix` → `bug_description`, `root_cause_hypothesis`.
- `feature` → `feature_description`, `new_components`.

Always: `pii_sanitized: true` after this command runs (earned in step 4).

**Validate by code, not by eye.** After writing the JSON, run the schema
validator and treat a non-zero exit as a hard stop:

```bash
aflow validate-artifact \
  --schema analysis \
  --schemas-dir <alea>/contracts/schemas \
  --artifact .pipeline/runs/<ticket_id>/analysis.json
# exit 0 = valid · 1 = violations (fix and re-validate) · 2 = file/parse error
```

On exit 1, read the reported violations, fix the JSON, and re-validate — never
persist or hand off an `analysis.json` that fails validation. (`analysis` is a
`stable` schema, so a violation is authoritative, not a false positive.)

### 10. Display summary

```
══════════════════════════════════════════════
Ticket Analysis: <ticket_id> — <title>
══════════════════════════════════════════════
Type:        <feature | bugfix>
Adapter:     <adapter_name>
Layers:      <affected_layers, joined>
Files:       <count> files identified
Attachments: <count> (<count> design refs, <count> other)

[For bugfix]:
Bug:         <bug_description>

Hypothesis:
  <root_cause_hypothesis>

[For feature]:
Feature:     <feature_description>

Components:
  Entities:   <list>
  Screens:    <list>
  Providers:  <list>
  Design:     <list of attachments[*].description that map to design adapters>

Success criteria:
  ✓ <criterion 1>
  ✓ <criterion 2>

PII redactions: <count> across <field count> fields
══════════════════════════════════════════════

Saved: .pipeline/runs/<ticket_id>/analysis.json
You can edit this file before continuing if anything is incorrect.
```

## Failure modes

| Failure | Behavior |
|---|---|
| `.alea.yaml` missing or invalid | Stop with schema validation error. |
| Adapter not found in `adapters/ticket_source/` | Stop. |
| Adapter raises `TicketFetchException` | Surface the exception's `reason`. If `--ticket-file` was provided AND the configured adapter is not `file`, retry once using the `file` adapter as fallback. Otherwise stop. |
| Minimum format check fails | Stop with the list of missing fields. |
| Schema validation of assembled JSON fails | Stop. Never persist a malformed file. |

## What this command does NOT do

- Does not fetch design assets — that's `/aflow-design-feature` reading `attachments[]`.
- Does not scan repos beyond the configured layer paths.
- Does not write commit messages, branches, or any git operations.
- Does not enforce any analyzer/gate — that's `/aflow-run-gates`.
- Does not invoke the next phase. `/aflow-pipeline` is the orchestrator.
