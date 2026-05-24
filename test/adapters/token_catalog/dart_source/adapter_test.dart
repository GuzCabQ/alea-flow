// Tests for DartSourceTokenCatalogAdapter.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:alea_flow/src/adapters/token_catalog/dart_source/adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DartSourceTokenCatalogAdapter — colors', () {
    late String fixturesRoot;

    setUp(() {
      fixturesRoot = p.normalize(
        p.join(
          Directory.current.path,
          'test/adapters/token_catalog/dart_source/fixtures',
        ),
      );
    });

    test('returns exactly the 5 declared StyleColors entries', () async {
      final adapter = DartSourceTokenCatalogAdapter(
        absoluteSourcePath: p.join(fixturesRoot, 'sample_app'),
      );
      final tokens = await adapter.colors();
      final names = tokens.map((t) => t.qualifiedName).toSet();
      expect(names, hasLength(5));
      expect(names, {
        'StyleColors.brand60',
        'StyleColors.brand40',
        'StyleColors.brand20',
        'StyleColors.secondary',
        'StyleColors.overlay',
      });
    });

    test('extracts ARGB from `Color(0xFFRRGGBB)` literal form', () async {
      final adapter = DartSourceTokenCatalogAdapter(
        absoluteSourcePath: p.join(fixturesRoot, 'sample_app'),
      );
      final tokens = await adapter.colors();
      final brand60 = tokens.firstWhere(
        (t) => t.qualifiedName == 'StyleColors.brand60',
      );
      expect(brand60.argb, 0xFFDA1884);
      expect(brand60.hex, '#DA1884');
    });

    test('extracts ARGB from `Color.fromARGB(a, r, g, b)` form', () async {
      final adapter = DartSourceTokenCatalogAdapter(
        absoluteSourcePath: p.join(fixturesRoot, 'sample_app'),
      );
      final tokens = await adapter.colors();
      final overlay = tokens.firstWhere(
        (t) => t.qualifiedName == 'StyleColors.overlay',
      );
      expect(overlay.argb, 0x80000000);
      expect(overlay.alpha, 0x80);
    });

    test(
      'skips alias fields whose initializer is not a Color literal',
      () async {
        final adapter = DartSourceTokenCatalogAdapter(
          absoluteSourcePath: p.join(fixturesRoot, 'sample_app'),
        );
        final tokens = await adapter.colors();
        expect(
          tokens.map((t) => t.qualifiedName),
          isNot(contains('StyleColors.brand60Alias')),
        );
      },
    );

    test('respects custom color_class via conventions', () async {
      final adapter = DartSourceTokenCatalogAdapter.fromConventions(
        absoluteSourcePath: p.join(fixturesRoot, 'synthetic_palette'),
        conventions: const {'color_class': 'Palette'},
      );
      final tokens = await adapter.colors();
      expect(tokens.map((t) => t.qualifiedName).toSet(), {
        'Palette.primary',
        'Palette.onPrimary',
        'Palette.background',
      });
      // The IgnoredColors class must NOT contribute tokens.
      expect(
        tokens.any((t) => t.qualifiedName.startsWith('IgnoredColors.')),
        isFalse,
      );
    });

    test('returns empty list when no matching class is found', () async {
      final adapter = DartSourceTokenCatalogAdapter(
        absoluteSourcePath: p.join(fixturesRoot, 'empty'),
      );
      final tokens = await adapter.colors();
      expect(tokens, isEmpty);
    });

    test(
      'throws DesignTokenCatalogException when source does not exist',
      () async {
        final adapter = DartSourceTokenCatalogAdapter(
          absoluteSourcePath: p.join(fixturesRoot, 'does_not_exist'),
        );
        await expectLater(
          adapter.colors(),
          throwsA(isA<DesignTokenCatalogException>()),
        );
      },
    );

    test('works on a single .dart file (not just directories)', () async {
      final adapter = DartSourceTokenCatalogAdapter(
        absoluteSourcePath: p.join(
          fixturesRoot,
          'sample_app',
          'style_colors.dart',
        ),
      );
      final tokens = await adapter.colors();
      expect(tokens, hasLength(5));
    });
  });

  group('DartSourceTokenCatalogAdapter — non-color families (Phase 2)', () {
    test('typography returns empty when typography_class is null', () async {
      final adapter = DartSourceTokenCatalogAdapter(
        absoluteSourcePath: Directory.systemTemp.path,
      );
      expect(await adapter.typography(), isEmpty);
    });

    test('spacing returns empty when spacing_class is null', () async {
      final adapter = DartSourceTokenCatalogAdapter(
        absoluteSourcePath: Directory.systemTemp.path,
      );
      expect(await adapter.spacing(), isEmpty);
    });

    test('custom returns empty when custom_class is null', () async {
      final adapter = DartSourceTokenCatalogAdapter(
        absoluteSourcePath: Directory.systemTemp.path,
      );
      expect(await adapter.custom('radii'), isEmpty);
    });
  });

  test('sourceId is "dart_source"', () {
    final adapter = DartSourceTokenCatalogAdapter(
      absoluteSourcePath: Directory.systemTemp.path,
    );
    expect(adapter.sourceId, 'dart_source');
  });
}
