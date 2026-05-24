// ALEA — Design Token Catalog contract.
//
// Abstraction over a consumer project's design system. The catalog returns
// canonical, transport-neutral token objects regardless of where the source
// of truth lives: Dart source (StyleColors-like classes), JSON (Style
// Dictionary), YAML, an external API. Token resolvers (Phase 3) consume the
// catalog without knowing which adapter produced it.
//
// Design notes:
//   - The sealed [DesignToken] hierarchy intentionally keeps the surface
//     small: color, typography, spacing, custom. Resolver code switches on
//     the type — adding a new sub-type is a deliberate, contract-level event.
//   - Token identity is captured in [qualifiedName], a stable string the
//     consumer recognizes (e.g. "StyleColors.brand60", "palette.brand.primary",
//     "color.background.surface"). ALEA never parses it; it propagates it to
//     reports and journal events so consumers can map issues back to their
//     own design system.
//   - All catalog methods are async because some adapters do real I/O (file
//     reads, HTTP). In-memory adapters return immediately resolved futures.
//   - [sourceId] is a stable identifier of the adapter that produced the
//     catalog ("dart_source", "json", ...) used in journal events and gate
//     reports for observability.

import 'dart:async';

/// Base of every token returned by a [DesignTokenCatalog].
///
/// Sealed: callers can exhaustively switch on the sub-type, and adding a new
/// kind of token is a contract-level change that ripples through resolvers.
sealed class DesignToken {
  /// Fully-qualified name in the consumer's own convention. Opaque to ALEA.
  final String qualifiedName;

  /// Adapter-specific hints (deprecation flags, WCAG ratings, etc.). Always
  /// JSON-safe so the token round-trips through the run journal.
  final Map<String, Object?> meta;

  const DesignToken({required this.qualifiedName, this.meta = const {}});
}

/// A color token expressed as 32-bit ARGB.
final class ColorToken extends DesignToken {
  /// Canonical color in 0xAARRGGBB.
  final int argb;

  const ColorToken({
    required super.qualifiedName,
    required this.argb,
    super.meta,
  });

  int get alpha => (argb >> 24) & 0xFF;
  int get red => (argb >> 16) & 0xFF;
  int get green => (argb >> 8) & 0xFF;
  int get blue => argb & 0xFF;

  /// Convenience hex form for human-readable reports.
  /// Returns `#AARRGGBB` (or `#RRGGBB` if alpha is fully opaque).
  String get hex {
    final r = red.toRadixString(16).padLeft(2, '0').toUpperCase();
    final g = green.toRadixString(16).padLeft(2, '0').toUpperCase();
    final b = blue.toRadixString(16).padLeft(2, '0').toUpperCase();
    if (alpha == 0xFF) return '#$r$g$b';
    final a = alpha.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#$a$r$g$b';
  }
}

/// A typography token capturing the dimensions resolvers compare against.
///
/// Optional dimensions ([fontFamily], [decoration], [letterSpacing],
/// [lineHeight]) are nullable: the catalog reports only what its source
/// declares. The resolver decides which dimensions to use as hard filters
/// (typically family + weight) and which as soft hints (decoration, spacing).
final class TypographyToken extends DesignToken {
  /// Font size in logical pixels.
  final double fontSize;

  /// Numeric font weight (100..900).
  final int fontWeight;

  final String? fontFamily;

  /// Adapter-normalized decoration: 'none', 'underline', 'line-through',
  /// 'overline'. Null when the source does not declare one.
  final String? decoration;

  final double? letterSpacing;
  final double? lineHeight;

  const TypographyToken({
    required super.qualifiedName,
    required this.fontSize,
    required this.fontWeight,
    this.fontFamily,
    this.decoration,
    this.letterSpacing,
    this.lineHeight,
    super.meta,
  });
}

/// A spacing/sizing token.
///
/// [unit] is a free-form short string ('px', 'pt', 'em', '%', 'dp', ...). It
/// is the consumer's responsibility to declare a consistent unit per token;
/// the layout-metric resolver (Phase 3) reads [unit] to decide how to compare.
final class SpacingToken extends DesignToken {
  final double value;
  final String unit;

  const SpacingToken({
    required super.qualifiedName,
    required this.value,
    this.unit = 'px',
    super.meta,
  });
}

/// A token of a family ALEA does not model natively (radii, shadows, motion
/// curves, etc.). Resolvers built for these families consume [value] directly.
final class NamedToken extends DesignToken {
  /// JSON-safe value: String, num, bool, null, List, or `Map<String,Object?>`.
  final Object? value;

  /// Family name passed to [DesignTokenCatalog.custom] when this token was
  /// produced. Resolvers use this to discriminate when one catalog yields
  /// multiple custom families.
  final String family;

  const NamedToken({
    required super.qualifiedName,
    required this.family,
    this.value,
    super.meta,
  });
}

/// Source of a consumer's design tokens.
///
/// Implementations must be idempotent: calling [colors] (or any family
/// method) twice with no underlying source change must return tokens that
/// compare equal field-by-field. Implementations may cache internally; ALEA
/// does not require fresh I/O on every call.
abstract interface class DesignTokenCatalog {
  /// Stable adapter identifier — emitted in journal events.
  String get sourceId;

  Future<List<ColorToken>> colors();
  Future<List<TypographyToken>> typography();
  Future<List<SpacingToken>> spacing();

  /// Tokens of a free-form family (e.g. `radii`, `shadows`).
  ///
  /// Adapters that do not model the requested family return an empty list.
  /// Resolvers MUST tolerate an empty result.
  Future<List<NamedToken>> custom(String family);
}

/// Thrown by adapters when the configured source cannot be read or is
/// structurally invalid. Distinguishes catalog errors from ProjectConfig
/// errors (which throw [ProjectConfigException] in the config loader).
class DesignTokenCatalogException implements Exception {
  final String message;
  final String? source;
  const DesignTokenCatalogException(this.message, {this.source});

  @override
  String toString() =>
      'DesignTokenCatalogException(${source != null ? 'source=$source, ' : ''}'
      'message=$message)';
}
