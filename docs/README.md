# `docs/`

Long-form documentation for package authors and consumers.

## What lives here

- [`PROJECT_WALKTHROUGH.md`](PROJECT_WALKTHROUGH.md) — **visual walkthrough** with mermaid diagrams (architecture, pipeline sequence, adapter selection, artifact flow, CLI map) + recommended reading order. **Start here if you're new.**
- [`CONSUMER_INTEGRATION.md`](CONSUMER_INTEGRATION.md) — step-by-step guide for a Flutter project that wants to adopt alea_flow (full reference).
- [`adr/`](adr/) — 18 Architectural Decision Records, one per design decision (0001 = invariants … 0018 = self-package resolution).

## TBD (planned — not yet written)

- `extending-the-pipeline.md` — adding a new adapter / analyzer / gate.
- `contracts-versioning.md` — when to bump major vs minor; deprecation policy.

## What does NOT live here

- Per-adapter docs — those live in each adapter's own folder.
- API reference — generated from doc comments in `contracts/` and `lib/`, not hand-written.
- Slash command usage — that's in each command's frontmatter under `core/commands/`.
