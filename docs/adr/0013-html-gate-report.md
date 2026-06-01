# ADR-0013 — `aflow analyze --format html` (browsable gate report)

- **Status:** Accepted
- **Date:** 2026-05-29
- **Phase:** 12
- **Related:** [Design spec](../superpowers/specs/2026-05-29-html-report-design.md) · [UI brief](../design/alea-reports-ui-brief.md) · validated prototype (vendored at `lib/src/cli/report/assets/`)

## Context

`aflow analyze` prints a human report to stdout (or JSON via `--format json` / `-o`).
On a real consumer project the output is unusable: the first parity run on **freya**
produced **890 findings** (1 blocker, 13 critical, 847 major, 29 minor). The few
actionable findings drown in advisory noise and the terminal wall is unreadable.

We need a triage-first **visual** report — the equivalent of what `flutter test
--coverage` + `genhtml` gives for coverage, but for the analyzer gate. A UX proposal was
iterated against a senior-QA review to **Design v1.1**, captured in the
[UI brief](../design/alea-reports-ui-brief.md); a specialized design AI produced a
prototype (vendored at `lib/src/cli/report/assets/`) that QA verified meets every v1.1 criterion.

## Decision

Add `--format html` to `aflow analyze`. It writes a self-contained folder (default
`alea-reports/`, override with `-o <dir>`):

```
alea-reports/
├── index.html     ← template with the gate data injected inline (window.__ALEA_REPORT__)
├── styles.css     ← shipped verbatim
├── app.js         ← shipped verbatim
└── report.json    ← same payload, for tooling/CI
```

Key choices:

1. **Pure renderer in the CLI layer.** `lib/src/cli/report/html_report.dart` exposes a
   pure `renderHtmlReport(GateReport, {required String project}) → Map<filename,String>`.
   No `dart:io`; the command writes the files. Same shape as the init `config_generator`.
   Respects package boundaries (CLI is the unrestricted orchestration layer).
2. **Assets are committed files + generated embed.** The browser bundle lives as source
   files under `lib/src/cli/report/assets/` and is embedded into
   `html_report_assets.dart` by `tool/embed_report_assets.dart` (raw-string consts), so
   the AOT binary is self-contained. A drift-guard test fails if the generated file
   diverges from the assets. We do **not** hand-author 1.2k lines of CSS/JS as Dart
   strings.
3. **`project` is a render-time parameter, not a contract change.** The renderer takes
   `project` (from `config.project.packageName`, falling back to the `--project-root`
   basename) and merges it into the emitted payload. `GateReport` and its other
   consumers (driver, validate-artifact) are untouched.
4. **Reuse the existing serialization.** The payload is `GateReport.toJson()` (already
   snake_case: `rule_id`, `summary`, `suggested_fix` omitted when null) augmented with
   `project`. `--format` changes only the output, never what is analysed.

## Consequences

### Positive
- A real consumer can read gate results: the 14 blocking findings are surfaced; the 876
  advisory are explorable but collapsed/filtered out by default.
- Reuses the existing `GateReport`; no new dependencies; the renderer is pure and
  golden-testable.
- The prototype is ~95% of the deliverable (our output IS static HTML/CSS/JS), so this
  is "templatize + wire data", not a re-implementation.

### Negative
- The browser bundle (CSS/JS) cannot be unit-tested from Dart. Validation relies on a
  **required manual browser acceptance gate** against real data before merge.
- Embedding ~1.2k lines of assets adds a few KB to the binary (negligible) and a codegen
  step to the workflow (mitigated by the drift-guard test).

### Neutral
- Adds `lib/src/cli/report/` and a `tool/` script. No new boundary rule needed.
- `alea-reports/` should be gitignored by the consumer; we document it, we do not mutate
  their `.gitignore`.

## Explicitly out of scope (deferred)

- **Editor deep-links** (`vscode://`, `idea://`) — copy-path only for v1.
- **Annotated source rendering** per file (the heavy genhtml-style per-file pages).
- **Run history / trends / diff** between runs.

## Alternatives considered

### A. Single self-contained `index.html` (inline CSS+JS)
Rejected: the user wanted the coverage-style multi-file folder, and separate assets are
cacheable and cleaner. (We still inline the *data* to avoid `file://` fetch blocks.)

### B. Reuse genhtml / an external HTML reporter
Rejected: genhtml is coverage-specific (per-line source rendering, 464 files for freya)
and has no notion of actionable-vs-advisory triage — the opposite of what this needs.

### C. Hand-author the CSS/JS as Dart string constants
Rejected: ~1.2k lines hand-pasted into Dart strings drift and are error-prone. Committed
asset files + a codegen embedder + drift-guard test is the maintainable form.

## References

- [Design spec](../superpowers/specs/2026-05-29-html-report-design.md)
- [UI brief](../design/alea-reports-ui-brief.md)
- `lib/src/cli/report/assets/` — the vendored browser bundle (the validated prototype; the original Claude Design export was removed after vendoring)
- [ADR-0012](0012-init-template-config.md) — the `config_generator` whose pure-function
  shape this reuses.
