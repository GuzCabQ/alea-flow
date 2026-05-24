// Lightweight in-memory DesignTokenCatalog used by resolver tests. Lets us
// control exactly which tokens are returned without spinning up the Dart
// or JSON adapters.

import 'package:alea_flow/alea_flow.dart';

class FakeTokenCatalog implements DesignTokenCatalog {
  FakeTokenCatalog({
    this.id = 'fake',
    this.colorList = const [],
    this.typographyList = const [],
    this.spacingList = const [],
    this.customMap = const {},
  });

  final String id;
  final List<ColorToken> colorList;
  final List<TypographyToken> typographyList;
  final List<SpacingToken> spacingList;
  final Map<String, List<NamedToken>> customMap;

  @override
  String get sourceId => id;

  @override
  Future<List<ColorToken>> colors() async => colorList;

  @override
  Future<List<TypographyToken>> typography() async => typographyList;

  @override
  Future<List<SpacingToken>> spacing() async => spacingList;

  @override
  Future<List<NamedToken>> custom(String family) async =>
      customMap[family] ?? const [];
}
