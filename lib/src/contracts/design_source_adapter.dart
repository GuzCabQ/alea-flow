// ALEA — Design source adapter contract.
//
// Every folder under alea/adapters/design_source/<name>/ implements [DesignSourceAdapter].
// Selection happens in `design-feature` by walking `analysis.json::attachments[]`
// and asking each enabled adapter `supports(ref, config)` until one matches.
// The contract is intentionally source-agnostic — no field, type, or method
// here names a specific design tool.

import 'project_config.dart';

/// What `core/commands/design-feature` hands to the adapter.
///
/// Intentionally source-agnostic: there is no field that names a specific design
/// tool. The triple (uri, mediaType, adapterHint) is the same shape used by
/// `analysis.json::attachments[*]` — see `contracts/schemas/analysis.schema.yaml`.
///
/// Adapter selection is the job of `design-feature`: it walks `attachments[]`
/// and asks each enabled adapter `supports(ref, config)` until one says yes.
/// Adapters inspect the [uri] pattern, the [mediaType] hint, and the
/// [adapterHint] string (which comes from `attachments[*].description`) to
/// decide.
class DesignRef {
  /// URL or file path. Adapters inspect the value to decide support
  /// (e.g. the figma adapter matches `figma.com/(file|design|proto)/...`).
  final String uri;

  /// Optional MIME type or file extension hint (e.g. `image/png`,
  /// `application/x-figma`, `.html`). Lets adapters short-circuit without
  /// parsing the URI.
  final String? mediaType;

  /// Optional routing hint from `attachments[*].description`. When set, the
  /// adapter whose name matches this string case-insensitively is preferred
  /// over URL-pattern-based selection.
  final String? adapterHint;

  const DesignRef({required this.uri, this.mediaType, this.adapterHint});
}

/// The Normalized Design Spec, as defined by
/// `contracts/schemas/nds.schema.yaml`.
///
/// Kept as an opaque map at the Dart-contract boundary because the YAML schema
/// is the source of truth and binding it to a strongly-typed Dart class would
/// duplicate the contract surface. Adapter implementations may use their own
/// internal types and serialize to this shape at the boundary.
typedef NDSDocument = Map<String, Object?>;

/// What the adapter writes to disk under `.pipeline/runs/<id>/<source>/`.
class DesignExtractionResult {
  /// The NDS YAML content. Must validate against `contracts/schemas/nds.schema.yaml`.
  final NDSDocument nds;

  /// Per-element decisions of USE_AS_IS / ADAPT / CREATE_NEW against the
  /// consumer project's widget catalog. Shape matches
  /// `adapters/design_source/_common/widget-audit.md`.
  final Map<String, Object?> widgetMap;

  /// Per-element color → theme-token mapping. Shape matches
  /// `adapters/design_source/_common/theme-map.md`.
  final Map<String, Object?> colorMap;

  /// Subdirectory under `.pipeline/runs/<id>/` where the adapter wrote its
  /// artifacts (e.g. `figma`, `image`, `markup`). Used by `design-feature` to
  /// record `nds_ref` in `spec.json`.
  final String runSubdirectory;

  const DesignExtractionResult({
    required this.nds,
    required this.widgetMap,
    required this.colorMap,
    required this.runSubdirectory,
  });
}

/// Base contract for every design-source adapter.
abstract class DesignSourceAdapter {
  /// Stable, snake_case name (`figma`, `image`, `markup`, `penpot`, ...).
  /// Matches the folder name under `alea/adapters/design_source/<name>/`.
  String get name;

  /// True when this adapter can handle [ref].
  bool supports(DesignRef ref, ProjectConfig config);

  /// Extract NDS + widget map + color map from the design source.
  ///
  /// Throws [DesignExtractionException] when the source is unreachable, the
  /// consumer's MCP server is unauthenticated, or extraction produces invalid
  /// NDS that the adapter cannot recover from.
  Future<DesignExtractionResult> extract(DesignRef ref, ProjectConfig config);
}

class DesignExtractionException implements Exception {
  final String adapter;
  final DesignRef ref;
  final String reason;

  const DesignExtractionException(this.adapter, this.ref, this.reason);

  @override
  String toString() =>
      'DesignExtractionException(adapter=$adapter, ref=$ref, reason=$reason)';
}
