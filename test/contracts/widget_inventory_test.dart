// Tests for the WidgetInventory contract — entry JSON round-trip and the
// InMemoryWidgetInventory reference implementation.

import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

void main() {
  group('WidgetEntry', () {
    test('toJson omits empty optionals', () {
      const e = WidgetEntry(
        className: 'FooComponent',
        filePath: 'lib/foo.dart',
        md5Hash: 'abc',
      );
      final json = e.toJson();
      expect(json['class_name'], 'FooComponent');
      expect(json['md5_hash'], 'abc');
      expect(json.containsKey('category'), isFalse);
      expect(json.containsKey('tokens_used'), isFalse);
      expect(json.containsKey('meta'), isFalse);
    });

    test('toJson includes populated optionals', () {
      const e = WidgetEntry(
        className: 'ButtonSaveComponent',
        filePath: 'lib/button.dart',
        category: 'button',
        tokensUsed: ['StyleColors.brand60', 'StyleFonts.body2'],
        constructorSignature:
            'ButtonSaveComponent({required this.onPressed, required this.label})',
        md5Hash: 'deadbeef',
        meta: {'extends': 'StatelessWidget'},
      );
      final json = e.toJson();
      expect(json['category'], 'button');
      expect(json['tokens_used'], hasLength(2));
      expect(json['constructor_signature'], isA<String>());
      expect(json['meta'], {'extends': 'StatelessWidget'});
    });

    test('round-trip preserves all fields', () {
      const original = WidgetEntry(
        className: 'CardItem',
        filePath: 'lib/card.dart',
        category: 'card',
        tokensUsed: ['StyleColors.brand20'],
        constructorSignature: 'CardItem({required this.title})',
        md5Hash: 'cafe',
        meta: {'preview': false},
      );
      final replay = WidgetEntry.fromJson(original.toJson());
      expect(replay.className, original.className);
      expect(replay.filePath, original.filePath);
      expect(replay.category, original.category);
      expect(replay.tokensUsed, original.tokensUsed);
      expect(replay.constructorSignature, original.constructorSignature);
      expect(replay.md5Hash, original.md5Hash);
      expect(replay.meta, original.meta);
    });
  });

  group('InMemoryWidgetInventory', () {
    test('entries() returns what was injected, in order', () async {
      final inv = InMemoryWidgetInventory(
        entries: const [
          WidgetEntry(className: 'A', filePath: 'a.dart', md5Hash: '1'),
          WidgetEntry(className: 'B', filePath: 'b.dart', md5Hash: '2'),
        ],
      );
      final list = await inv.entries();
      expect(list.map((e) => e.className), ['A', 'B']);
    });

    test('byClassName filters exact', () async {
      final inv = InMemoryWidgetInventory(
        entries: const [
          WidgetEntry(className: 'A', filePath: 'a.dart', md5Hash: '1'),
          WidgetEntry(className: 'B', filePath: 'b.dart', md5Hash: '2'),
          WidgetEntry(className: 'A', filePath: 'a2.dart', md5Hash: '3'),
        ],
      );
      final hits = await inv.byClassName('A');
      expect(hits, hasLength(2));
      final miss = await inv.byClassName('Z');
      expect(miss, isEmpty);
    });

    test('default sourceId is in_memory', () {
      final inv = InMemoryWidgetInventory(entries: const []);
      expect(inv.sourceId, 'in_memory');
    });

    test('caller-provided sourceId overrides default', () {
      final inv = InMemoryWidgetInventory(
        entries: const [],
        sourceId: 'storybook',
      );
      expect(inv.sourceId, 'storybook');
    });
  });

  test('WidgetInventoryException toString includes source + message', () {
    const e = WidgetInventoryException('parse error', source: 'lib/foo.dart');
    expect(e.toString(), contains('source=lib/foo.dart'));
    expect(e.toString(), contains('message=parse error'));
  });
}
