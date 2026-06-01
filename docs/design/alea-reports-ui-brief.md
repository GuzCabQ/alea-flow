# Design brief — `alea-reports` static HTML report

> **Purpose of this file.** A self-contained prompt/spec to hand to a
> specialized UI-generation AI (v0, Lovable, Figma AI, etc.) so it produces the
> `alea-reports/` HTML report meeting the criteria converged in design review
> (UX proposal + senior-QA iteration → "Design v1.1"). Attach the tool's real
> output `report.json` (e.g. from `aflow analyze --gate full --format json -o report.json`)
> as the example dataset; its schema is described below verbatim.

---

## What to build

A self-contained, static HTML report that visualizes the output of a Dart/Flutter
static-analysis tool ("alea"). After the tool runs its analyzer suite ("a gate")
on a project, it emits findings. The report's ONE job: **triage** — let a developer
instantly separate the FEW findings that BLOCK the gate from the MANY that are
ADVISORY. Real input scale: ~14 blocking vs ~876 advisory across ~890 findings.

## Tech constraints (hard)

- Pure static output, **no build step, no network, no external CDN/fonts**. Must open
  by double-clicking `index.html` (`file://`). System font stack only.
- Emit separate files: `index.html`, `styles.css`, `app.js` (+ the example `report.json`).
- Data is provided to the page **inline** as `window.__ALEA_REPORT__ = { ... }` inside a
  `<script>` in `index.html`. Do **NOT** `fetch()` `report.json` — `file://` fetch is
  blocked by browsers. `report.json` is emitted separately only for tooling.
- Vanilla HTML/CSS/JS — no framework, no dependencies. Modern but broadly compatible.
- Light/dark via `prefers-color-scheme`.
- Accessible to WCAG 2.1 AA. Responsive down to 360px.

## Data model — `window.__ALEA_REPORT__` (REAL schema)

```json
{
  "gate": "full",
  "timestamp": "2026-05-29T13:42:00",
  "passed": false,
  "summary": { "total_issues": 890, "blockers": 1, "criticals": 13, "majors": 847, "minors": 29 },
  "results": [
    {
      "analyzer": "security",
      "passed": false,
      "issues": [
        {
          "file": "lib/src/domain/repositories/profile_photo_upload_repository.dart",
          "line": 1,
          "rule": "dart_io_in_domain",
          "rule_id": "security/dart_io_in_domain",
          "message": "Domain must not import dart:io — move platform code to infrastructure.",
          "suggested_fix": "Introduce a domain abstraction; keep dart:io in infrastructure.",
          "severity": "blocker"
        }
      ]
    },
    {
      "analyzer": "code_complexity",
      "passed": false,
      "issues": [
        {
          "file": "lib/src/presentation/profile/screens/update_password_screen.dart",
          "line": 53,
          "rule": "length_critical",
          "rule_id": "code_complexity/length_critical",
          "message": "build is 193 lines long (threshold: 100)",
          "suggested_fix": "Extract sub-widgets into named classes.",
          "severity": "critical"
        }
      ]
    },
    {
      "analyzer": "visual_fidelity",
      "passed": true,
      "issues": [
        {
          "file": "lib/src/presentation/home/widgets/simple_home_card.dart",
          "line": 38,
          "rule": "missing_image_fit",
          "rule_id": "visual_fidelity/missing_image_fit",
          "message": "Image.asset(...) called without a fit: argument.",
          "severity": "minor"
        }
      ]
    }
  ]
}
```

**Schema notes (match exactly):**
- Top level: `gate` (string), `timestamp` (ISO 8601 string), `passed` (bool),
  `summary` (precomputed counts — use it for the header tallies), `results` (array).
- There is **no** top-level `project` field. The header may show `gate` + `timestamp`;
  do not invent a project name.
- Each result: `analyzer` (string), `passed` (bool), `issues` (array).
- Each issue: `file` (project-relative path), `line` (int), `rule` (string),
  `rule_id` (string, `"<analyzer>/<rule>"`), `message` (string), `severity` (enum),
  and `suggested_fix` (string) which is **OPTIONAL — present only when non-null**.
- Generate a realistic dataset matching the scale: 1 blocker, 13 critical, ~847 major
  (mostly `testing/missing_test`, `code_complexity` build-method length, and many
  `visual_fidelity/missing_image_fit`), ~29 minor — spread across ~600 files in
  `domain/`, `infrastructure/`, `presentation/` subfolders.

## Severity model (drives EVERYTHING)

- `blocker`, `critical` → **BLOCKING** (these fail the gate; the actionable few).
- `major`, `minor` → **ADVISORY** (do NOT fail the gate; the noisy many).
- Render each severity with **color + icon + text label** (never color alone):
  blocker 🟥, critical 🟧, major 🟨, minor ⬜ (use distinct, accessible hues).

## Layout

1. **Sticky header / dashboard**
   - Verdict banner: PASS (green) / FAIL (red), with a **nuanced** subtitle derived
     from the data, e.g. "Fails on 1 architecture + 13 complexity findings" (avoid
     pure alarm when most findings are debt, not bugs).
   - Severity tally chips with counts + total (from `summary`).
   - Grouping segmented control: **Severity (default) | File | Analyzer**.
   - Severity filter toggles (checkbox chips): blocker+critical **ON** by default,
     major+minor **OFF**.
   - Search box (filters by `file`, `rule_id`, or `message`).
   - A live counter: "showing X of Y".
   - A short legend: "blocker/critical fail the gate; major/minor are advisory".
2. **Body — grouped findings.**
3. **Finding row (shared, IDENTICAL across all 3 grouping axes):**
   `[severity chip+icon]  file/path:line  [⧉ copy]  ·  rule_id  ·  message  [fix ▸]`
   - `⧉` copies `file:line` to the clipboard (toast confirmation).
   - `fix ▸` expands to show `suggested_fix`; **hide the control entirely when the
     field is absent/null**.
   - Path in monospace; truncate in the MIDDLE on overflow with a full-path `title`.

## Grouping axes

- **Severity (default):** a "BLOCKING" section (expanded) above an "ADVISORY" section
  (collapsed). If `blockers + criticals == 0`: show a green "Nothing blocks this gate"
  state and **auto-expand** advisory (never a blank screen).
- **File:** a **collapsible folder tree** (`domain/` → `repositories/` → file → findings):
  - **Auto-expand** every branch containing a blocking finding on load; collapse
    advisory-only branches. (If blocking == 0: collapsed + green empty-state guidance.)
  - **Path compression:** collapse single-child folder chains into one node
    (VS Code style: `orden_de_pago/screens` as one row). Compute compression **after**
    filtering.
  - **Prune:** a folder appears only if it has ≥1 finding passing the current filter;
    recompute its color (worst severity) and chip mix from the filtered set.
  - Per-folder **chips** show only severities with count > 0 (e.g. 🟧2 🟨5); on <900px
    collapse to "worst severity + total".
  - Sort siblings within each level: worst-severity (default) → count → alphabetical.
- **Analyzer:** flat groups, one per analyzer, showing pass/fail + counts.

## Interactions

- Filters + search combine with **AND**; the header counter reflects the result.
- Switching grouping axis **persists** active filters and search.
- Search is **debounced (~150ms)**.
- **Pagination:** within any expanded group/folder, render the first **50** findings +
  a "Show 50 more" control at the foot of that group (preserving filter/search).
  Folders themselves are not paginated.
- Defer rendering a group's contents until it is expanded (performance with ~890+ rows).
- Default order inside flat groups (Severity/Analyzer): by `file` then `line` ascending.

## States

- **Fail** (blocking > 0): blocking expanded, advisory collapsed.
- **Pass** (blocking == 0): green verdict + advisory auto-shown.
- **Empty File tree** (e.g. blocking == 0 with advisory filtered off): show the same
  green guidance ("Nothing blocks this gate — enable major/minor to see advisory"),
  never a blank panel.

## Accessibility (required, not optional)

- The File tree uses `role="tree" / "treeitem" / "group"` with `aria-expanded`, and full
  **keyboard navigation** (Up/Down move focus, Right/Left expand/collapse, Enter activates).
- Severity conveyed by icon + text, not color alone. Contrast ≥ 4.5:1.
- All controls focusable and keyboard-operable; visible focus ring.

## Visual direction

Modern, calm, "quality dashboard" aesthetic — think a clean CI/lint results panel
(e.g. Vitest UI / a modern ESLint HTML report), NOT the dated lcov/genhtml table look.
Generous whitespace, clear typographic hierarchy, subtle borders, severity color as
accents (not full-row floods). Density appropriate for scanning hundreds of rows.

## Acceptance criteria (the output MUST)

1. Open with no server/network; data read from `window.__ALEA_REPORT__` (schema above).
2. Default view shows ONLY blocking findings (blocker+critical); advisory collapsed/off.
3. If blocking == 0 → green verdict + advisory auto-shown (never a blank screen).
4. The three grouping axes share one identical finding-row component.
5. File tree auto-expands to blocking, compresses single-child chains (post-filter),
   prunes empty branches, and is keyboard + screen-reader accessible.
6. Filters/search are AND, persist across axis switches, with a "showing X of Y" count.
7. Copy-path works with a toast; `suggested_fix` expands; absent fix hides the control.
8. Groups paginate at 50 with "show 50 more"; rendering is deferred until expanded.
9. Light/dark; responsive 360px+; severity = color + icon + text.

Deliver `index.html`, `styles.css`, `app.js`, and a representative `report.json`.
