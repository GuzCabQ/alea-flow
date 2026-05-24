# Layout Decision Tree

Used by every code-gen adapter's `layers/presentation.md` to pick the Flutter root widget for each NDS container.

## The tree

```
For an NDS element with type=container or type=list:

  Has scroll=true ?
    └─ Yes
       └─ Has type=list AND content=dynamic AND children=[ONE repeating shape] ?
          ├─ Yes  → ListView.builder
          └─ No   → SingleChildScrollView wrapping the layout

  Has layout=stack ?
    └─ Yes  → Stack + Positioned per overlapping child

  Has layout=column ?
    └─ Yes
       └─ Children count is API-driven OR > 20 ?
          ├─ Yes  → ListView.builder (over Column for performance)
          └─ No   → Column

  Has layout=row ?
    └─ Yes
       └─ Children might overflow horizontally on small screens ?
          ├─ Yes  → SingleChildScrollView(scrollDirection: Axis.horizontal) wrapping Row
          └─ No   → Row

  Has layout=none AND ≤1 child ?
    └─ Yes  → the child's widget directly (no container wrapper)

  Default → Column (graceful fallback for malformed NDS)
```

## Quick lookup table

| NDS pattern | Flutter widget |
|---|---|
| `layout: column, scroll: true, mixed content taller than screen` | `SingleChildScrollView` + `Column` |
| `layout: column, content: dynamic, type: list, children unknown count` | `ListView.builder` |
| `layout: column, children ≤ 20, scroll: false` | `Column` |
| `layout: column, children > 20` | `ListView.builder` (even if NDS says scroll false — performance over fidelity) |
| `layout: row, overflow possible` | `SingleChildScrollView(horizontal)` + `Row` |
| `layout: row, fixed children` | `Row` |
| `layout: stack` | `Stack` + `Positioned` per overlapping child |
| `layout: none, 1 child` | the child's widget (no wrapper) |
| `layout: none, 0 children` | `SizedBox.shrink()` |

## Constraint rules (always apply, regardless of layout choice)

The following constraints are enforced AT GENERATION TIME and ALSO verified by the `visual_fidelity` analyzer. If you generate code that violates them, the gate fails.

| Rule | Why |
|---|---|
| Any `Text` with `content: dynamic` inside a `Row` → wrap in `Expanded` | Prevents `RenderFlex overflowed` errors at runtime |
| Any scrollable (`ListView`, `GridView`) inside a `Column` → wrap in `Expanded` OR give an explicit `SizedBox(height: N)` | Prevents `Vertical viewport was given unbounded height` |
| Any `TextField` inside a `Row` → wrap in `Expanded` | Same overflow reason |
| Never use `shrinkWrap: true` on a dynamic `ListView` whose item count is unknown | Performance — defeats lazy rendering |
| Never use `ListView` (without `.builder`) for ≤20 static items — use `Column` | Avoids unnecessary lazy machinery for short fixed lists |

### Expanded vs Flexible

- `Expanded` = forces child to fill ALL remaining space. Use when child must fill.
- `Flexible` = allows child to be smaller than allocated space. Use when child may shrink.

When in doubt → `Expanded`.

## Responsive sizing

- Never hardcode screen width / height numerically. Use `double.infinity`, `MediaQuery.sizeOf(context).width`, or `LayoutBuilder`.
- For full-width forms and text blocks on tablet+ form factors, wrap in `ConstrainedBox(constraints: BoxConstraints(maxWidth: 600))`.
- `width: "fill"` in NDS → `double.infinity` (inside a Column) or `Expanded` (inside a Row).
- `width: "hug"` in NDS → omit width (children's intrinsic width).
- `width: "fixed:N"` in NDS → `SizedBox(width: N, ...)`.

## Default spacing (when NDS does not specify)

| Context | Default |
|---|---|
| Horizontal padding on a page-level container | `EdgeInsets.symmetric(horizontal: 16)` |
| Vertical gap between sibling cards/sections | `SizedBox(height: 16)` |
| Inline gap between an icon and its label | `SizedBox(width: 8)` |
| Padding inside a card | `EdgeInsets.all(16)` |
| Padding inside a button | `EdgeInsets.symmetric(horizontal: 24, vertical: 12)` |

These defaults are overridable per consumer convention but never hardcoded in the adapter beyond this table.
