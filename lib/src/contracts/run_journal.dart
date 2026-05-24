// ALEA — Run Journal contract.
//
// Append-only event log scoped to a single pipeline run. Analyzers, adapters
// and orchestration code emit [JournalEvent]s; downstream tooling (gate
// reports, post-mortem skills, cost-tracking dashboards) reads them back.
//
// Design notes:
//   - This contract is meant to be cheap to call: a `null` journal in the
//     [AnalyzerContext] short-circuits via `ctx.journal?.record(...)`.
//   - The journal is the SAME contract whether the run is one analyzer or the
//     full pipeline. There is no separate "session" type — a run is whatever
//     the journal's owner says it is.
//   - PII redaction is the responsibility of the implementation, not the
//     caller. Callers may pass raw payloads; the journal must scrub them
//     before they hit any durable storage. `NullRunJournal` does not need
//     to redact (no storage).

import 'dart:async';

/// What kind of event is being recorded.
///
/// Conventions:
///   - `started`   — a unit of work began.
///   - `completed` — a unit of work finished successfully.
///   - `warning`   — non-blocking abnormal condition.
///   - `error`     — blocking abnormal condition (the unit aborted).
///   - `check`     — a determinate verification ran; payload usually carries
///                   `verdict`, counts, scores, or threshold deltas.
enum JournalEventKind { started, completed, warning, error, check }

/// A single event in the journal.
///
/// Immutable by convention — implementations of [RunJournal] must not mutate
/// events after they are recorded. [payload] should contain only JSON-safe
/// primitives (String, num, bool, null, List, `Map<String,Object?>`) so the
/// JSONL line round-trips cleanly.
class JournalEvent {
  /// When the event was created. Implementations may overwrite this with the
  /// server-side clock if they care about monotonicity; default is "client
  /// clock at construction time".
  final DateTime timestamp;

  /// Stable identifier of who emitted the event.
  ///
  /// Convention: `<role>:<name>`. Examples:
  ///   - `analyzer:layer_integrity`
  ///   - `resolver:palette`
  ///   - `adapter:ticket_source:asana`
  ///   - `command:run_gates`
  final String source;

  final JournalEventKind kind;

  /// Free-form, JSON-serializable payload. Implementations sanitize strings
  /// for PII before writing — callers may pass raw values without redacting.
  final Map<String, Object?> payload;

  /// Optional id that links several events that belong to the same logical
  /// operation (e.g. the `started`/`completed` pair of one analyzer run).
  final String? correlationId;

  JournalEvent({
    DateTime? timestamp,
    required this.source,
    required this.kind,
    this.payload = const {},
    this.correlationId,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  Map<String, Object?> toJson() => {
    'ts': timestamp.toUtc().toIso8601String(),
    'source': source,
    'kind': kind.name,
    if (correlationId != null) 'correlation_id': correlationId,
    if (payload.isNotEmpty) 'payload': payload,
  };

  /// Parse from a JSON map produced by [toJson]. Used by [RunJournal.readAll].
  ///
  /// Throws [FormatException] when required fields are missing or have the
  /// wrong type. Unknown fields are ignored (forward-compat).
  static JournalEvent fromJson(Map<String, Object?> json) {
    final ts = json['ts'];
    final source = json['source'];
    final kindRaw = json['kind'];
    if (ts is! String || source is! String || kindRaw is! String) {
      throw const FormatException(
        'JournalEvent.fromJson: ts/source/kind are required strings',
      );
    }
    final kind = JournalEventKind.values.firstWhere(
      (k) => k.name == kindRaw,
      orElse: () => throw FormatException(
        'JournalEvent.fromJson: unknown kind "$kindRaw"',
      ),
    );
    final payloadRaw = json['payload'];
    final correlation = json['correlation_id'];
    return JournalEvent(
      timestamp: DateTime.parse(ts),
      source: source,
      kind: kind,
      payload: payloadRaw is Map<String, Object?>
          ? Map<String, Object?>.from(payloadRaw)
          : const {},
      correlationId: correlation is String ? correlation : null,
    );
  }
}

/// Append-only event journal for one pipeline run.
///
/// Implementations are responsible for:
///   1. Serializing concurrent [record] calls so the underlying medium never
///      sees interleaved bytes.
///   2. Redacting PII (MX patterns: CURP, RFC, CLABE, card, phone, email)
///      from string values inside [JournalEvent.payload] before persisting.
///   3. Closing cleanly on [close]; [record] after [close] must throw
///      [StateError].
///
/// Implementations are NOT responsible for any kind of ordering across
/// processes — there is exactly one writer per journal instance.
abstract interface class RunJournal {
  Future<void> record(JournalEvent event);

  /// Replay every event ever recorded into this journal, in the order they
  /// were written.
  Stream<JournalEvent> readAll();

  Future<void> close();
}
