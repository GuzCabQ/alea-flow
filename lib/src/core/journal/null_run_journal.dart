// ALEA — NullRunJournal.
//
// No-op journal used as the default in tests and in any AnalyzerContext that
// does not need observability. Every method is fast, side-effect-free, and
// never throws.

import '../../contracts/run_journal.dart';

class NullRunJournal implements RunJournal {
  const NullRunJournal();

  static const RunJournal instance = NullRunJournal();

  @override
  Future<void> record(JournalEvent event) async {
    // intentionally empty
  }

  @override
  Stream<JournalEvent> readAll() async* {
    // emits nothing
  }

  @override
  Future<void> close() async {
    // intentionally empty
  }
}
