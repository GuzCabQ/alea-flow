# Consumer Integration Guide

This guide takes a Flutter project that has **never used ALEA** and walks
through every decision point to wire it in. It assumes you have read the
top-level [`README.md`](../README.md) and want concrete steps.

By the end of this guide:

- Your project root contains a `.alea.yaml`.
- `aflow analyze` produces a gate report against your codebase.
- `aflow match`, `scaffold`, `inventory`, `journal`, and `context` are
  usable from your shell.
- CI fails when generated code or human code violates your declared
  architectural rules.

---

## 1 — Install

```bash
git clone <alea-repo>
cd alea
dart pub get
./tool/compile.sh         # produces bin/aflow (≈10 MB native executable)
sudo ln -s "$(pwd)/bin/aflow" /usr/local/bin/aflow
```

Verify:

```bash
aflow --help
```

You should see seven subcommands listed.

---

## 1.5 — Bootstrap with `aflow init` (optional, recommended for new projects)

If your Flutter project does not yet have the layer folders, theme stub,
and router that ALEA expects, run `aflow init` to scaffold them. Skip this
section if you already have a hand-rolled `.alea.yaml`.

### For a single Flutter app

```bash
flutter create my_app
cd my_app
alea init my_app --template project
```

Writes:

- `.alea.yaml` at the package root (pre-filled with sensible defaults).
- `lib/src/{domain,infrastructure,presentation}/.gitkeep` — the three
  Clean Architecture layers.
- `lib/src/theme/{tokens.dart,app_theme.dart}` — a working theme catalog
  with `AppColors` and `AppTypography` you can edit immediately.
- `lib/src/app/router.dart` — a minimal GoRouter setup.
- `test/fakes/.gitkeep` — for fake repository implementations.

Add `go_router` to your `pubspec.yaml` (ALEA does not touch it), then run
`aflow analyze --gate domain` to confirm the skeleton is sound.

### For a feature package in a monorepo

```bash
cd packages/
alea init feature_wallet --template feature
```

Writes a Dart-only package (no Flutter platform code) whose `.alea.yaml`
points its **token catalog at the sibling `design_system` package** by
default (`source: ../design_system/lib/`). This is the modular monorepo
pattern from [ADR-0011](adr/0011-monorepo-and-bootstrap-strategy.md):
every feature consumes the same design system without redeclaring its
tokens.

Override the design system path when needed:

```bash
alea init feature_wallet --template feature \
  --design-system-path ../../shared/design_system
```

Other useful flags: `--style bloc` (or `provider`, `getx`), `--dry-run`
(prints the plan, writes nothing), `--force` (overwrites pre-existing
files).

---

## 2 — Create `.alea.yaml`

Place it at the root of your Flutter project (sibling to `pubspec.yaml`).
The minimum required shape is below; each section is explained in the
sections that follow.

```yaml
config_version: "1.0.0"

project:
  package_name: my_app                # MUST match pubspec.yaml::name
  pubspec_path: pubspec.yaml

architecture:
  layers:
    domain:        { paths: [lib/src/domain/]        }
    infrastructure: { paths: [lib/src/infrastructure/], may_import: [domain] }
    presentation:  { paths: [lib/src/presentation/], may_import: [domain]   }

state_management:
  style: riverpod_manual

routing:
  package: go_router
  router_path: lib/src/app/router.dart

theme:
  path: lib/src/theme/

testing:
  framework: flutter_test
  fakes_path: test/fakes/

coverage:
  thresholds: { domain: 95, infrastructure: 80, presentation: 70 }

ticket_source: { adapter: file }
design_source: { default: figma }

mr:
  policy: single-commit-amend
  branch_pattern: "feature/{ticket_id}-{slug}"
  pre_push: [dart format ., dart analyze, flutter test]

pipeline:
  default_mode: guided
  modes_available: [guided, semi, auto]
  cost_warn_usd: 3.0
  cost_hard_stop_usd: 5.0

gates:
  domain: [domain]
  infrastructure: [infra]
  presentation: [presentation]
```

Validate it loads:

```bash
alea analyze --project-root . --gate domain
```

If the config is malformed, the CLI exits with code 2 and a message
pointing at the offending field.

---

## 3 — Architecture rules

### 3.1 Layers (mandatory)

`architecture.layers` is a map of layer name → paths + import policy.
The `LayerIntegrityAnalyzer` enforces "may import" vs "forbid imports".

```yaml
architecture:
  layers:
    domain:
      paths:
        - lib/src/domain/
      forbid_imports:
        - "package:flutter/"
        - "package:my_app/src/infrastructure/"
        - "package:my_app/src/presentation/"
    infrastructure:
      paths:
        - lib/src/infrastructure/
      may_import: [domain]
      forbid_imports:
        - "package:my_app/src/presentation/"
    presentation:
      paths:
        - lib/src/presentation/
      may_import: [domain]
      forbid_imports:
        - "package:my_app/src/infrastructure/"   # optional; stricter
```

> **Tip.** The package self-prefix `package:my_app/` must match
> `project.package_name`. If your `pubspec.yaml::name` is `foo_bar`,
> use `package:foo_bar/…`.

### 3.2 Package boundaries (optional — library packages)

For library packages that ship contracts + adapters, declare boundary
rules orthogonal to Clean-Architecture layers:

```yaml
architecture:
  package_boundaries:
    - name: contracts_purity
      description: contracts may only depend on dart:core + meta.
      applies_to:
        - lib/src/contracts/
      forbid:
        - dart:io
        - package:analyzer/
        - package:my_app/src/adapters/
```

These are read by `PackageBoundaryAnalyzer` and enforced like any other
analyzer.

### 3.3 Wiring (optional — DI / routes registration)

`WiringCohesionAnalyzer` checks that every class matching a pattern is
referenced inside a specific call in a manifest file.

```yaml
architecture:
  wiring:
    rules:
      - name: services
        class_pattern: "*Service"
        manifest_file: lib/src/injector.dart
        registration_call: registerSingleton
      - name: repositories
        class_pattern: "*Repository"
        manifest_file: lib/src/injector.dart
        registration_call: registerSingleton
      - name: screens
        class_pattern: "*Screen"
        manifest_file: lib/src/config/routes.dart
        registration_call: GoRoute        # or AutoRoute, GetPage…
```

Examples per stack:

| Stack | `registration_call` |
|---|---|
| GetX | `Get.put` |
| get_it (manual) | `registerSingleton` |
| get_it (lazy) | `registerLazySingleton` |
| Riverpod (manual) | `registerSingleton` (when paired with get_it) |
| go_router | `GoRoute` |
| auto_route | `AutoRoute` |
| GetX routes | `GetPage` |

---

## 4 — State management

Just one knob:

```yaml
state_management:
  style: riverpod_manual    # | bloc | provider | getx | …
```

The value drives which code-gen adapter `aflow scaffold` picks by default
(can be overridden with `--style`). Built-in adapters:

- `riverpod_manual` — `Notifier<State>` + `NotifierProvider`, no codegen.
- `bloc` — sealed state + sealed event + `Bloc<E, S>`.

To add a new adapter (`provider`, `getx`, `mobx` …), create
`lib/src/adapters/code_gen/<style>/{adapter.dart,templates.dart}` in the
ALEA tree. See [ADR-0008](adr/0008-executable-code-generation.md) for the
contract.

---

## 5 — Theme & token catalog

Declare WHERE your design tokens live and HOW they are encoded:

```yaml
theme:
  path: lib/src/theme/
  token_catalog:
    adapter: dart_source      # or `json` (Style Dictionary)
    source: lib/src/theme/    # directory (dart_source) or file (json)
    conventions:
      color_class: StyleColors
      typography_class: StyleFonts    # optional (Phase 2 supports colors only)
```

Two adapters ship out of the box:

### 5.1 `dart_source` adapter

Reads a Dart class with `static const Color` fields:

```dart
// lib/src/theme/style_colors.dart
class StyleColors {
  static const Color primary = Color(0xFF0066CC);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF7F8FA);
}
```

The class name comes from `conventions.color_class`. If your project uses
`Palette` instead, configure:

```yaml
conventions:
  color_class: Palette
```

### 5.2 `json` adapter

Reads a Style-Dictionary-style JSON file:

```json
{
  "color": {
    "brand": { "primary": { "value": "#0066CC" } }
  },
  "typography": {
    "body": { "value": { "fontSize": 16, "fontWeight": 400 } }
  }
}
```

```yaml
theme:
  token_catalog:
    adapter: json
    source: tokens/design-tokens.json
```

### 5.3 Using the catalog

Once configured, `aflow match` resolves arbitrary inputs:

```bash
alea match color "#0066CC"
# → recommended: StyleColors.brand60 (ΔE = 0.00, match)

alea match typography "16/semibold"
# → recommended: StyleFonts.body2

alea match spacing 16 --unit px
# → recommended: spacing.md
```

`VisualFidelityAnalyzer` (Phase 4) uses the same resolvers against
NDS-extracted designs.

### 5.4 Monorepo: external token catalog source

In a modular monorepo (Melos / Pub workspaces), the design system is its
own package and every feature package consumes it. Point
`token_catalog.source` at the sibling package's `lib/` instead of an
intra-project directory:

```yaml
# packages/feature_wallet/.alea.yaml
theme:
  path: ../design_system/lib/
  token_catalog:
    adapter: dart_source
    source: ../design_system/lib/
    conventions:
      color_class: AppColors
```

ALEA resolves the relative path against the package's own root, so the
path above refers to `<monorepo>/packages/design_system/lib/`. **The
target must exist at config-load time** — when it doesn't, ALEA fails
with a clear error pointing at the resolved absolute path (this is the
guard introduced by [ADR-0011](adr/0011-monorepo-and-bootstrap-strategy.md)
Part 2; intra-project paths stay lazy and are only read on first
catalog method call).

Both `dart_source` and `json` adapters support external sources. The
generated config from `aflow init --template feature` uses this pattern
by default.

---

## 6 — Coverage thresholds

```yaml
coverage:
  thresholds:
    domain: 95
    infrastructure: 80
    presentation: 70
```

Values are integers (percent). Each key must match a layer name.
Thresholds drive Gate-Final coverage checks.

---

## 7 — Ticket source

```yaml
ticket_source:
  adapter: file        # or asana, linear, jira, …
  config:
    inbox_dir: .pipeline/tickets/
```

`file` reads from a local directory (Markdown or JSON). Other adapters
hit their respective APIs. The `config:` block is free-form — each
adapter documents what it consumes.

---

## 8 — Design source

```yaml
design_source:
  default: figma
  adapters:
    figma:
      enabled: true
      options:
        viewport_baseline_width: 430
        viewport_baseline_height: 932
    image:
      enabled: false
    markup:
      enabled: false
```

Adapters listed under `adapters:` are individually enabled/disabled.
Selection at runtime: `default` if no explicit hint; otherwise the
adapter whose name matches the ticket attachment's
`description` field.

---

## 9 — MR policy

```yaml
mr:
  policy: single-commit-amend           # | feature-branch-merge | …
  branch_pattern: "feature/{ticket_id}-{slug}"
  pre_push:
    - dart format --output=none --set-exit-if-changed .
    - dart analyze
    - flutter test
```

The `pre_push` list is run by `alea create-mr` (or the equivalent skill)
before pushing. Any failing step blocks the push.

---

## 10 — Pipeline operations

```yaml
pipeline:
  default_mode: guided                  # | semi | auto
  modes_available: [guided, semi, auto]
  cost_warn_usd: 3.0
  cost_hard_stop_usd: 5.0
  unreliable_threshold:
    runs_window: 5
    bad_runs_required: 3
    manual_corrections_per_run: 5
```

`cost_warn_usd` warns when the running USD estimate exceeds it;
`cost_hard_stop_usd` aborts the run.

`unreliable_threshold` triggers a forced switch to `guided` mode when
recent runs accumulate too many manual corrections.

---

## 11 — Gates

```yaml
gates:
  domain: [domain]
  infrastructure: [infra]
  presentation: [presentation]
```

Maps layer name → list of gate names to run for that layer. The CLI
exposes the chosen gate via `--gate`.

---

## 12 — Analyzers

```yaml
analyzers:
  enabled:
    - layer_integrity
    - package_boundary
    - visual_fidelity
    - widget_inventory
    - wiring_cohesion
    - flutter_antipatterns
    - widget_purity
  severity_overrides:
    visual_fidelity: critical          # demote any visual_fidelity issue
  options:
    visual_fidelity:
      match_threshold: 0.85
      no_match_threshold: 0.40
      check_colors: true
      check_typography: true
    widget_inventory:
      scan_paths:
        - lib/src/shared/presentation/components/
      token_classes: [StyleColors, StyleFonts, StyleSize]
      output_path: widget_inventory.json
```

- `enabled` — when empty, every registered analyzer runs.
- `severity_overrides` — coerce all issues from an analyzer to the given
  severity (`minor` / `major` / `critical` / `blocker`).
- `options` — per-analyzer free-form bag. Each analyzer documents its
  keys in its README.

---

## 13 — CI integration

### 13.1 GitLab

```yaml
alea_gates:
  stage: test
  image: dart:stable
  script:
    - cd alea && dart pub get && dart compile exe bin/aflow.dart -o /usr/local/bin/aflow
    - cd $CI_PROJECT_DIR
    - alea analyze --project-root . --gate domain --format json --output-file gate_domain.json
    - alea analyze --project-root . --gate presentation --format json --output-file gate_presentation.json
  artifacts:
    paths:
      - gate_*.json
```

### 13.2 GitHub Actions

```yaml
- name: ALEA gates
  run: |
    cd alea && dart pub get && ./tool/compile.sh
    cd $GITHUB_WORKSPACE
    alea/bin/aflow analyze --project-root . --gate domain
```

---

## 14 — Per-state-management examples

### 14.1 Riverpod (manual)

```yaml
state_management: { style: riverpod_manual }

architecture:
  wiring:
    rules:
      - name: services
        class_pattern: "*Service"
        manifest_file: lib/src/injector.dart
        registration_call: registerSingleton
      - name: notifiers
        class_pattern: "*Notifier"
        manifest_file: lib/src/providers.dart
        registration_call: NotifierProvider
      - name: screens
        class_pattern: "*Screen"
        manifest_file: lib/src/app/router.dart
        registration_call: GoRoute
```

### 14.2 Bloc

```yaml
state_management: { style: bloc }

architecture:
  wiring:
    rules:
      - name: services
        class_pattern: "*Service"
        manifest_file: lib/src/injector.dart
        registration_call: registerLazySingleton
      - name: blocs
        class_pattern: "*Bloc"
        manifest_file: lib/src/injector.dart
        registration_call: registerFactory
      - name: screens
        class_pattern: "*Screen"
        manifest_file: lib/src/app/router.dart
        registration_call: AutoRoute
```

### 14.3 GetX

```yaml
state_management: { style: getx }

architecture:
  wiring:
    rules:
      - name: controllers
        class_pattern: "*Controller"
        manifest_file: lib/src/injector.dart
        registration_call: Get.put
      - name: screens
        class_pattern: "*Screen"
        manifest_file: lib/src/app/routes.dart
        registration_call: GetPage
```

---

## 15 — Troubleshooting

### "Error loading config: ProjectConfigException(field=architecture.layers, …)"

Your `.alea.yaml` is missing a required field, or has a type mismatch.
The error message includes a `field=` path you can grep for.

### `LayerIntegrityAnalyzer` flags imports you think are fine

The analyzer uses **prefix matching** on the canonicalized URI. A
`forbid_imports` entry of `package:flutter/` matches every Flutter
import. To allow specific Flutter packages while forbidding most:

```yaml
forbid_imports:
  - "package:flutter/material.dart"
  - "package:flutter/cupertino.dart"
# "package:flutter/foundation.dart" remains allowed
```

### `VisualFidelityAnalyzer` does not flag missing tokens

Three checks:

1. Is `theme.token_catalog` declared? `aflow match color "#000000"` should
   report a verdict — if it fails with "no theme.token_catalog declared",
   you need section 5.
2. Is the analyzer enabled? Add `visual_fidelity` to
   `analyzers.enabled` (or leave `enabled` empty so every analyzer runs).
3. Is an NDS file present in the run directory? Catalog rules only fire
   when `runDirectory/<adapter>/nds.yaml` exists.

### `WiringCohesionAnalyzer` reports false positives

Check that the manifest file actually contains the registration call. The
analyzer is AST-based — it looks for invocations of the call NAME (e.g.
`registerSingleton`), and any PascalCase identifier inside that
invocation's argument list counts as registered.

If your manifest registers via a higher-order function (e.g.
`final services = [AuthService, ProfileService]` then iterating), the
analyzer won't see the registration. Two fixes: refactor to declarative
calls, or declare your higher-order helper as the `registration_call`.

### `aflow scaffold` produces files that don't compile

Two likely causes:

1. Your `architecture.layers.<X>.paths` don't match where your project
   actually puts files. The generator respects whatever you declare —
   garbage in, garbage out.
2. The template assumes packages (`flutter_riverpod`, `flutter_bloc`,
   `equatable`) are in your `pubspec.yaml`. Add them or override the
   templates by forking the adapter.

### `aflow context` regenerates on every call

If TTL hasn't expired but the hash differs, a source file changed. Run
`md5sum .alea.yaml` between calls to confirm. If you want longer cache
windows, raise `--ttl-minutes` — but understand you trade staleness for
cache hit rate.

---

## 16 — Next steps

- Read each analyzer's README under `lib/src/analyzers/<name>/README.md`
  for analyzer-specific configuration.
- Read [ADR-0001](adr/0001-architectural-invariants.md) to understand
  the architectural invariants ALEA enforces on its own codebase.
- Run `aflow scaffold demo --dry-run --style riverpod_manual` to preview
  the generated file set without writing anything.
- Hook `aflow analyze` into your pre-commit hook (Husky, lefthook).

If you find yourself patching ALEA to fit a workflow that isn't covered
here, that's a contract gap — please open an issue describing the
project-specific value you needed to encode.
