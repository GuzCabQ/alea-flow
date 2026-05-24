import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

import '../_fake_catalog.dart';

void main() {
  group('PaletteResolver', () {
    late FakeTokenCatalog catalog;

    setUp(() {
      catalog = FakeTokenCatalog(
        colorList: const [
          ColorToken(qualifiedName: 'palette.brand60', argb: 0xFFDA1884),
          ColorToken(qualifiedName: 'palette.brand40', argb: 0xFF4A0E2B),
          ColorToken(qualifiedName: 'palette.brand20', argb: 0xFFFCEDF6),
          ColorToken(qualifiedName: 'palette.secondary', argb: 0xFFE0F5F5),
          ColorToken(qualifiedName: 'palette.overlay', argb: 0x80000000),
          ColorToken(qualifiedName: 'palette.background', argb: 0xFFF7F8FA),
          ColorToken(qualifiedName: 'palette.text', argb: 0xFF1A1A1A),
          ColorToken(qualifiedName: 'palette.warn', argb: 0xFFE0A800),
          ColorToken(qualifiedName: 'palette.danger', argb: 0xFFE53935),
          ColorToken(qualifiedName: 'palette.success', argb: 0xFF22A06B),
        ],
      );
    });

    test('identical hex → match with confidence 1.0', () async {
      final resolver = PaletteResolver(catalog);
      final result = await resolver.resolve(ColorQuery.fromHex('#DA1884')!);
      expect(result.verdict, ResolutionVerdict.match);
      expect(result.recommended?.qualifiedName, 'palette.brand60');
      expect(result.confidence, closeTo(1.0, 1e-6));
    });

    test('1-step perturbation → match with high confidence', () async {
      final resolver = PaletteResolver(catalog);
      final result = await resolver.resolve(ColorQuery.fromHex('#DB1884')!);
      expect(result.verdict, ResolutionVerdict.match);
      expect(result.recommended?.qualifiedName, 'palette.brand60');
      expect(result.confidence, greaterThan(0.9));
    });

    test('contrasting color in a wide-spread palette → no match', () async {
      final resolver = PaletteResolver(
        catalog,
        maxDelta: 5,
      ); // strict distance budget
      // Pick a hue that sits between several palette entries.
      final result = await resolver.resolve(ColorQuery.fromHex('#7F7F7F')!);
      expect(result.verdict, ResolutionVerdict.noMatch);
    });

    test('empty catalog → no match with explanatory warning', () async {
      final empty = FakeTokenCatalog(colorList: const []);
      final resolver = PaletteResolver(empty);
      final result = await resolver.resolve(ColorQuery.fromHex('#000000')!);
      expect(result.verdict, ResolutionVerdict.noMatch);
      expect(result.warnings, isNotEmpty);
    });

    test('candidates are sorted descending by score', () async {
      final resolver = PaletteResolver(catalog);
      final result = await resolver.resolve(ColorQuery.fromHex('#FF0000')!);
      for (var i = 1; i < result.candidates.length; i++) {
        expect(
          result.candidates[i].score,
          lessThanOrEqualTo(result.candidates[i - 1].score),
        );
      }
    });

    test('candidates truncated to hints.maxCandidates', () async {
      final resolver = PaletteResolver(catalog);
      final result = await resolver.resolve(
        ColorQuery.fromHex('#FF0000')!,
        const ResolverHints(maxCandidates: 2),
      );
      expect(result.candidates, hasLength(2));
    });

    test('rationale annotates each candidate with its ΔE', () async {
      final resolver = PaletteResolver(catalog);
      final result = await resolver.resolve(ColorQuery.fromHex('#DA1884')!);
      expect(result.candidates.first.rationale, contains('ΔE = '));
    });

    test('toJson is JSON-safe and includes verdict + confidence', () async {
      final resolver = PaletteResolver(catalog);
      final result = await resolver.resolve(ColorQuery.fromHex('#DA1884')!);
      final json = result.toJson();
      expect(json['verdict'], 'match');
      expect(json['recommended'], 'palette.brand60');
      expect(json['confidence'], isA<num>());
      expect(json['candidates'], isA<List>());
    });

    test(
      'property: random hex never throws and always yields a verdict',
      () async {
        final resolver = PaletteResolver(catalog);
        var seed = 2026;
        int next() {
          seed = (1103515245 * seed + 12345) & 0x7FFFFFFF;
          return seed;
        }

        for (var i = 0; i < 50; i++) {
          final argb = 0xFF000000 | (next() & 0xFFFFFF);
          final result = await resolver.resolve(ColorQuery(argb));
          expect(
            ResolutionVerdict.values,
            contains(result.verdict),
            reason:
                'verdict for argb=$argb must be one of '
                '${ResolutionVerdict.values}',
          );
          expect(result.confidence, inInclusiveRange(0, 1));
        }
      },
    );
  });

  group('ColorQuery.fromHex', () {
    test('parses #RRGGBB as opaque', () {
      expect(ColorQuery.fromHex('#DA1884')!.argb, 0xFFDA1884);
    });

    test('parses #AARRGGBB preserving alpha', () {
      expect(ColorQuery.fromHex('#80000000')!.argb, 0x80000000);
    });

    test('expands #RGB shorthand', () {
      expect(ColorQuery.fromHex('#F00')!.argb, 0xFFFF0000);
    });

    test('returns null on malformed input', () {
      expect(ColorQuery.fromHex('DA1884'), isNull);
      expect(ColorQuery.fromHex('#XYZ'), isNull);
      expect(ColorQuery.fromHex('#123456789'), isNull);
    });
  });
}
