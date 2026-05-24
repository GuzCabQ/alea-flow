// ALEA — JsonTokenCatalogAdapter.
//
// Reads design tokens from a JSON file. The expected shape is the Style
// Dictionary convention: a tree of nested maps where every leaf carries a
// `value` field, plus optional `type` and free-form metadata.
//
// Example input:
//
//   {
//     "color": {
//       "brand": {
//         "primary":   { "value": "#0066CC",    "type": "color" },
//         "secondary": { "value": "#E0F5F5",    "type": "color" }
//       }
//     },
//     "typography": {
//       "body": {
//         "value": { "fontSize": 16, "fontWeight": 400 },
//         "type": "typography"
//       }
//     },
//     "spacing": {
//       "gutter": { "value": "16px", "type": "spacing" }
//     }
//   }
//
// The adapter recognizes a token by either:
//   1. An explicit `type` field whose value is `color | typography | spacing`.
//   2. The root family (`color`, `typography`, `spacing`) when `type` is
//      absent — Style Dictionary convention.
//
// `qualifiedName` is the dotted path from root to leaf: `color.brand.primary`.

import 'dart:convert';
import 'dart:io';

import '../../../contracts/design_token_catalog.dart';

class JsonTokenCatalogAdapter implements DesignTokenCatalog {
  /// Absolute path to the JSON file.
  final String absoluteSourcePath;

  /// Root keys that map to each token family. Defaults mirror the Style
  /// Dictionary convention. Consumers can override via the `conventions`
  /// block of `theme.token_catalog`:
  ///
  ///   token_catalog:
  ///     adapter: json
  ///     source: tokens/design-tokens.json
  ///     conventions:
  ///       color_root: palette       # instead of "color"
  ///       typography_root: text
  ///       spacing_root: dimensions
  final String colorRoot;
  final String typographyRoot;
  final String spacingRoot;

  JsonTokenCatalogAdapter({
    required this.absoluteSourcePath,
    this.colorRoot = 'color',
    this.typographyRoot = 'typography',
    this.spacingRoot = 'spacing',
  });

  factory JsonTokenCatalogAdapter.fromConventions({
    required String absoluteSourcePath,
    required Map<String, Object?> conventions,
  }) {
    return JsonTokenCatalogAdapter(
      absoluteSourcePath: absoluteSourcePath,
      colorRoot: _stringConvention(conventions, 'color_root') ?? 'color',
      typographyRoot:
          _stringConvention(conventions, 'typography_root') ?? 'typography',
      spacingRoot: _stringConvention(conventions, 'spacing_root') ?? 'spacing',
    );
  }

  @override
  String get sourceId => 'json';

  Map<String, Object?>? _cachedRoot;

  Map<String, Object?> _loadRoot() {
    if (_cachedRoot != null) return _cachedRoot!;
    final file = File(absoluteSourcePath);
    if (!file.existsSync()) {
      throw DesignTokenCatalogException(
        'JSON token file does not exist',
        source: absoluteSourcePath,
      );
    }
    final raw = file.readAsStringSync();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw DesignTokenCatalogException(
        'Top-level of token JSON must be an object',
        source: absoluteSourcePath,
      );
    }
    return _cachedRoot = decoded;
  }

  @override
  Future<List<ColorToken>> colors() async {
    final root = _loadRoot();
    final subtree = root[colorRoot];
    if (subtree is! Map<String, Object?>) return const [];
    final out = <ColorToken>[];
    _walk(subtree, [colorRoot], (qualifiedName, leaf) {
      final type = leaf['type']?.toString();
      if (type != null && type != 'color') return;
      final raw = leaf['value']?.toString();
      if (raw == null) return;
      final argb = _parseHexColor(raw);
      if (argb == null) return;
      out.add(ColorToken(qualifiedName: qualifiedName, argb: argb));
    });
    return List.unmodifiable(out);
  }

  @override
  Future<List<TypographyToken>> typography() async {
    final root = _loadRoot();
    final subtree = root[typographyRoot];
    if (subtree is! Map<String, Object?>) return const [];
    final out = <TypographyToken>[];
    _walk(subtree, [typographyRoot], (qualifiedName, leaf) {
      final type = leaf['type']?.toString();
      if (type != null && type != 'typography') return;
      final value = leaf['value'];
      if (value is! Map<String, Object?>) return;
      final fontSize = _asDouble(value['fontSize']);
      final fontWeight = _asInt(value['fontWeight']);
      if (fontSize == null || fontWeight == null) return;
      out.add(
        TypographyToken(
          qualifiedName: qualifiedName,
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFamily: value['fontFamily']?.toString(),
          decoration: value['decoration']?.toString(),
          letterSpacing: _asDouble(value['letterSpacing']),
          lineHeight: _asDouble(value['lineHeight']),
        ),
      );
    });
    return List.unmodifiable(out);
  }

  @override
  Future<List<SpacingToken>> spacing() async {
    final root = _loadRoot();
    final subtree = root[spacingRoot];
    if (subtree is! Map<String, Object?>) return const [];
    final out = <SpacingToken>[];
    _walk(subtree, [spacingRoot], (qualifiedName, leaf) {
      final type = leaf['type']?.toString();
      if (type != null && type != 'spacing') return;
      final raw = leaf['value'];
      final parsed = _parseSpacing(raw);
      if (parsed == null) return;
      out.add(
        SpacingToken(
          qualifiedName: qualifiedName,
          value: parsed.value,
          unit: parsed.unit,
        ),
      );
    });
    return List.unmodifiable(out);
  }

  @override
  Future<List<NamedToken>> custom(String family) async {
    final root = _loadRoot();
    final subtree = root[family];
    if (subtree is! Map<String, Object?>) return const [];
    final out = <NamedToken>[];
    _walk(subtree, [family], (qualifiedName, leaf) {
      out.add(
        NamedToken(
          qualifiedName: qualifiedName,
          family: family,
          value: leaf['value'],
        ),
      );
    });
    return List.unmodifiable(out);
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// Visit every leaf of [node] (a leaf is a map that contains a `value`
  /// key). [path] is the dotted prefix used to build the qualifiedName.
  void _walk(
    Map<String, Object?> node,
    List<String> path,
    void Function(String qualifiedName, Map<String, Object?> leaf) onLeaf,
  ) {
    if (node.containsKey('value')) {
      onLeaf(path.join('.'), node);
      return;
    }
    for (final entry in node.entries) {
      final v = entry.value;
      if (v is Map<String, Object?>) {
        _walk(v, [...path, entry.key], onLeaf);
      }
    }
  }

  /// Parse `#RGB`, `#RGBA`, `#RRGGBB`, `#AARRGGBB`. Returns null for any
  /// other form.
  int? _parseHexColor(String raw) {
    var s = raw.trim();
    if (!s.startsWith('#')) return null;
    s = s.substring(1).toUpperCase();
    String expanded;
    switch (s.length) {
      case 3: // #RGB → #FFRRGGBB
        expanded = 'FF${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
        break;
      case 4: // #RGBA → #AARRGGBB (Style Dictionary uses #RGBA convention)
        expanded = '${s[3]}${s[3]}${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
        break;
      case 6: // #RRGGBB → #FFRRGGBB
        expanded = 'FF$s';
        break;
      case 8: // #AARRGGBB
        expanded = s;
        break;
      default:
        return null;
    }
    return int.tryParse(expanded, radix: 16);
  }

  /// Parse `"16px"`, `"5%"`, `8` (numeric) into a (value, unit) pair.
  _ParsedSpacing? _parseSpacing(Object? raw) {
    if (raw is num) return _ParsedSpacing(raw.toDouble(), 'px');
    if (raw is! String) return null;
    final match = RegExp(
      r'^([+-]?\d+(?:\.\d+)?)\s*([a-zA-Z%]+)?$',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final amount = double.tryParse(match.group(1)!);
    if (amount == null) return null;
    final unit = match.group(2) ?? 'px';
    return _ParsedSpacing(amount, unit);
  }

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static String? _stringConvention(
    Map<String, Object?> conventions,
    String key,
  ) {
    final v = conventions[key];
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }
}

class _ParsedSpacing {
  final double value;
  final String unit;
  const _ParsedSpacing(this.value, this.unit);
}
