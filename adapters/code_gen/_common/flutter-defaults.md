# Flutter Defaults

Rules every code-gen adapter applies UNCONDITIONALLY when NDS leaves a field unspecified or when generated code touches a Flutter widget that has well-known footguns. These rules are enforced by `_common/` because they don't depend on state-management style.

The [`visual_fidelity`](../../../lib/src/analyzers/) analyzer (step 8) re-checks generated code against these rules; violations are `blocker`.

## Image fit

Every `Image.*`, `SvgPicture.*`, and `Lottie.*` call MUST pass a `fit:` parameter. Choosing the value:

| NDS signal | `fit` |
|---|---|
| `box_fit` set in NDS | use it exactly |
| `box_fit` absent, element looks like icon / illustration / logo | `BoxFit.contain` |
| `box_fit` absent, element looks like full-bleed background | `BoxFit.cover` |
| `box_fit` absent, role unclear | `BoxFit.contain` |

## Asset existence check

Before emitting `Image.asset(path)`, `SvgPicture.asset(path)`, or `Lottie.asset(path)`:

1. Resolve `path` against the consumer project root.
2. Check if the file exists.
3. If yes → emit the call.
4. If no → emit `// TODO: asset missing — expected at <path>` AND a placeholder `SizedBox(width: W, height: H)`. Never emit broken `.asset()` calls that crash at runtime.

## Text overflow

For every `Text` widget where the data is `content: dynamic` (variable, comes from a Notifier/Bloc/provider):

- Always add `maxLines: 2, overflow: TextOverflow.ellipsis` unless the design EXPLICITLY shows a multi-line expanding text area.

For `content: static` with a known short string: `maxLines` is not required.

## Asset type → widget mapping

| `asset_type` | Widget |
|---|---|
| `image` | `Image.asset(path, fit: BoxFit.X)` |
| `svg` | `SvgPicture.asset(path, fit: BoxFit.X)` — requires `flutter_svg` dependency |
| `gif` | `Image.asset(path, gaplessPlayback: true, fit: BoxFit.X)` |
| `lottie` | `Lottie.asset(path, fit: BoxFit.X)` — requires `lottie` dependency |

When emitting `SvgPicture` or `Lottie`, also emit a comment indicating the package dependency the consumer's pubspec needs (the adapter should NOT modify the consumer's pubspec; it documents).

## Emoji prohibition

When the NDS document was produced from a Figma source (`document.source.adapter == "figma"`):

- NEVER use Unicode emoji (🎉, 📋, ⚙️, 📄, 📅, 🔍, etc.) as a substitute for an image asset or icon.
- If NDS expects an icon at an element but `asset_path` is unknown → emit `// TODO: asset unknown — replace with the correct Image.asset(...)` instead of an emoji.

Emoji are acceptable ONLY when they appear in `static_value` strings AND the Figma design explicitly contains emoji as text (not as icon nodes).

For non-figma sources (image, markup, sketch, etc.) the same rule applies by default — emoji as icon is always a bug.

## Button content

- If NDS `type: button` has `label: null AND icon: null` → STOP code generation. Escalate to the consumer via the Question Gate in `/design-feature`.
- Never emit `Text('')` (empty label) as a stand-in for a missing label.

## `const` constructors

- Every leaf widget with no dynamic data MUST use a `const` constructor.
- Containers with at least one `const` child should still be `const`-eligible when their own configuration is constant.
- Reason: reduces rebuilds and improves perf; also enforced by the `widget_purity` analyzer.

## Gradient direction

When NDS `background.type: gradient` with `background.direction: <angle>` (degrees):

| Angle | Flutter alignment pair |
|---|---|
| 0 or 180 | `begin: Alignment.topCenter, end: Alignment.bottomCenter` |
| 90 | `begin: Alignment.centerLeft, end: Alignment.centerRight` |
| 270 | `begin: Alignment.centerRight, end: Alignment.centerLeft` |
| 45 | `begin: Alignment.topLeft, end: Alignment.bottomRight` |
| 135 | `begin: Alignment.topRight, end: Alignment.bottomLeft` |
| 225 | `begin: Alignment.bottomRight, end: Alignment.topLeft` |
| 315 | `begin: Alignment.bottomLeft, end: Alignment.topRight` |
| other | `Alignment(cos(angle), sin(angle))` |

## Opacity application

When NDS sets `background.opacity: <float>` together with a token resolved by `color_map.yaml`:

```dart
AppColors.tokenName.withValues(alpha: <opacity>)
```

NEVER pre-multiply alpha into a hex literal. The token resolves to the base color; opacity is a separate concern.

## DO / DON'T summary

| DO | DON'T |
|---|---|
| Use `const` constructors wherever possible | Hardcode `Color(0xFFRRGGBB)` literals |
| Use theme tokens from `color_map.yaml` | Use raw hex strings |
| Use `Expanded` inside `Row`/`Column` for dynamic-content children | Use `shrinkWrap: true` on dynamic lists |
| Use `ListView.builder` for repeating API-driven items | Nest `ListView` inside `Column` without `Expanded` |
| Always set `fit:` on every image-family widget | Omit `fit:` on any `Image.*` / `SvgPicture.*` / `Lottie.*` |
| Add `maxLines` + `overflow` to all dynamic `Text` | Leave dynamic `Text` without overflow protection |
| Use `Image.asset` etc. for icons | Substitute icons with Unicode emoji |
| Emit `// TODO: asset missing` when file not found | Emit broken `.asset()` paths that crash at runtime |
| Use `LinearGradient` with full stops for gradients | Reduce a gradient to a single dominant color |
| Use `MediaQuery.sizeOf(context)` for responsive widths | Hardcode pixel widths |
