// ALEA — CodeGenOrchestrator.
//
// Glues the three independently-tested scaffolding services together into
// the canonical code-gen flow:
//
//     adapter.generate(request)
//         │
//         ▼
//     ScaffoldPlan
//         │
//         ▼
//     executor.apply(plan)
//         │
//         ▼
//     verifier.verify(outcomes)
//         │
//   ┌─────┴─────┐
//   passed     failed
//   │            │
//   │      executor.rollback(outcomes)
//   ▼            ▼
//   CodeGenRunResult{success=true|false, rolledBack=true|false}
//
// Adapters are not aware of executor / verifier / rollback — they only
// emit a plan. This keeps the adapter surface trivial: a function from
// `(request)` to `ScaffoldPlan`.

import 'dart:async';

import '../contracts/code_gen_adapter.dart';
import '../contracts/run_journal.dart';
import '../contracts/scaffolding.dart';
import 'scaffold_executor.dart';
import 'scaffold_verifier.dart';

class CodeGenOrchestrator {
  final RunJournal? journal;

  CodeGenOrchestrator({this.journal});

  Future<CodeGenRunResult> run({
    required CodeGenAdapter adapter,
    required CodeGenRequest request,
  }) async {
    await journal?.record(
      JournalEvent(
        source: 'orchestrator:code_gen',
        kind: JournalEventKind.started,
        payload: {'adapter': adapter.name, 'layer': request.layer.name},
      ),
    );

    final plan = await adapter.generate(request);

    final executor = ScaffoldExecutor(
      projectRoot: request.projectRoot,
      journal: journal,
    );
    final outcomes = await executor.apply(plan);

    final verifier = ScaffoldVerifier(
      config: request.config,
      projectRoot: request.projectRoot,
      journal: journal,
    );
    final verification = await verifier.verify(
      outcomes,
      runDirectory: request.runDirectory,
    );

    if (!verification.passed) {
      final rolled = await executor.rollback(outcomes);
      await journal?.record(
        JournalEvent(
          source: 'orchestrator:code_gen',
          kind: JournalEventKind.error,
          payload: {
            'adapter': adapter.name,
            'issues': verification.issues.length,
          },
        ),
      );
      return CodeGenRunResult(
        plan: plan,
        outcomes: rolled,
        verification: ScaffoldVerification(
          passed: false,
          issues: verification.issues,
          rolledBack: true,
          elapsed: verification.elapsed,
        ),
      );
    }

    await journal?.record(
      JournalEvent(
        source: 'orchestrator:code_gen',
        kind: JournalEventKind.completed,
        payload: {'adapter': adapter.name, 'files': outcomes.length},
      ),
    );

    return CodeGenRunResult(
      plan: plan,
      outcomes: outcomes,
      verification: verification,
    );
  }
}
