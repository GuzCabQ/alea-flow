import 'package:alea_flow/src/adapters/platform_commands/factory.dart';
import 'package:test/test.dart';

void main() {
  test('allAdapters returns the four v1 platforms', () {
    final ids = allAdapters().map((a) => a.platformId).toSet();
    expect(ids, {'claude', 'gemini', 'codex', 'cursor'});
  });

  test('adapterById resolves a known id and returns null otherwise', () {
    expect(adapterById('gemini')?.platformId, 'gemini');
    expect(adapterById('nope'), isNull);
  });

  group('resolvePlatformSpec', () {
    test('expands all to the four platforms', () {
      final sel = resolvePlatformSpec('all');
      expect(sel.adapters.map((a) => a.platformId), [
        'claude',
        'gemini',
        'codex',
        'cursor',
      ]);
      expect(sel.unknown, isEmpty);
    });
    test('parses a comma list, trims, dedupes', () {
      final sel = resolvePlatformSpec(' claude , gemini ,claude');
      expect(sel.adapters.map((a) => a.platformId), ['claude', 'gemini']);
      expect(sel.unknown, isEmpty);
    });
    test('collects unknown tokens without throwing', () {
      final sel = resolvePlatformSpec('claude,typo');
      expect(sel.adapters.map((a) => a.platformId), ['claude']);
      expect(sel.unknown, ['typo']);
    });
  });
}
