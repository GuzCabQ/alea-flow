import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

import '../_fake_catalog.dart';

void main() {
  group('LayoutMetricResolver', () {
    late FakeTokenCatalog catalog;

    setUp(() {
      catalog = FakeTokenCatalog(
        spacingList: const [
          SpacingToken(qualifiedName: 'spacing.s4', value: 4),
          SpacingToken(qualifiedName: 'spacing.s8', value: 8),
          SpacingToken(qualifiedName: 'spacing.s12', value: 12),
          SpacingToken(qualifiedName: 'spacing.s16', value: 16),
          SpacingToken(qualifiedName: 'spacing.s24', value: 24),
          SpacingToken(qualifiedName: 'spacing.s32', value: 32),
          SpacingToken(qualifiedName: 'gutter.pct5', value: 5, unit: '%'),
          SpacingToken(qualifiedName: 'gutter.pct10', value: 10, unit: '%'),
        ],
      );
    });

    test('exact value within tolerance → match', () async {
      final resolver = LayoutMetricResolver(catalog);
      final result = await resolver.resolve(const LayoutMetricQuery(value: 16));
      expect(result.verdict, ResolutionVerdict.match);
      expect(result.recommended?.qualifiedName, 'spacing.s16');
    });

    test('unit filter: querying px ignores % tokens', () async {
      final resolver = LayoutMetricResolver(catalog);
      // Query an exact px value so the verdict is `match` and the unit
      // filter is observable in the recommended token (not just in the
      // candidate list).
      final result = await resolver.resolve(const LayoutMetricQuery(value: 4));
      expect(result.verdict, ResolutionVerdict.match);
      expect(result.recommended?.unit, 'px');
      // No % token leaked into the ranking.
      expect(result.candidates.every((c) => c.token.unit == 'px'), isTrue);
    });

    test('% unit yields % tokens', () async {
      final resolver = LayoutMetricResolver(catalog);
      final result = await resolver.resolve(
        const LayoutMetricQuery(value: 5, unit: '%'),
      );
      expect(result.recommended?.unit, '%');
      expect(result.recommended?.qualifiedName, 'gutter.pct5');
    });

    test('value between two declared steps → ambiguous', () async {
      final resolver = LayoutMetricResolver(catalog);
      final result = await resolver.resolve(
        const LayoutMetricQuery(value: 6), // between s4 and s8
      );
      expect(
        result.verdict,
        anyOf(ResolutionVerdict.ambiguous, ResolutionVerdict.noMatch),
      );
    });

    test('tolerance hint widens the match threshold', () async {
      final resolver = LayoutMetricResolver(catalog);
      final tight = await resolver.resolve(
        const LayoutMetricQuery(value: 6),
        const ResolverHints(extras: {'tolerance': 0.5}),
      );
      final loose = await resolver.resolve(
        const LayoutMetricQuery(value: 6),
        const ResolverHints(extras: {'tolerance': 4}),
      );
      expect(loose.confidence, greaterThan(tight.confidence));
    });

    test('no tokens of the requested unit → no match with warning', () async {
      final resolver = LayoutMetricResolver(catalog);
      final result = await resolver.resolve(
        const LayoutMetricQuery(value: 10, unit: 'em'),
      );
      expect(result.verdict, ResolutionVerdict.noMatch);
      expect(result.warnings.single, contains('unit'));
    });
  });
}
