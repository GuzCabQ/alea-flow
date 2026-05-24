# `visual_fidelity` analyzer

Checks that generated Flutter widget code satisfies the rules in [`../../../../adapters/code_gen/_common/flutter-defaults.md`](../../../../adapters/code_gen/_common/flutter-defaults.md) and (when an NDS document is available in the run directory) matches the design spec.

Ported from `flutter-ui/SKILL.md` Agent 5 critical-fail checks. Each rule here is what made Agent 5's `FidelityScore` "pass with zero critical fails AND score ≥ 90". The score itself is computed by the `fidelity` gate (step 8.5); this analyzer emits issues, not scores.

## Rules (v1)

| Rule id | Severity | Active | What it checks |
|---|---|---|---|
| `visual_fidelity/missing_image_fit` | `critical` | ✅ | `Image.asset/network/file/memory`, `SvgPicture.asset/network/string`, `Lottie.asset/network/memory/file` calls without a `fit:` named argument. |
| `visual_fidelity/emoji_as_icon` | `critical` (when NDS source = figma) / `major` (otherwise) | ✅ | `Text("...")` whose string is composed entirely of Unicode emoji code points (length ≤ 4 chars). |
| `visual_fidelity/button_without_content` | `blocker` | ✅ | `ElevatedButton`/`TextButton`/`OutlinedButton`/`FilledButton`/`CupertinoButton` whose subtree contains no `Text`, `Image`, `Icon`, `SvgPicture`, `Lottie`, `RichText`, or `SelectableText`. `IconButton` is exempt (always has `icon:` by definition). |
| `visual_fidelity/asset_path_broken` | `critical` | ✅ | `Image.asset("p")` / `SvgPicture.asset("p")` / `Lottie.asset("p")` where `<projectRoot>/<p>` does not exist on disk AND no `// TODO: ... asset/missing/unknown` comment precedes the call within the prior ~3 lines. `packages/...` paths are skipped (those resolve against the imported package). |
| `visual_fidelity/ignored_widget_hint` | `blocker` | 🚧 STUB | When NDS has `widget_hint`, the consumer's generated code is expected to use that widget. STUB until code-gen emits NDS-element annotations that this analyzer can correlate. |
| `visual_fidelity/gradient_degraded` | `blocker` | 🚧 STUB | When NDS says `background.type: gradient`, the generated code must emit `BoxDecoration(gradient: ...)`, not `BoxDecoration(color: ...)`. STUB for the same reason — needs NDS-annotation coordination. |

The two stubs are intentional placeholders: the rules are documented and the analyzer's structure includes a slot for them, but the detection logic is deferred until [`adapters/code_gen/_common/flutter-defaults.md`](../../../../adapters/code_gen/_common/flutter-defaults.md) adds the convention of emitting `// alea:nds_ref=<element_id>` annotations next to NDS-derived widgets.

## Inputs (from `AnalyzerContext`)

- `filePaths` — Dart files to inspect. Typically the `files_changed` list from the most recent `<layer>_impl.md`.
- `projectRoot` — consumer project root; used for asset path resolution.
- `runDirectory` — `.pipeline/runs/<ticket_id>/` (optional). When present, the analyzer walks any subdirectory for `nds.yaml` and reads `document.source.adapter` to decide emoji rule severity. Without it, emoji is `major`.
- `config` — `ProjectConfig`. Not currently consulted by the AST-only rules but reserved for future per-consumer overrides.

## Severity rationale

Three tiers reflect "what fails when this slips into production":

- **`blocker`** — broken UX or undefined widget behavior. `button_without_content` produces a button with empty press target; nothing visible to the user.
- **`critical`** — runtime exceptions or layout instability. `asset_path_broken` crashes when the widget builds. `missing_image_fit` causes unbounded constraint errors in some contexts. `emoji_as_icon` (figma) means the design's icon was lost — the bug is silent until QA notices, but the design intent is gone.
- **`major`** — likely a bug, less certain. `emoji_as_icon` outside a figma run gets this severity because the emoji might be intentional in non-design-driven flows.

Consumers can demote any rule via `.alea.yaml::analyzers.severity_overrides.visual_fidelity: <severity>` — applied by the runner, not by this analyzer.

## What this analyzer does NOT do

- Does NOT verify visual pixel-fidelity (no rendering, no screenshot diff).
- Does NOT compute the FidelityScore. The `fidelity` gate composes this analyzer with other metrics and produces the score.
- Does NOT modify the consumer's code.
- Does NOT enforce `package:alea/...` self-imports in the consumer's project; that's the `layer_integrity` analyzer's job.
- Does NOT check that NDS itself is well-formed. NDS validation against `nds.schema.yaml` happens in `/design-feature`; if NDS is malformed, this analyzer simply emits nothing for NDS-dependent rules.

## Failure modes

| Condition | Behavior |
|---|---|
| `runDirectory` is null | All AST-only rules run normally. NDS-dependent severity downgrades emoji to `major`. Stub rules emit nothing. |
| `runDirectory` exists but no NDS file found in any subdirectory | Same as above. |
| NDS file present but malformed (won't parse as YAML, or schema-invalid) | The analyzer silently skips NDS source detection. The malformed-NDS issue is surfaced by the design-source adapter's validation, not here. |
| Asset path resolution fails (e.g. `projectRoot` doesn't exist) | The `asset_path_broken` rule treats the asset as not-existing and emits the issue. Defensive: if the project root is wrong, ALL assets look broken, surfacing the configuration problem quickly. |

## Determinism

Same input files + same NDS → same issues bytewise, in file-then-line order.
