// ALEA — Code-gen adapter contract.
//
// Each folder under `lib/src/adapters/code_gen/<name>/` implements
// [CodeGenAdapter]. The adapter's only job is to produce a [ScaffoldPlan]
// — an immutable description of the files and patches that would create
// the requested layer. Actually writing to disk, verifying the result, and
// rolling back on failure are the responsibility of the scaffolding
// services (`lib/src/scaffolding/`), not the adapter.
//
// This separation is what lets the consumer swap `state_management.style`
// from `riverpod_manual` to `bloc` without touching any orchestration
// code: only the adapter changes; the plan it emits flows through the
// same executor, the same verifier, and the same rollback machinery.

import 'design_source_adapter.dart' show NDSDocument;
import 'project_config.dart';
import 'scaffolding.dart';

/// Layers a code-gen adapter knows how to produce.
enum CodeGenLayer { domain, infrastructure, presentation, bugfix }

/// Input to `CodeGenAdapter.generate`.
class CodeGenRequest {
  final CodeGenLayer layer;

  /// Parsed `spec.json`. Adapters read `feature.name`, the NDS reference,
  /// and any layer-specific fields they recognize.
  final Map<String, Object?> spec;

  /// Parsed NDS, when the design phase produced one. Null for bugfix and
  /// for runs with `spec.design_source.status == none|disabled`.
  final NDSDocument? nds;

  /// Project root in the consumer repo. Adapters interpret
  /// `GeneratedFile.relativePath` against this root.
  final String projectRoot;

  /// `.pipeline/runs/<id>/` (optional). Adapters that want to read prior
  /// artifacts or write an implementation report use it; others ignore it.
  final String? runDirectory;

  final ProjectConfig config;

  const CodeGenRequest({
    required this.layer,
    required this.spec,
    this.nds,
    required this.projectRoot,
    this.runDirectory,
    required this.config,
  });
}

/// Adapter contract.
///
/// Adapters MUST:
///   - Respect `architecture.layers.<layer>.paths`: files in the plan must
///     fall inside the configured paths.
///   - Respect `architecture.layers.<layer>.forbid_imports`: the rendered
///     content must not introduce a forbidden import.
///   - Produce deterministic output: the same request must yield the same
///     plan byte-for-byte across runs.
///   - Be agnostic to filesystem state: the adapter does NOT read the
///     current contents of files it intends to write (the executor handles
///     idempotency).
abstract interface class CodeGenAdapter {
  /// Stable snake_case identifier (`riverpod_manual`, `bloc`, `provider`).
  String get name;

  /// True when this adapter can produce a plan for [layer] given [config].
  bool supports(CodeGenLayer layer, ProjectConfig config);

  /// Build the plan. No I/O permitted — the result is a pure transformation
  /// of [request].
  Future<ScaffoldPlan> generate(CodeGenRequest request);
}

/// Thrown by adapters when the request is structurally invalid (missing
/// required spec fields, unsupported layer, etc.).
class CodeGenException implements Exception {
  final String adapter;
  final CodeGenLayer layer;
  final String reason;

  const CodeGenException(this.adapter, this.layer, this.reason);

  @override
  String toString() =>
      'CodeGenException(adapter=$adapter, layer=$layer, reason=$reason)';
}
