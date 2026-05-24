// ALEA — WidgetInventory contract.
//
// A catalog of reusable widget classes discovered in (or imported into) a
// consumer's codebase. Produced by `WidgetInventoryBuilder` (Phase 5) from a
// Dart-source scan; future sources may include Storybook exports or Figma
// Code Connect mappings.
//
// Consumed by:
//   - `ComponentLookup` (`lib/src/resolvers/component_lookup/`) — fuzzy-matches
//     a Figma layer description against the inventory and surfaces the best
//     reusable widget instead of emitting a fresh one.
//   - Skills that need a low-token index of available components.
//
// The contract is intentionally narrow: an iterable of [WidgetEntry] plus a
// lookup by class name. Anything more elaborate (faceted search by category,
// by tokens used, by constructor signature) lives in the consumer or in a
// resolver that wraps the inventory.

import 'dart:async';

/// One widget class registered in the inventory.
class WidgetEntry {
  /// Public class name as declared in source (PascalCase).
  final String className;

  /// Project-relative path to the file that defines [className]. Forward
  /// slashes; no leading `./`.
  final String filePath;

  /// Optional categorization (e.g. `button`, `card`, `input`, `layout`).
  /// Free-form — derived heuristically by the builder, surfaced for human
  /// readability and for resolvers that want to filter by family.
  final String? category;

  /// Design tokens referenced literally in the source — e.g.
  /// `StyleColors.brand60`, `StyleFonts.body2`. Order is irrelevant; the
  /// builder emits them sorted for deterministic output.
  final List<String> tokensUsed;

  /// Rendered primary constructor signature (named or unnamed). Useful for
  /// LLMs that need to instantiate the widget without re-reading its source.
  /// Null when no public constructor exists.
  final String? constructorSignature;

  /// MD5 of the file content at scan time. Changes when the file changes —
  /// callers diff against a previous inventory to detect drift.
  final String md5Hash;

  /// Adapter-specific metadata (extends-clause, docComment hash, etc.).
  /// Always JSON-safe so the entry round-trips through the run journal.
  final Map<String, Object?> meta;

  const WidgetEntry({
    required this.className,
    required this.filePath,
    this.category,
    this.tokensUsed = const [],
    this.constructorSignature,
    required this.md5Hash,
    this.meta = const {},
  });

  Map<String, Object?> toJson() => {
    'class_name': className,
    'file_path': filePath,
    if (category != null) 'category': category,
    if (tokensUsed.isNotEmpty) 'tokens_used': tokensUsed,
    if (constructorSignature != null)
      'constructor_signature': constructorSignature,
    'md5_hash': md5Hash,
    if (meta.isNotEmpty) 'meta': meta,
  };

  static WidgetEntry fromJson(Map<String, Object?> json) {
    return WidgetEntry(
      className: json['class_name'] as String,
      filePath: json['file_path'] as String,
      category: json['category'] as String?,
      tokensUsed:
          (json['tokens_used'] as List?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const [],
      constructorSignature: json['constructor_signature'] as String?,
      md5Hash: json['md5_hash'] as String,
      meta: (json['meta'] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }
}

/// Catalog of [WidgetEntry] items. Implementations may load lazily or eagerly
/// — callers must always await [entries].
abstract interface class WidgetInventory {
  /// Stable identifier of the inventory source ('dart_source', 'storybook',
  /// ...). Emitted in journal events.
  String get sourceId;

  /// Return every entry. Order is implementation-defined but stable across
  /// calls when the underlying source has not changed.
  Future<List<WidgetEntry>> entries();

  /// Return entries whose class name matches [name] exactly. Most inventories
  /// have one entry per class name, but the contract permits multiple (e.g.
  /// when the source is a JSON catalog with explicit duplicates).
  Future<List<WidgetEntry>> byClassName(String name);
}

/// Thrown when an inventory source cannot be loaded or parsed.
class WidgetInventoryException implements Exception {
  final String message;
  final String? source;
  const WidgetInventoryException(this.message, {this.source});

  @override
  String toString() =>
      'WidgetInventoryException(${source != null ? 'source=$source, ' : ''}'
      'message=$message)';
}
