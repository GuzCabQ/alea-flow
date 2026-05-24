# Theme Map — Shared Sub-Phase

Maps each NDS color value (background fills, border colors, text colors) to the nearest theme token defined in the consumer project, by RGB distance. Invoked by every design-source adapter as the last sub-phase before emitting `DesignExtractionResult`.

## Inputs

- `nds` — the NDS document the calling adapter has just extracted.
- `config` — the loaded `ProjectConfig`. Specifically: `config.theme.path` and `config.theme.brand_colors`.
- `run_dir` — the directory under `.pipeline/runs/<ticket_id>/` for this adapter's artifacts.

## Output

`<run_dir>/color_map.yaml` — one entry per NDS color reference, with `decision` (USE_EXACT / USE_CLOSEST / CREATE_NEW), `token` (the resolved token name), and `delta_pct` (when not exact).

## Steps

### 1. Build the theme token table (if absent or stale)

Check whether `<run_dir>/theme_tokens.csv` exists AND is newer than `config.theme.path`. If stale or absent, regenerate:

```
For the file at config.theme.path (and any files it imports/exports within the project):
  Find every const declaration of shape: `static const Color <name> = Color(0x<hex>);`
                                       OR: `Color get <name> => Color(0x<hex>);`
                                       OR: `<name>: Color(0x<hex>);`           (used in maps)
  Append to theme_tokens.csv:
    token_name, hex_value, type (solid | gradient), file_path
```

Also include the brand colors from `config.theme.brand_colors`:

```
For (name, hex) in config.theme.brand_colors:
  Append: name, hex, solid, <synthetic — declared in .alea.yaml>
```

### 2. Match each NDS color

For every NDS element where `background.value`, `border.color`, or `style.color` is non-null:

#### 2a. Solid colors

Run the RGB distance algorithm:

```
delta(c1, c2) = sqrt( (R1-R2)² + (G1-G2)² + (B1-B2)² ) / sqrt(255² * 3)

# delta is normalized to 0.0 - 1.0 (0 = identical, 1 = max distance)
# Express as percentage: delta_pct = delta * 100
```

Find the token with minimum `delta_pct`. Apply thresholds:

| `delta_pct` | Decision |
|---|---|
| `0.0` (exact match) | `USE_EXACT` |
| `0.0 – 30.0` | `USE_CLOSEST` |
| `≥ 30.0` | `CREATE_NEW` (flag for human review; emit raw hex as fallback) |

#### 2b. Gradient colors

For each stop in `background.value` (comma-separated hex list), run the solid-color algorithm independently. Combine into a synthetic gradient token reference:

```
gradient_<element_id>:
  stops:
    - { nds_value: "#X", decision: ..., token: ..., delta_pct: ... }
    - { nds_value: "#Y", decision: ..., token: ..., delta_pct: ... }
```

If every stop resolves to USE_EXACT or USE_CLOSEST AND the consumer's theme has a matching gradient helper → use that helper. Otherwise the code-gen adapter materializes a `LinearGradient` with the resolved stops.

### 3. Build the color_map entry

```yaml
<element_id>_<role>:                  # role ∈ {bg, border, text}
  nds_value: "#RRGGBB"                # original from NDS
  opacity: 0.0–1.0                    # if background.opacity was set
  decision: USE_EXACT | USE_CLOSEST | CREATE_NEW
  token: <theme_token_name> | null    # null when CREATE_NEW
  delta_pct: <float>                  # 0 for USE_EXACT; null when CREATE_NEW (no nearest)
  note: "<one-line explanation>"
```

### 4. Save and return

Persist `<run_dir>/color_map.yaml`. The calling adapter packages this path into the `DesignExtractionResult.colorMap` field.

## Reference: RGB distance pseudo-code

```dart
double colorDistancePct(String hexA, String hexB) {
  final a = _parseHex(hexA);
  final b = _parseHex(hexB);
  final dr = a.r - b.r;
  final dg = a.g - b.g;
  final db = a.b - b.b;
  final raw = math.sqrt(dr * dr + dg * dg + db * db);
  final max = math.sqrt(255 * 255 * 3);
  return (raw / max) * 100.0;
}

({int r, int g, int b}) _parseHex(String hex) {
  final s = hex.replaceFirst('#', '');
  return (
    r: int.parse(s.substring(0, 2), radix: 16),
    g: int.parse(s.substring(2, 4), radix: 16),
    b: int.parse(s.substring(4, 6), radix: 16),
  );
}
```

The Dart version of this algorithm lives at `_common/scripts/color_distance.dart` (created in step 9). Until then, AI executes the math inline.

## What this map does NOT do

- Does NOT modify `app_theme.dart` or any other consumer file. CREATE_NEW decisions are flagged for human review; never auto-add tokens.
- Does NOT pick non-color tokens (typography, spacing). Those are resolved during code generation, not here.
- Does NOT enforce a max delta. Anything ≥ 30% is `CREATE_NEW`, but the raw hex is preserved so the code-gen adapter can still produce a syntactically-valid widget (Agent 5 / visual-fidelity will catch the hex-literal-in-output as a `theme_compliance` violation, surfacing it as a real issue rather than silently inventing a token).

## Failure modes

| Condition | Behavior |
|---|---|
| `config.theme.path` does not point to a readable file | Skip theme extraction. Use only `config.theme.brand_colors`. If those are empty too, emit `color_map.yaml` with `CREATE_NEW` for every entry and warn the user. |
| NDS has no color-bearing elements | Emit empty `color_map.yaml`. Calling adapter continues. |
| Two tokens tie on `delta_pct` | Prefer the brand color (declared in `.alea.yaml`) over the extracted token. If neither is a brand color, prefer the one whose name appears first alphabetically (deterministic). |
