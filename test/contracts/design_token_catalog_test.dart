// Tests for the DesignTokenCatalog contract types.
//
// Pure data-class tests — verify accessors, formatting, exhaustiveness.

import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

void main() {
  group('ColorToken', () {
    test('decomposes ARGB into alpha/red/green/blue', () {
      const t = ColorToken(
        qualifiedName: 'StyleColors.brand60',
        argb: 0xFFDA1884,
      );
      expect(t.alpha, 0xFF);
      expect(t.red, 0xDA);
      expect(t.green, 0x18);
      expect(t.blue, 0x84);
    });

    test('hex omits alpha when fully opaque', () {
      const t = ColorToken(
        qualifiedName: 'StyleColors.brand60',
        argb: 0xFFDA1884,
      );
      expect(t.hex, '#DA1884');
    });

    test('hex preserves alpha when partially transparent', () {
      const t = ColorToken(
        qualifiedName: 'StyleColors.overlay',
        argb: 0x80000000,
      );
      expect(t.hex, '#80000000');
    });

    test('preserves opaque qualifiedName regardless of value', () {
      const t = ColorToken(
        qualifiedName: 'palette.background.surface',
        argb: 0xFFF5F5F5,
      );
      expect(t.qualifiedName, 'palette.background.surface');
    });
  });

  group('TypographyToken', () {
    test('captures required dimensions', () {
      const t = TypographyToken(
        qualifiedName: 'StyleFonts.body2',
        fontSize: 16,
        fontWeight: 600,
        fontFamily: 'DM Sans',
      );
      expect(t.fontSize, 16);
      expect(t.fontWeight, 600);
      expect(t.fontFamily, 'DM Sans');
    });

    test('leaves optional dimensions null by default', () {
      const t = TypographyToken(
        qualifiedName: 'StyleFonts.caption',
        fontSize: 12,
        fontWeight: 400,
      );
      expect(t.fontFamily, isNull);
      expect(t.decoration, isNull);
      expect(t.letterSpacing, isNull);
      expect(t.lineHeight, isNull);
    });
  });

  group('SpacingToken', () {
    test('default unit is px', () {
      const t = SpacingToken(qualifiedName: 'spacing.s8', value: 8);
      expect(t.value, 8);
      expect(t.unit, 'px');
    });

    test('custom unit is preserved', () {
      const t = SpacingToken(
        qualifiedName: 'layout.gutter',
        value: 5,
        unit: '%',
      );
      expect(t.unit, '%');
    });
  });

  group('NamedToken', () {
    test('carries family and value', () {
      const t = NamedToken(
        qualifiedName: 'radii.medium',
        family: 'radii',
        value: 12,
      );
      expect(t.family, 'radii');
      expect(t.value, 12);
    });
  });

  group('exhaustive switch on DesignToken', () {
    test('compiler enforces every case', () {
      // This test is intentionally a static-check vehicle: the switch must be
      // exhaustive or the package will not compile. Runtime assertions just
      // confirm each branch returns the expected discriminator string.
      String describe(DesignToken t) => switch (t) {
        ColorToken() => 'color',
        TypographyToken() => 'typography',
        SpacingToken() => 'spacing',
        NamedToken() => 'named',
      };
      expect(describe(const ColorToken(qualifiedName: 'x', argb: 0)), 'color');
      expect(
        describe(
          const TypographyToken(
            qualifiedName: 'y',
            fontSize: 12,
            fontWeight: 400,
          ),
        ),
        'typography',
      );
      expect(
        describe(const SpacingToken(qualifiedName: 'z', value: 4)),
        'spacing',
      );
      expect(
        describe(const NamedToken(qualifiedName: 'q', family: 'radii')),
        'named',
      );
    });
  });

  group('DesignTokenCatalogException', () {
    test('toString includes message and optional source', () {
      const e = DesignTokenCatalogException(
        'parse failure',
        source: 'lib/src/theme/colors.dart',
      );
      expect(e.toString(), contains('source=lib/src/theme/colors.dart'));
      expect(e.toString(), contains('message=parse failure'));
    });
  });
}
