// Tests for ComponentLookup post-Phase-5 wiring.

import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

void main() {
  group('ComponentLookup', () {
    test('no inventory → noMatch with explanatory warning', () async {
      final resolver = ComponentLookup();
      final result = await resolver.resolve(
        const ComponentQuery(description: 'botón guardar'),
      );
      expect(result.verdict, ResolutionVerdict.noMatch);
      expect(result.warnings.single, contains('no WidgetInventory injected'));
    });

    test('empty inventory → noMatch with explanatory warning', () async {
      final resolver = ComponentLookup(
        inventory: InMemoryWidgetInventory(entries: const []),
      );
      final result = await resolver.resolve(
        const ComponentQuery(description: 'guardar'),
      );
      expect(result.verdict, ResolutionVerdict.noMatch);
      expect(result.warnings.single, contains('empty'));
    });

    test('high fuzzy match → match verdict', () async {
      final resolver = ComponentLookup(
        inventory: InMemoryWidgetInventory(
          entries: const [
            WidgetEntry(
              className: 'ButtonSaveSCIComponent',
              filePath: 'lib/button_save.dart',
              md5Hash: '1',
            ),
            WidgetEntry(
              className: 'CardSummaryComponent',
              filePath: 'lib/card.dart',
              md5Hash: '2',
            ),
          ],
        ),
      );
      final result = await resolver.resolve(
        const ComponentQuery(description: 'ButtonSaveSCIComponent'),
      );
      expect(result.verdict, ResolutionVerdict.match);
      expect(result.recommended?.qualifiedName, 'ButtonSaveSCIComponent');
    });

    test('partial match → ambiguous or noMatch depending on score', () async {
      final resolver = ComponentLookup(
        inventory: InMemoryWidgetInventory(
          entries: const [
            WidgetEntry(
              className: 'ButtonSaveSCIComponent',
              filePath: 'lib/a.dart',
              md5Hash: '1',
            ),
            WidgetEntry(
              className: 'ButtonCancelComponent',
              filePath: 'lib/b.dart',
              md5Hash: '2',
            ),
          ],
        ),
      );
      final result = await resolver.resolve(
        const ComponentQuery(description: 'guardar'),
      );
      // "guardar" doesn't appear in either className → fuzzy score is low.
      expect(result.verdict, ResolutionVerdict.noMatch);
    });

    test('tokensUsed acts as a hard filter', () async {
      final resolver = ComponentLookup(
        inventory: InMemoryWidgetInventory(
          entries: const [
            WidgetEntry(
              className: 'ButtonSaveSCIComponent',
              filePath: 'lib/a.dart',
              tokensUsed: ['StyleColors.brand60', 'StyleFonts.body2'],
              md5Hash: '1',
            ),
            WidgetEntry(
              className: 'ButtonSaveAltComponent',
              filePath: 'lib/b.dart',
              tokensUsed: ['StyleColors.secondary'],
              md5Hash: '2',
            ),
          ],
        ),
      );
      final result = await resolver.resolve(
        const ComponentQuery(
          description: 'ButtonSaveSCIComponent',
          tokensUsed: {'StyleColors.brand60'},
        ),
      );
      // Only ButtonSaveSCIComponent passes the filter.
      expect(result.candidates, hasLength(1));
      expect(
        result.candidates.single.token.qualifiedName,
        'ButtonSaveSCIComponent',
      );
    });

    test('recommended token wraps the WidgetEntry as NamedToken', () async {
      final resolver = ComponentLookup(
        inventory: InMemoryWidgetInventory(
          entries: const [
            WidgetEntry(
              className: 'CardSummaryComponent',
              filePath: 'lib/card.dart',
              md5Hash: '1',
            ),
          ],
        ),
      );
      final result = await resolver.resolve(
        const ComponentQuery(description: 'CardSummaryComponent'),
      );
      final token = result.recommended!;
      expect(token.family, 'widget');
      expect(token.qualifiedName, 'CardSummaryComponent');
      expect(token.value, isA<Map<String, Object?>>());
      expect((token.value as Map)['class_name'], 'CardSummaryComponent');
    });
  });
}
