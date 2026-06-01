---
description: Enriches a .alea.yaml draft by grounding structural fields (layer paths, import rules) from the real code graph, replacing PLACEHOLDERs and surfacing architectural issues.
---
# `/aflow-complete-config` — Complete `.alea.yaml` from the code graph

Enriches a `.alea.yaml` draft using the verified structure of the code graph. Where `aflow init --template config` left PLACEHOLDERs (non-canonical layer names, feature-first layouts), this grounds the structural fields in real directories and dependency edges, and surfaces architectural issues. The AI proposes; the human disposes via a diff.

## Usage

```
/aflow-complete-config
```

## What it grounds vs. what stays human

- **Grounded from the graph** (marked `# from graph: <evidence>`): `architecture.layers` paths and `may_import` / `forbid_imports` direction.
- **Never invented** (preserved or left `# human decision`): `ticket_source`, `design_source`, `coverage.thresholds`, `mr.policy`, `state_management.style` (from pubspec, not the graph), `routing`. `project.package_name` comes from `pubspec.yaml` (as `init` already sets it).

## Steps

### 1. Build/refresh the graph

```bash
aflow graph --ensure-fresh -o .pipeline/graph.json --project-root .
```

If `aflow` is unavailable, STOP and report — do not infer structure by hand.

### 2. Query the structure (do NOT read graph.json whole)

```bash
aflow graph-query structure -i .pipeline/graph.json --project-root . --format json
```

This returns `clusters[]` (`path`, `file_count`, `imports_flutter`), `cluster_edges[]` (`from`, `to`, `count`), and `cyclic_clusters[]`.

### 3. Propose `architecture.layers`

From `clusters[]`, pick the directories that are architectural layers (largest, top-level under the source roots; ignore leaf utility dirs). Map each to a layer key. Prefer the consumer's existing key names if a `.alea.yaml` draft exists; otherwise use the directory's last segment (`data`, `ui`, `dominio`, …) — do not force `domain`/`infrastructure`/`presentation` onto a project that named them otherwise.

For each chosen layer, set `paths: [<cluster.path>/]` and mark `# from graph: <N> files`.

### 4. Infer `may_import` / `forbid_imports` from `cluster_edges`

- If layer A's cluster has edges **to** layer B's cluster (`from: A, to: B`), then `A.may_import: [B]`. List every B that A actually imports.
- A layer with **no** outgoing edges to other layers (a sink) is the dependency-free core — propose `forbid_imports: ["package:flutter/"]` for it (the classic pure-domain rule), and confirm against `imports_flutter`.

### 4b. Account for code outside every layer (declare or exclude)

The graph collects all of `lib/` (opt-out). Files matching no declared layer are **unlayered** — invisible to layer rules until classified. Surface them as a bounded signal:

```bash
aflow graph-query unlayered -i .pipeline/graph.json --project-root . --format json
```

This returns `unlayered[]` (`path`, `file_count`). For each cluster, propose ONE of:
- **Declare** it under a layer (extend an existing `paths:` with a glob like `lib/src/feature/*/presentation/`, or add a new layer) when it is real architecture — e.g. a feature-first `lib/src/feature/` tree.
- **Exclude** it via `graph.exclude` (a glob) when it is generated or non-architectural — e.g. `lib/assets/template/`, vendored code. (Generated `*.g.dart`/`*.freezed.dart` are excluded by default.)

Never leave a non-trivial cluster unaddressed: an unlayered file is a blind spot for the whole pipeline (impact/regression/gates). State the choice per cluster in the diff.

### 5. Surface diagnostics (warnings, not edits)

- For each entry in `cyclic_clusters[]`: warn `Import cycle between <clusters> — Clean Architecture forbids it; consider inverting a dependency.`
- For any cluster you mapped as the pure core whose `imports_flutter` is `true`: warn `<layer> imports package:flutter but is your domain core — this breaks domain purity (forbid_imports).`

### 6. Present the diff and let the human dispose

Show the proposed `.alea.yaml` changes as a unified diff. Grounded lines carry `# from graph:`; untouched/uncertain lines carry `# human decision`. **Write only after the human approves.** Never overwrite silently. If `.alea.yaml` does not exist, run `aflow init --template config` first to produce the skeleton, then enrich it here.

### 7. Validate the result

After writing, reload the config by running any command that parses it:

```bash
aflow graph --ensure-fresh -o .pipeline/graph.json --project-root .
```

A config-load failure exits `2` — STOP and fix; never leave an invalid `.alea.yaml`.

## What this command MUST NOT do

- ❌ Read `graph.json` whole into context. Use `graph-query structure` (a bounded summary).
- ❌ Invent `ticket_source` / `design_source` / `coverage` / `mr` / `routing` / `state_management` values. Those are human decisions.
- ❌ Force canonical layer names onto a project that named its layers differently.
- ❌ Overwrite `.alea.yaml` without showing the diff and getting approval.
