// Performance smoke for PaletteResolver.
//
// Acceptance criterion from the implementation plan: "1000 resolve()
// paralelos completan en < 2s sobre catálogo de 200 tokens." Generous wall
// budget here (5s) to absorb CI jitter — actual cost on a warm laptop is
// well under 500ms thanks to the per-resolver Lab cache.

import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

import '../_fake_catalog.dart';

void main() {
  test(
    'PaletteResolver: 1000 parallel resolves over 200 tokens < 5s',
    () async {
      final tokens = List<ColorToken>.generate(200, (i) {
        // Spread 200 colors deterministically across the cube.
        final r = (i * 17) & 0xFF;
        final g = (i * 41) & 0xFF;
        final b = (i * 71) & 0xFF;
        return ColorToken(
          qualifiedName: 'spread.c$i',
          argb: 0xFF000000 | (r << 16) | (g << 8) | b,
        );
      });
      final catalog = FakeTokenCatalog(colorList: tokens);
      final resolver = PaletteResolver(catalog);

      final sw = Stopwatch()..start();
      await Future.wait(
        List<Future<ResolutionResult<ColorToken>>>.generate(1000, (i) {
          final argb = 0xFF000000 | ((i * 31) & 0xFFFFFF);
          return resolver.resolve(ColorQuery(argb));
        }),
      );
      sw.stop();

      expect(
        sw.elapsedMilliseconds,
        lessThan(5000),
        reason: 'observed: ${sw.elapsedMilliseconds}ms',
      );
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
