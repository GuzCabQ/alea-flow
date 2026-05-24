// ALEA — Ticket source adapter contract.
//
// Every folder under alea/adapters/ticket_source/<name>/ implements [TicketSourceAdapter].
// Selected at runtime via `ticket_source.adapter` in `.alea.yaml`.

import 'project_config.dart';

/// What `core/commands/analyze-ticket` hands to the adapter.
///
/// Either [ticketId] (e.g. `DEV-1234`) OR [filePath] (e.g. `./tickets/DEV-1234.md`)
/// is set. The adapter inspects which to use; `file/` is the only adapter that
/// requires [filePath].
class TicketRef {
  final String? ticketId;
  final String? filePath;

  const TicketRef({this.ticketId, this.filePath})
    : assert(
        ticketId != null || filePath != null,
        'TicketRef requires either ticketId or filePath',
      );
}

/// Raw, untyped ticket payload returned by the adapter.
///
/// Adapter responsibilities stop here: the payload is parsed by
/// `core/commands/analyze-ticket` into the canonical `analysis.json`
/// (per `contracts/schemas/analysis.schema.yaml`). PII sanitization
/// happens in core, not in the adapter — so adapters never see the
/// raw secrets after the first read.
typedef RawTicketPayload = Map<String, Object?>;

/// Base contract for every ticket-source adapter.
abstract class TicketSourceAdapter {
  /// Stable, snake_case name (`asana`, `linear`, `file`, `jira`).
  /// Matches the folder name under `alea/adapters/ticket_source/<name>/`.
  String get name;

  /// True when this adapter can handle [ref]. Used by `core/commands/analyze-ticket`
  /// when the consumer config allows fallbacks (e.g. `file/` always supports
  /// [TicketRef.filePath] != null).
  bool supports(TicketRef ref, ProjectConfig config);

  /// Fetch the raw ticket. Throws [TicketFetchException] on transport or auth failure.
  Future<RawTicketPayload> fetch(TicketRef ref, ProjectConfig config);
}

class TicketFetchException implements Exception {
  final String adapter;
  final TicketRef ref;
  final String reason;

  const TicketFetchException(this.adapter, this.ref, this.reason);

  @override
  String toString() =>
      'TicketFetchException(adapter=$adapter, ref=$ref, reason=$reason)';
}
