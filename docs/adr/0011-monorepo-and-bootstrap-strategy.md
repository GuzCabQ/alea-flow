# ADR-0011 — Monorepo strategy and zero-to-running bootstrap

- **Status:** Accepted
- **Date:** 2026-05-24
- **Phase:** 10

## Context

[ADR-0010](0010-cli-consolidation.md) shipped the single binary with six subcommands. Adoption testing surfaced two gaps that block ALEA from running on greenfield projects:

1. **Zero-to-running cost is too high.** A new consumer must hand-author `.alea.yaml`, hand-create layer folders, hand-stub a theme tokens file, and hand-wire a router before `aflow analyze` does anything useful. The quickstart in [`README.md`](../../README.md) lists the config but assumes the surrounding skeleton already exists.
2. **No first-class monorepo story.** [`ARCHITECTURE.md:168`](../../ARCHITECTURE.md) states *"ALEA assumes one Flutter project per consumer. Monorepos can run ALEA per-package."* In practice, large teams ship as a modular monorepo (Melos / Pub workspaces) where features live as sibling Dart packages and the design system is its own package. Every feature package would need to redeclare its own token catalog, duplicating the design system's source of truth.

Both gaps are felt every time a team adopts ALEA. Neither is a contracts-level problem — the existing schema and adapters are flexible enough; what's missing is ergonomics and an opinionated reference for the monorepo case.

## Decision

A three-part strategy, sequenced by cost. Parts 1 and 2 ship together in v1.1; part 3 lands in v1.2 or later.

### Part 1 — `aflow init`: bootstrap a project skeleton in one command

A seventh CLI subcommand that writes a usable `.alea.yaml` + layer folders + theme stub + router stub + test fakes folder into a target directory.

```
alea init [<package_name>]
  --template, -t   project | feature   (default: project)
  --output, -o     Directory to write into (default: cwd)
  --style          riverpod_manual | bloc | provider | getx (default: riverpod_manual)
  --force          Overwrite existing files
  --dry-run        Print the plan, write nothing
```

**Two templates:**

- **`project`** — for a Flutter app (post `flutter create`). Writes the consumer-facing ALEA layer: `.alea.yaml`, `lib/src/{domain,infrastructure,presentation}/`, `lib/src/theme/{tokens.dart,app_theme.dart}`, `lib/src/app/router.dart`, `test/fakes/`. The theme stub seeds `AppColors` and `AppTypography` with neutral defaults so `aflow match color #HEX` and `visual_fidelity` analyzer have something to resolve against on day 1.
- **`feature`** — for a monorepo feature package. Writes a Dart package skeleton: `pubspec.yaml` (Dart-only, no Flutter platform deps), `.alea.yaml` pointing its token catalog at `../design_system/lib/`, the three layer folders, public barrel file, `test/fakes/`. Defaults are tuned for the monorepo case in part 2.

**Reuses the existing `TemplateEngine`** ([`lib/src/scaffolding/template_engine.dart`](../../lib/src/scaffolding/template_engine.dart)) for variable substitution. Templates are embedded as Dart strings in the same module — consistent with how `riverpod_manual` and `bloc` adapters ship their templates today.

**Idempotency.** `aflow init` refuses to write a file that already exists unless `--force` is passed. `--dry-run` prints the plan as a tree.

**Not in scope for `aflow init`:**

- Running `flutter create` itself — ALEA doesn't manage platform bindings.
- Initializing git, husky, CI configs — out of scope.
- Wiring third-party packages (Riverpod, GoRouter) into `pubspec.yaml` — the `project` template assumes the consumer added them.

### Part 2 — External token catalog source: monorepo-aware `.alea.yaml`

Allow `theme.token_catalog.source` in `.alea.yaml` to point **outside the package** at a sibling Dart package's source tree. The factory at [`lib/src/adapters/token_catalog/factory.dart:39-41`](../../lib/src/adapters/token_catalog/factory.dart) already resolves relative paths against `projectRoot` — meaning `source: ../design_system/lib/` works today *but is undocumented and untested*.

The work is small and explicit:

1. **Test coverage** — a new test under [`test/adapters/token_catalog/`](../../test/adapters/token_catalog/) that creates two sibling temp dirs (`feature_wallet/` and `design_system/`), points the former's `.alea.yaml::theme.token_catalog.source` at `../design_system/lib/`, and confirms the catalog resolves correctly.
2. **Documentation** — the `dart_source` adapter README and [`CONSUMER_INTEGRATION.md`](../CONSUMER_INTEGRATION.md) explicitly call out the monorepo pattern with an example.
3. **Validation** — the factory currently does no pre-existence check on the resolved source (by design — first I/O happens on first method call). When the source is external, the failure mode is "directory not found" deep in the adapter. We surface this with a clearer `ProjectConfigException` at config-load time when the path is absent, since debugging across package boundaries is harder than within one.

### Part 3 (future, v1.2+) — Bootstrap adapter for `design_system` from a design source

When a team starts with a Figma design-system file or a brand-guide PDF, the entire `design_system` package (tokens, color constants, typography scale, spacing constants, possibly base widgets) can be generated. This becomes a new adapter family — `bootstrap_source/` — paralleling the existing `design_source/`, `ticket_source/`, `code_gen/` families.

This is **not in this ADR's scope to implement**. We commit only to the contract shape: a `BootstrapAdapter` takes a source URI (figma:// or file://) and emits a populated `design_system` package directory. Concrete adapters (`bootstrap_source/figma/`, `bootstrap_source/json/`) are deferred until a real consumer asks for it.

## Why this ordering

| Part | Cost | Benefit | Why now / later |
|---|---|---|---|
| 1 | Medium — one command, templates, tests | High — every new consumer benefits | Now: every onboarding hits this gap |
| 2 | Low — already works, needs validation + test + docs | High — unblocks the monorepo case | Now: trivial to ship alongside Part 1 |
| 3 | High — new adapter family, schemas, design | Medium — one-shot setup, used once per design system | Later: wait for a real consumer to validate the shape |

Shipping 1+2 together gives the team enough to start running ALEA on both single-app and monorepo projects without manual bootstrapping. Part 3 is the cherry on top — it's the kind of feature that's tempting to over-design before there's a forcing function.

## Module dependency impact

```
                            ┌──────────────────┐
                            │  alea init       │  (NEW — Part 1)
                            │  (CLI subcommand)│
                            └────────┬─────────┘
                                     │
                              embeds templates
                                     │
                                     ▼
                            ┌──────────────────┐
                            │ TemplateEngine   │  (existing — reused)
                            │ scaffolding/     │
                            └──────────────────┘

       feature_wallet/                         design_system/
       ┌─────────────────────┐                 ┌──────────────────┐
       │ .alea.yaml          │ ◀── reads ───   │ lib/             │
       │  theme:             │                 │   colors.dart    │
       │   token_catalog:    │                 │   typography.dart│
       │    source:          │                 │                  │
       │     ../design_      │                 └──────────────────┘
       │     system/lib/     │ (Part 2 — already works,
       └─────────────────────┘  needs test + docs + clearer error)
```

## Consequences

**Positive:**

- A team with no prior ALEA experience can go from `flutter create my_app` → `aflow init` → `aflow analyze` in under 5 minutes.
- Monorepo teams declare their design system **once** and every feature package consumes it. No duplication of token sources, no drift between feature packages.
- Both shipped pieces are additive — no consumer's existing `.alea.yaml` breaks.
- `aflow init`'s `--dry-run` makes the template's behaviour fully inspectable before any disk write.

**Negative:**

- `aflow init` ships templates that **freeze opinions** (Riverpod manual + go_router + Clean Architecture three-layer split). Teams using a different stack must `init`, then edit. Mitigated by `--style` flag at minimum; the layered convention is presumed by ALEA's analyzers anyway, so editing it is rare.
- External token catalog requires the consumer to set up the monorepo themselves (Melos / Pub workspaces). ALEA does not opine on which.
- Part 3's "bootstrap adapter" surface is left explicit but unimplemented. Risk: someone in v1.2 designs it differently than this ADR sketches. Mitigated by the ADR being non-prescriptive about the adapter's internals — only its position in the family taxonomy.

## References

- [`README.md`](../../README.md) — quickstart section that this ADR makes runnable.
- [`ARCHITECTURE.md`](../../ARCHITECTURE.md) — monorepo limitation called out at line 168.
- [`docs/CONSUMER_INTEGRATION.md`](../CONSUMER_INTEGRATION.md) — gains a "Monorepo setup" section.
- [`docs/PROJECT_WALKTHROUGH.md`](../PROJECT_WALKTHROUGH.md) §7 — CLI map gets a 7th subcommand.
- [ADR-0010](0010-cli-consolidation.md) — established the CLI dispatch pattern.
- `lib/src/cli/commands/init_command.dart` — implementation.
- `test/cli/init_command_test.dart` — smoke tests.
- `test/adapters/token_catalog/external_source_test.dart` — Part 2 coverage.
