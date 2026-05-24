# ADR-0002 — Run Journal: append-only JSONL with mandatory PII redaction

- **Status:** Accepted
- **Date:** 2026-05-23
- **Phase:** 1

## Context

The pre-redesign tooling (HORUS) printed observability data to `stdout`
with no structure, no level, and no persistence. Debugging a stuck run
required re-running the command with a different verbosity flag — and
sensitive Mexican-context PII (CURP, RFC, CLABE, card, phone, email)
could leak into operator terminals or CI logs.

ALEA needs:

1. Structured events that downstream tools can read mechanically.
2. Persistence per run so a post-mortem can reconstruct what happened.
3. Concurrency safety — multiple analyzers run in parallel.
4. **Mandatory** PII redaction at the journal boundary; callers should
   not have to remember to scrub.

## Decision

A new contract `RunJournal` (`lib/src/contracts/run_journal.dart`) with a
single `record(event)` method. The default implementation
`JsonlRunJournal` (`lib/src/core/journal/jsonl_run_journal.dart`) writes
to `.pipeline/runs/<id>/journal.jsonl` as append-only newline-delimited
JSON.

Key properties:

- **Concurrency**: writes are serialized through a `Future` chain so
  parallel `record()` calls produce well-formed JSONL.
- **PII**: `pii_redactor.dart` rewrites string leaves of `payload`
  through a fixed pattern catalog (CURP, RFC, CLABE, card, phone,
  email). Redactions are counted and stored in a `_pii_redactions`
  sub-map for auditability.
- **NullRunJournal** is a `const` singleton used in tests and ad-hoc
  invocations — callers always have somewhere to send events.

`AnalyzerContext` gained an optional `journal` field;
`AnalyzerRunner.run({journal})` ferries it through. Analyzers emit via
`ctx.journal?.record(...)` — null-safe so existing tests are unaffected.

## Consequences

**Positive:**

- Every analyzer, adapter, and orchestrator can emit structured events
  without arguing about a logging library.
- PII redaction lives in one file; callers cannot accidentally bypass it
  by formatting strings their own way.
- `JsonlRunJournal` is replayable — running `aflow journal --format jsonl`
  re-emits the original events for downstream tools.

**Negative:**

- One extra file per run on disk. Negligible in practice; cleaning the
  `.pipeline/runs/` tree handles it.
- PII patterns are a moving target; the regex catalog will need
  periodic review.

## References

- `lib/src/contracts/run_journal.dart` — contract.
- `lib/src/core/journal/jsonl_run_journal.dart` — default impl.
- `lib/src/core/journal/null_run_journal.dart` — no-op for tests.
- `lib/src/core/journal/pii_redactor.dart` — pattern catalog.
- `test/core/journal/` — 17 tests (round-trip, concurrency, PII, lifecycle).
