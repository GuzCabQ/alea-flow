# `adapters/design_source/`

Adapters that turn a design artifact into a Normalized Design Spec ([NDS](../../contracts/schemas/nds.schema.yaml)).

## Contract

Every folder here implements `DesignSourceAdapter` from [`../../contracts/design_source_adapter.dart`](../../contracts/design_source_adapter.dart) (TBD).

Inputs:
- Source descriptor (Figma URL / image path / HTML file / pasted JSX).
- `ProjectConfig` (for theme token paths, widget catalog paths, brand color references).

Output:
- A valid NDS YAML file at `.pipeline/runs/<id>/figma/nds.yaml` (or `image/`, `markup/` depending on adapter).
- A widget audit at `.pipeline/runs/<id>/<source>/widget_map.yaml`.
- A color/theme map at `.pipeline/runs/<id>/<source>/color_map.yaml`.

The adapter does NOT write Dart code, decide on state management, or run analyzers — those are downstream.

## Folders

| Folder | Source type | Status |
|---|---|---|
| `figma/` | Figma MCP URL / node | Primary adapter (port of flutter-ui Path A) |
| `image/` | PNG/JPG/WebP screenshot | Stub for v1; implemented on first consumer demand (YAGNI) |
| `markup/` | HTML or JSX file or pasted content | Stub for v1 (port of flutter-ui Path C); implemented on first consumer demand |
| `_common/` | Shared logic across all design sources (widget audit, theme mapping, color distance, widget index) | Always present |

## Adding a new adapter (e.g. Penpot, Storybook, Sketch)

1. Create `adapters/design_source/<name>/`.
2. Implement `DesignSourceAdapter` — at minimum, the `extract(source, config) → NDS` method.
3. Add a `README.md` explaining what source types are supported and any external dependencies (MCP server, CLI tool, etc.).
4. Add a `<name>_test.dart` with at least one fixture-based integration test.
5. Declare the adapter as selectable in `design_source.adapters.<name>` in the project config schema.

No changes to `core/`, `contracts/`, or other adapters.
