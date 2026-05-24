# Widget Audit — Shared Sub-Phase

Scores the consumer project's widget catalog against each NDS element and emits a per-element decision (USE_AS_IS / ADAPT / CREATE_NEW). Invoked by every design-source adapter as the second-to-last sub-phase before emitting the final `DesignExtractionResult`.

## Inputs

- `nds` — the NDS document the calling adapter has just extracted.
- `config` — the loaded `ProjectConfig`.
- `run_dir` — the directory under `.pipeline/runs/<ticket_id>/` where the calling adapter writes its artifacts (e.g. `figma/`, `image/`, `markup/`).

## Output

`<run_dir>/widget_map.yaml` — one entry per NDS element with `decision`, `widget` (when reusing), `file` (when reusing), `changes` (when adapting), `placement` (when creating).

## Steps

### 1. Build the widget index (if absent or stale)

Check whether `<run_dir>/widgets_index.csv` exists AND is newer than every Dart file under the consumer's presentation paths (`config.architecture.layers.presentation.paths` — or whatever layer name the consumer assigned to UI).

If stale or absent, regenerate:

```
For every .dart file under presentation layer paths:
  Parse the file's AST (or grep for `class X extends StatelessWidget|StatefulWidget|ConsumerWidget|ConsumerStatefulWidget|HookConsumerWidget`).
  For each match, append a row to widgets_index.csv with columns:
    name, type, key_props, file_path, last_modified, interactive
```

Column definitions:

| Column | Value |
|---|---|
| `name` | the widget class name (PascalCase) |
| `type` | one of: `button`, `card`, `list`, `field`, `image`, `text`, `layout`, `screen`, `other` (heuristic by name suffix + content) |
| `key_props` | comma-separated parameter names from the widget's primary constructor |
| `file_path` | project-relative path to the .dart file |
| `last_modified` | mtime as ISO 8601 |
| `interactive` | `true` if the widget wraps `InkWell`, `GestureDetector`, or accepts an `onTap`/`onPressed` parameter; else `false` |

> Step 9 of the migration replaces this prompt-driven scan with `_common/scripts/generate_widget_index.dart`. Until then, the AI-driven scan is the official approach. The output schema is the contract.

### 2. Score candidates per NDS element

For every element in `nds.elements`:

1. **Filter** — keep only widgets from `widgets_index.csv` whose `type` is compatible with the element's `type` AND whose `name` does NOT end in `Page`, `Screen`, `View`, or `Route`.

2. **Short-circuit on `widget_hint`** — if the NDS element has `widget_hint` set:
   - Look up the hinted name in the index.
   - If found, score only the prop coverage dimension per [`widget-scoring-matrix.md`](widget-scoring-matrix.md). Apply thresholds and emit.
   - If not found, fall through to step 3.

3. **Score across all 4 dimensions** per [`widget-scoring-matrix.md`](widget-scoring-matrix.md): Structure 40% / Visual 30% / Behavior 20% / Prop coverage 10%. Produce a numeric score 0–100 per candidate.

4. **Pick the top candidate** by score. Apply decision thresholds:

   | Score | Decision |
   |---|---|
   | 85–100 | `USE_AS_IS` |
   | 60–84 | `ADAPT` |
   | 50–59 | `ADAPT` if reusing ≥70% of candidate code, else `CREATE_NEW` |
   | 0–49 | `CREATE_NEW` |

   If no candidate passes filtering at step 1 → `CREATE_NEW` immediately (no scoring).

### 3. Build the widget_map entry

For each element, emit one entry to `<run_dir>/widget_map.yaml`:

```yaml
<element_id>:
  decision: USE_AS_IS | ADAPT | CREATE_NEW
  widget: <PascalCaseName>           # required for USE_AS_IS, ADAPT
  file: <project-relative path>      # required for USE_AS_IS, ADAPT
  score: <numeric>                   # informational; null if widget_hint short-circuit
  changes:                           # required for ADAPT
    - "add optional param `<name>` (default <value>)"
    - "extract <thing> to allow override"
  placement: <project-relative dir>  # required for CREATE_NEW
  rationale: "<one-line explanation>"
```

### 4. Save and return

Persist `<run_dir>/widget_map.yaml`. The calling adapter packages this path into the `DesignExtractionResult.widgetMap` field.

## What this audit does NOT do

- Does NOT write Dart code. Decisions are abstract; the code-gen adapter materializes them.
- Does NOT modify the consumer's existing widgets. Even for `ADAPT` decisions, only the recommendation is recorded; code-gen makes the edit.
- Does NOT pick CREATE_NEW placement paths from outside the presentation layer. New widgets always live under the consumer's presentation paths.
- Does NOT score widgets across the entire consumer codebase indiscriminately — only those under the presentation paths and not named like a screen.

## Failure modes

| Condition | Behavior |
|---|---|
| `widgets_index.csv` cannot be built (no presentation paths in config, or paths are empty) | Skip widget audit. Emit `widget_map.yaml` with `decision: CREATE_NEW` for every element. The calling adapter continues. |
| NDS has no elements | Emit empty `widget_map.yaml`. Calling adapter continues. |
| A `widget_hint` references a widget that doesn't exist in the index | Fall through to normal scoring; do NOT raise. The hint is advisory. |
