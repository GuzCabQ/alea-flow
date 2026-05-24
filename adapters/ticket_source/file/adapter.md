# File Adapter — Fetch Prompt

Invoked by `/analyze-ticket` after the file adapter is selected. The prompt reads a local file, parses it per the format conventions in [`README.md`](README.md), and returns a `RawTicketPayload`.

## Inputs

- `file_path` — relative or absolute path to a `.md`, `.json`, or `.yaml` file.
- `config` — `ProjectConfig` (rarely consulted; reserved for future per-project conventions).

## Steps

### 1. Resolve and validate the path

Resolve `file_path` to an absolute path. Verify:

- The file exists. If not → `TicketFetchException(adapter: "file", reason: "File not found: <path>")`.
- The file is readable.
- The file size is < 1 MB (sanity bound — tickets are not large blobs).

### 2. Pick a parser by extension

| Extension (case-insensitive) | Parser branch |
|---|---|
| `.md`, `.markdown` | Markdown — go to step 3a. |
| `.json` | JSON — go to step 3b. |
| `.yaml`, `.yml` | YAML — go to step 3b (same shape validation as JSON). |
| Anything else | `TicketFetchException(reason: "Unsupported extension: <ext>")` |

### 3a. Markdown branch

1. Find the first `# ` (H1) heading. Its trimmed text is `raw_title`. If no H1 → fail with `Missing H1 heading`.
2. Walk H2 sections (`## `). For each one, normalize the heading name (lowercase, strip accents) and match against:

   | Normalized name | Field |
   |---|---|
   | `descripcion`, `description` | `raw_description` (body until next H2 or EOF) |
   | `criterios de aceptacion`, `acceptance criteria`, `success criteria` | `raw_acceptance` (parse as bullet list — see step 4) |
   | `adjuntos`, `attachments` | `raw_attachments` (parse as bullet list of links — see step 5) |
   | `prioridad`, `priority` | `raw_priority` (first non-empty line; lowercased; map to enum if recognized, else null) |
   | `etiquetas`, `labels`, `tags` | `raw_labels` (parse as bullet list of plain strings) |

3. After section walk, verify required fields populated:
   - `raw_title` non-empty
   - `raw_description` non-empty and ≥ 20 chars
   - `raw_acceptance` non-null AND non-empty list

   On any missing → `TicketFetchException(reason: "Missing required section: <name>")`.

### 3b. JSON / YAML branch

1. Parse the file with the appropriate library (yaml: parse YAML 1.2; json: parse JSON).
2. Validate the result is a top-level object (not array or scalar).
3. Validate at minimum: `raw_title`, `raw_description`, `raw_acceptance` are present and of correct type.
4. Use the parsed map as the payload base. Continue to step 4 only if `raw_attachments` is unset (since JSON/YAML callers may have already populated it).

### 4. Parse bullet list (for raw_acceptance, raw_labels)

Recognized bullet prefixes: `-`, `*`, `+`, `1.`, `1)`, `(1)`. For each line:

1. Strip the prefix and any leading whitespace.
2. Strip trailing whitespace.
3. Skip empty lines.

Result is a `list<string>`.

### 5. Parse attachments list

For each bullet in the `Attachments` section:

1. Try to match Markdown link: `\[(?<label>[^\]]+)\]\((?<url>[^)]+)\)`.
   - If matches → `{kind: <inferred>, uri: <url>, description: <label>}`.
2. Else try to match a bare URL: `https?://\S+`.
   - If matches → `{kind: <inferred>, uri: <url>, description: null}`.
3. Else skip the line (with a warning logged to the run directory; do not fail).

`kind` inference table:

| URL contains / extension | `kind` | `description` enrichment |
|---|---|---|
| Host `figma.com` | `link` | If `description` was null, set to `"figma"`; else keep |
| `.png` / `.jpg` / `.jpeg` / `.webp` / `.gif` | `image` | Keep label or set to filename |
| `.pdf` / `.doc` / `.docx` / `.xlsx` / `.csv` | `document` | Keep label or set to filename |
| Anything else | `link` | Keep label or set to host |

### 6. Scan description for inline figma links

Even after step 5, run `r"https://www\.figma\.com/(file|design|proto)/[A-Za-z0-9]+[^\s)]*"` against `raw_description`. For each URL not already present in `raw_attachments`, append:

```yaml
{ kind: link, uri: <url>, description: "figma" }
```

### 7. Build source_metadata

```yaml
source_metadata:
  file_path: <absolute path resolved in step 1>
  file_size_bytes: <integer>
  parsed_at: <ISO8601 now>
  parser: markdown | json | yaml
  adapter_version: "1.0.0"
```

### 8. Return the payload

Return the assembled `RawTicketPayload` map to `/analyze-ticket`. No disk writes, no redaction, no classification.

## Determinism

This adapter must be fully deterministic: same file → same payload bytewise. Tests rely on this for golden-file comparisons.

## What this prompt MUST NOT do

- ❌ Resolve `./path` references in attachments against the filesystem.
- ❌ Follow links or fetch URL contents.
- ❌ Redact PII.
- ❌ Decide ticket type or extract affected layers.
- ❌ Validate that the consumer project has files matching the ticket — that's core's concern.
