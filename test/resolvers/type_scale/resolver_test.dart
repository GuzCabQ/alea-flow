import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

import '../_fake_catalog.dart';

void main() {
  group('TypeScaleResolver', () {
    late FakeTokenCatalog catalog;

    setUp(() {
      catalog = FakeTokenCatalog(
        typographyList: const [
          TypographyToken(
            qualifiedName: 'typography.caption',
            fontSize: 12,
            fontWeight: 400,
            fontFamily: 'DM Sans',
          ),
          TypographyToken(
            qualifiedName: 'typography.body1',
            fontSize: 14,
            fontWeight: 400,
            fontFamily: 'DM Sans',
          ),
          TypographyToken(
            qualifiedName: 'typography.body2',
            fontSize: 16,
            fontWeight: 600,
            fontFamily: 'DM Sans',
          ),
          TypographyToken(
            qualifiedName: 'typography.title',
            fontSize: 20,
            fontWeight: 600,
            fontFamily: 'DM Sans',
          ),
          TypographyToken(
            qualifiedName: 'typography.headline',
            fontSize: 24,
            fontWeight: 700,
          ),
        ],
      );
    });

    test('exact (size, weight) → match', () async {
      final resolver = TypeScaleResolver(catalog);
      final result = await resolver.resolve(
        const TypographyQuery(fontSize: 16, fontWeight: 600),
      );
      expect(result.verdict, ResolutionVerdict.match);
      expect(result.recommended?.qualifiedName, 'typography.body2');
    });

    test('different weight → no match (weight is a hard filter)', () async {
      final resolver = TypeScaleResolver(catalog);
      final result = await resolver.resolve(
        const TypographyQuery(
          fontSize: 16,
          fontWeight: 500, // no token has weight 500
        ),
      );
      expect(result.verdict, ResolutionVerdict.noMatch);
      expect(result.warnings.single, contains('weight=500'));
    });

    test('size within ±1px → ambiguous or match depending on margin', () async {
      final resolver = TypeScaleResolver(catalog);
      final result = await resolver.resolve(
        const TypographyQuery(fontSize: 17, fontWeight: 600),
      );
      // Two candidates at weight 600: body2 (16) and title (20). body2 is
      // closer (|17-16|=1) but the default tolerance (±1px) gives score=0.5,
      // below matchThreshold (0.85) → ambiguous.
      expect(
        result.verdict,
        anyOf(ResolutionVerdict.ambiguous, ResolutionVerdict.noMatch),
      );
    });

    test(
      'family mismatch is enforced when both sides declare a family',
      () async {
        final resolver = TypeScaleResolver(catalog);
        final result = await resolver.resolve(
          const TypographyQuery(
            fontSize: 16,
            fontWeight: 600,
            fontFamily: 'Inter',
          ),
        );
        expect(result.verdict, ResolutionVerdict.noMatch);
      },
    );

    test('family is permissive when the token declares none', () async {
      final resolver = TypeScaleResolver(catalog);
      final result = await resolver.resolve(
        const TypographyQuery(
          fontSize: 24,
          fontWeight: 700,
          fontFamily: 'Inter',
        ),
      );
      // 'typography.headline' has no fontFamily — must still be considered.
      expect(result.recommended?.qualifiedName, 'typography.headline');
    });

    test('size_tolerance_px hint widens or narrows the score', () async {
      final resolver = TypeScaleResolver(catalog);
      final loose = await resolver.resolve(
        const TypographyQuery(fontSize: 18, fontWeight: 600),
        const ResolverHints(extras: {'size_tolerance_px': 4}),
      );
      final strict = await resolver.resolve(
        const TypographyQuery(fontSize: 18, fontWeight: 600),
        const ResolverHints(extras: {'size_tolerance_px': 1}),
      );
      expect(loose.confidence, greaterThan(strict.confidence));
    });

    test('catalog with no typography tokens → no match', () async {
      final empty = FakeTokenCatalog(typographyList: const []);
      final resolver = TypeScaleResolver(empty);
      final result = await resolver.resolve(
        const TypographyQuery(fontSize: 16, fontWeight: 400),
      );
      expect(result.verdict, ResolutionVerdict.noMatch);
    });
  });
}
