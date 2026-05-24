# Widget Scoring Matrix

Reference data for [`widget-audit.md`](widget-audit.md). Scores each candidate widget from the consumer's catalog against one NDS element and decides USE_AS_IS / ADAPT / CREATE_NEW.

## Dimensions (weighted)

| Dimension | Weight | Description |
|---|---|---|
| **Structure** | 40% | Does the candidate's layout (column/row/stack/none, children count, fixed-vs-flexible sizing) match the NDS element? |
| **Visual** | 30% | Does the candidate's default background type + border-radius category match? |
| **Behavior** | 20% | Does the candidate handle `interactive`, `scroll`, animations, and stateful affordances the NDS implies? |
| **Prop coverage** | 10% | Can the candidate's existing constructor parameters cover the NDS element without forcing the consumer to add new required parameters? |

## Decision thresholds

| Score | Decision | Action |
|---|---|---|
| 85–100 | `USE_AS_IS` | Import and instantiate; no edits to the candidate. |
| 60–84 | `ADAPT` | Add optional parameters with defaults; preserve every existing call site. |
| 50–59 | Threshold case | `ADAPT` if reusing ≥ 70% of candidate code; else `CREATE_NEW`. |
| 0–49 | `CREATE_NEW` | Write a new widget; place per the rules below. |

## Per-dimension scoring rules

### Structure (40%)

| Match condition | Points (out of 40) |
|---|---|
| Same layout axis (both column / both row / both stack) | 15 |
| Same number-of-children category (atomic / pair / list / nested) | 10 |
| Same sizing mode on main axis (fill / hug / fixed) | 8 |
| Same sizing mode on cross axis | 7 |

### Visual (30%)

| Match condition | Points (out of 30) |
|---|---|
| Same background type (solid / gradient / none) | 12 |
| Same border-radius category (none / small ≤ 8 / medium 12–16 / large ≥ 24) | 10 |
| Same density category (compact / standard / spacious — derived from default padding) | 8 |

### Behavior (20%)

| Match condition | Points (out of 20) |
|---|---|
| Both interactive (`onTap` / `InkWell` / `GestureDetector` present) OR both non-interactive | 10 |
| Both scrollable OR both fixed-height | 5 |
| State-variant icons supported (for lists) | 5 |

### Prop coverage (10%)

| Match condition | Points (out of 10) |
|---|---|
| All NDS data points fit existing parameters without making them required | 10 |
| Needs 1 new optional parameter with a sensible default | 7 |
| Needs 2+ new optional parameters | 4 |
| Needs a new required parameter | 0 |

## `widget_hint` short-circuit

If the NDS element has `widget_hint` set (non-null):

1. Look up the hinted widget name directly in the consumer's widget index.
2. If found → score ONLY the prop coverage dimension. The hint already encodes structural + visual + behavioral confidence.
3. If prop coverage = 10 → `USE_AS_IS`. Else → `ADAPT`.
4. Do NOT score other candidates when a hint resolves.
5. If the hinted widget is NOT in the index → fall through to normal candidate scoring across all dimensions.

## CREATE_NEW placement

When a new widget is needed:

| NDS scope | Placement (relative to consumer project root) |
|---|---|
| Generic / reusable across features | Read from `config.architecture.layers.presentation.paths` and append `/core/widgets/` (or the consumer's documented shared-widgets path). |
| Feature-specific | Same presentation path, append `/<feature_slug>/widgets/`. |

The widget audit emits a placement suggestion; the code-gen adapter writes the file there.

## Candidate filtering before scoring

A widget from the consumer's catalog is a candidate only when ALL of:

1. The widget's type is compatible with the NDS element type (button widget ↔ NDS button, layout widget ↔ NDS container, etc.).
2. The widget is NOT a screen-level widget. By convention, names ending in `Page`, `Screen`, `View`, `Route` are screens and never reused as in-tree widgets.
3. The widget's file lives under the consumer's `presentation` layer paths (per config).

If no candidate passes filtering → decision is `CREATE_NEW`. No scoring needed.

## Layout decision tree (used by code-gen, referenced here for completeness)

| NDS pattern | Flutter widget |
|---|---|
| Repeating same-type children, count is API-driven or unknown | `ListView.builder` |
| Mixed content taller than typical screen | `SingleChildScrollView` + `Column` |
| Overlapping elements | `Stack` + `Positioned` |
| Vertical, fixed children, ≤ 20 items | `Column` |
| Horizontal, fixed children | `Row` |
| Atomic element with no children | the element's own widget type |
