# ADR-0009 — Context Packet: hash-stable, cacheable LLM prefix

- **Status:** Accepted
- **Date:** 2026-05-23
- **Phase:** 8

## Context

Anthropic's prompt cache has a 5-minute TTL and yields ~10× cost
reduction when there is a cache hit. To get hits across consecutive
skill invocations in a pipeline run, every skill must send the **same
bytes** as a prefix — otherwise each skill pays the cold cost.

Pre-redesign, each skill assembled its own prefix from
`.alea.yaml` + assorted convention files. Bytes drifted; cache hits
never landed.

The pre-redesign tool `gen_primer.dart` (HORUS) approached the same
problem but with informal hashing and ad-hoc invalidation.

## Decision

A `ContextPacket` artifact — YAML front-matter + markdown body — built
by `ContextPacketBuilder` and persisted at
`.pipeline/runs/<id>/context-packet.md`. Reuse semantics:

```
              ┌──────────────────┐
              │ Existing packet  │
              │ file present?    │
              └────────┬─────────┘
              YES│            │NO
                 ▼            ▼
   ┌─────────────────┐       Regenerate
   │ hash matches    │
   │ current sources?│
   └────────┬────────┘
           NO        YES
            │         │
            ▼         ▼
       Regenerate    expiresAt
                      in the future?
                      ─────────────
                      NO        YES
                       │         │
                       ▼         ▼
                  Regenerate   Reuse
```

Key properties:

- **`ContextPacket.hash`** is the md5 of `(sources, md5 per source)`.
  Changes the moment any source byte changes.
- **`ContextPacket.expiresAt`** = `generatedAt + ttl` (default 5 minutes).
- **`force: true`** bypasses cache for explicit refreshes.
- **`clock` is injectable** so tests can simulate TTL expiry.

The packet body is a full markdown dump of `ProjectConfig`: project,
architecture (layers + boundaries + wiring), state management, routing,
theme, testing, coverage, ticket source, design source, MR policy,
pipeline ops, analyzers. Skills consume the same bytes.

## Consequences

**Positive:**

- A pipeline run with 5 consecutive LLM calls inside the TTL window
  pays the cold cost once and 4 cache hits. Cost reduction in the
  40-60% range for full-pipeline runs.
- Cache invalidation is content-driven, not mtime-driven — touching
  `.alea.yaml` with no changes is a no-op.
- The packet's render() is round-trippeable via
  `ContextPacket.parse(raw)`. Cached packets aren't binary blobs;
  they're inspectable markdown.

**Negative:**

- For runs that only invoke ONE skill, the cache is unused. The cost
  of building the packet is small (~10ms) — acceptable.
- TTL of 5 minutes is fixed to Anthropic's cache. If Anthropic changes
  it, consumers can override via `--ttl-minutes`.

## References

- `lib/src/contracts/context_packet.dart`.
- `lib/src/core/context/context_packet_builder.dart`.
- 19 tests covering round-trip, hash sensitivity, TTL, force,
  in-memory mode, missing config, journal events.
