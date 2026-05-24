// ALEA — Scaffolding contracts.
//
// Data types shared by code-gen adapters, the scaffold executor, and the
// scaffold verifier. Pure data — no I/O, no AST, no business logic. The
// runtime behaviour lives in `lib/src/scaffolding/`.
//
// Lifecycle of a code-gen run:
//
//   adapter.generate(request)
//       │
//       ▼
//   ScaffoldPlan (immutable description: files + patches)
//       │
//       ▼
//   ScaffoldExecutor.apply(plan)         ─► writes files, records md5,
//                                          marks each outcome as
//                                          create | modify | skip
//       │
//       ▼
//   ScaffoldVerifier.verify(outcomes)    ─► runs analyzers; if blocked,
//                                          requests rollback
//       │
//       ▼
//   CodeGenResult (plan + outcomes + verification, with rollback applied
//                  when verification failed)

import 'analyzer.dart';

/// What an executor will do (or did) with a single file.
enum ScaffoldAction {
  /// File did not exist; the executor created it.
  create,

  /// File existed; the executor overwrote its content.
  modify,

  /// File existed with identical content (same md5) — executor skipped it.
  skip,

  /// Executor wrote the file, but the verifier asked for a rollback, so the
  /// previous content (if any) was restored.
  rolledBack,
}

/// One file the adapter wants to write (or modify) on disk.
///
/// [relativePath] is project-relative — never absolute, never `..`-escaping.
/// Executors throw [ArgumentError] when given an absolute or escaping path.
class GeneratedFile {
  final String relativePath;
  final String content;

  const GeneratedFile({required this.relativePath, required this.content});
}

/// A surgical patch to an existing file (typically the wiring manifest:
/// `injector.dart`, `routes.dart`, ...).
///
/// Three modes:
///   - `insertAfterAnchor` — locate the first line containing [anchor] and
///     insert [insertion] immediately after it.
///   - `insertBeforeAnchor` — insert [insertion] immediately before the
///     anchor line.
///   - `appendIfMissing` — append [insertion] at the end of the file when
///     [insertion] is not already present anywhere; no-op if present.
///
/// Always idempotent: re-running a patch whose [insertion] is already in
/// the file is a `skip`.
enum WiringPatchMode { insertAfterAnchor, insertBeforeAnchor, appendIfMissing }

class WiringPatch {
  final String relativePath;
  final WiringPatchMode mode;
  final String? anchor;
  final String insertion;

  const WiringPatch({
    required this.relativePath,
    required this.mode,
    this.anchor,
    required this.insertion,
  });
}

/// Immutable description of everything the adapter wants to do. Adapters
/// build this; executors apply it; verifiers re-read it for rollback.
class ScaffoldPlan {
  final List<GeneratedFile> files;
  final List<WiringPatch> patches;

  /// Adapter identifier. Used in journal events and verification reports.
  final String adapterName;

  /// Free-form metadata (feature name, layer, NDS hash, ...). JSON-safe.
  final Map<String, Object?> meta;

  const ScaffoldPlan({
    required this.adapterName,
    this.files = const [],
    this.patches = const [],
    this.meta = const {},
  });
}

/// Outcome of applying one [GeneratedFile] or [WiringPatch].
class ScaffoldOutcome {
  final String relativePath;
  final ScaffoldAction action;

  /// Content present on disk before the executor ran. Null for `create`.
  /// Used by [ScaffoldExecutor.rollback] to restore the previous state.
  final String? previousContent;

  /// md5 of the content present on disk AFTER the executor ran.
  final String newMd5;

  const ScaffoldOutcome({
    required this.relativePath,
    required this.action,
    this.previousContent,
    required this.newMd5,
  });

  /// Returns a new outcome with [action] replaced by [ScaffoldAction.rolledBack].
  /// Used by the executor when rolling back after a failed verification.
  ScaffoldOutcome asRolledBack() => ScaffoldOutcome(
    relativePath: relativePath,
    action: ScaffoldAction.rolledBack,
    previousContent: previousContent,
    newMd5: newMd5,
  );
}

/// Result of post-write verification.
class ScaffoldVerification {
  final bool passed;
  final List<AnalysisIssue> issues;
  final bool rolledBack;
  final Duration elapsed;

  const ScaffoldVerification({
    required this.passed,
    this.issues = const [],
    this.rolledBack = false,
    required this.elapsed,
  });

  Map<String, Object?> toJson() => {
    'passed': passed,
    'rolled_back': rolledBack,
    'elapsed_ms': elapsed.inMilliseconds,
    if (issues.isNotEmpty) 'issues': issues.map((i) => i.toJson()).toList(),
  };
}

/// Top-level result returned by `CodeGenOrchestrator.run`.
class CodeGenRunResult {
  final ScaffoldPlan plan;
  final List<ScaffoldOutcome> outcomes;
  final ScaffoldVerification verification;
  final Map<String, Object?> metrics;

  const CodeGenRunResult({
    required this.plan,
    required this.outcomes,
    required this.verification,
    this.metrics = const {},
  });

  /// True when every outcome was a create/modify (no rollback) AND the
  /// verification passed. Convenience for callers that only care about the
  /// happy path.
  bool get success => verification.passed && !verification.rolledBack;

  Map<String, Object?> toJson() => {
    'adapter': plan.adapterName,
    'outcomes': outcomes
        .map((o) => {'path': o.relativePath, 'action': o.action.name})
        .toList(),
    'verification': verification.toJson(),
    if (metrics.isNotEmpty) 'metrics': metrics,
  };
}

/// Thrown by [ScaffoldExecutor] when a plan is structurally invalid before
/// any I/O happens (absolute paths, escaping `..`, duplicate entries).
class ScaffoldPlanException implements Exception {
  final String message;
  const ScaffoldPlanException(this.message);
  @override
  String toString() => 'ScaffoldPlanException(message=$message)';
}
