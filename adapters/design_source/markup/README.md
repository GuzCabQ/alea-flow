# `markup/` — Design Source Adapter (Stub)

Stub for an adapter that extracts NDS from HTML or JSX files / pasted content. Not implemented in v1.

## When this would be selected

`/design-feature` walks `analysis.json::attachments[]` and asks each enabled adapter `supports(ref, config)`. This adapter would match attachments whose URI ends in `.html`, `.htm`, `.jsx`, or `.tsx`, OR attachments whose `description: "markup"`.

Currently `.alea.yaml::design_source.adapters.markup.enabled` defaults to `false`. Implement this adapter when the first consumer requests it (likely a team migrating a React web app to Flutter, or a team that prototypes in HTML before designing in Figma).

## Implementation outline (when ready)

Following the same three-phase pattern:

1. **Source-specific extraction (Path C):**
   - Strip `<script>` and `<style>` nodes that don't affect layout.
   - Walk DOM / JSX tree:
     - Block containers (`<div>`, `<section>`, `<article>`) → NDS `container`.
     - Text (`<p>`, `<span>`, `<h1>`–`<h6>`) → NDS `text`.
     - `<button>`, `<input type="button">` → NDS `button`.
     - `<img>` → NDS `image`.
     - `<ul>` / `<ol>` / repeating sibling `<div>`s with same shape → NDS `list` (collapsed).
     - `<svg>` or icon component → NDS `icon`.
   - Extract CSS properties (inline `style=` or class lookups when CSS is provided):
     - `display: flex` + `flex-direction` → `layout`.
     - `background-color` / `background: linear-gradient(...)` → `background`.
     - `border-radius` → `border.radius`.
     - `onClick` / `onPress` → `interactive: true`.
     - `overflow: scroll` → `scroll: true`.
   - For JSX: `useState` / `useEffect` → note state management requirement in `actions`.
2. **Delegate widget audit:** [`../_common/widget-audit.md`](../_common/widget-audit.md).
3. **Delegate theme map:** [`../_common/theme-map.md`](../_common/theme-map.md).

## Reference

`adapter.md` (when written) ports `flutter-ui/SKILL.md` Path C plus the HTML/JSX mapping table at `flutter-ui/references/html-to-flutter-mapping.md`.

## Why this is not in v1

No consumer needs it. Building it preemptively violates YAGNI. The stub lives here so:

1. The adapter family demonstrates that the architecture is open to multiple source types — not Figma-specific.
2. Adding it later requires no contract change.
3. `analysis.schema.yaml::AttachmentRef.description` already lists `markup` as a valid routing hint.
