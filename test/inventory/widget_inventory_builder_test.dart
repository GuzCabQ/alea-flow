// Tests for WidgetInventoryBuilder.
//
// Verifies:
//   - Five Widget-like classes are discovered across six fixture files
//     (5 explicit widget files + one with two widgets - one non-widget file
//     contributes nothing).
//   - Token references are extracted accurately (StyleColors / StyleFonts /
//     StyleSize members).
//   - Constructor signatures round-trip.
//   - md5Hash changes when the source changes.
//   - Inventory is ordered deterministically.
//   - JSON emission yields parseable, schema-conformant output.

import 'dart:convert';
import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('WidgetInventoryBuilder', () {
    late String fixtureRoot;

    setUp(() {
      fixtureRoot = p.normalize(
        p.join(Directory.current.path, 'test/inventory/fixtures/widgets'),
      );
    });

    test('discovers all 6 widget classes in the fixture set', () async {
      final builder = WidgetInventoryBuilder(
        scanPaths: [fixtureRoot],
        projectRoot: Directory.current.path,
      );
      final inv = await builder.build();
      final entries = await inv.entries();
      final names = entries.map((e) => e.className).toSet();
      expect(names, {
        'ButtonSaveComponent',
        'CardSummaryComponent',
        'TextFieldInput',
        'LoadingOverlay',
        'SectionFormComponent',
        'SectionDividerWidget',
      });
    });

    test('ignores plain Dart utility classes', () async {
      final builder = WidgetInventoryBuilder(
        scanPaths: [fixtureRoot],
        projectRoot: Directory.current.path,
      );
      final inv = await builder.build();
      final entries = await inv.entries();
      expect(entries.where((e) => e.className == 'StringHelper'), isEmpty);
    });

    test('skips private classes (leading underscore)', () async {
      final builder = WidgetInventoryBuilder(
        scanPaths: [fixtureRoot],
        projectRoot: Directory.current.path,
      );
      final inv = await builder.build();
      final entries = await inv.entries();
      expect(entries.where((e) => e.className.startsWith('_')), isEmpty);
    });

    test('extracts token references accurately', () async {
      final builder = WidgetInventoryBuilder(
        scanPaths: [fixtureRoot],
        projectRoot: Directory.current.path,
      );
      final inv = await builder.build();
      final entries = await inv.entries();
      final button = entries.firstWhere(
        (e) => e.className == 'ButtonSaveComponent',
      );
      expect(button.tokensUsed, {'StyleColors.brand60', 'StyleFonts.body2'});

      final card = entries.firstWhere(
        (e) => e.className == 'CardSummaryComponent',
      );
      expect(card.tokensUsed, {
        'StyleColors.brand20',
        'StyleFonts.body1',
        'StyleFonts.title',
        'StyleSize.md',
      });
    });

    test('categorizes by class-name suffix', () async {
      final builder = WidgetInventoryBuilder(
        scanPaths: [fixtureRoot],
        projectRoot: Directory.current.path,
      );
      final inv = await builder.build();
      final entries = await inv.entries();
      expect(
        entries
            .firstWhere((e) => e.className == 'ButtonSaveComponent')
            .category,
        'button',
      );
      expect(
        entries
            .firstWhere((e) => e.className == 'CardSummaryComponent')
            .category,
        'card',
      );
      expect(
        entries.firstWhere((e) => e.className == 'TextFieldInput').category,
        'input',
      );
    });

    test('captures the constructor signature', () async {
      final builder = WidgetInventoryBuilder(
        scanPaths: [fixtureRoot],
        projectRoot: Directory.current.path,
      );
      final inv = await builder.build();
      final entries = await inv.entries();
      final button = entries.firstWhere(
        (e) => e.className == 'ButtonSaveComponent',
      );
      expect(button.constructorSignature, isNotNull);
      expect(button.constructorSignature, contains('ButtonSaveComponent'));
      expect(button.constructorSignature, contains('onPressed'));
      expect(button.constructorSignature, contains('label'));
    });

    test('md5Hash changes when the file content changes', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_inventory_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final file = File(p.join(tmp.path, 'foo_component.dart'));
      file.writeAsStringSync('class FooComponent { const FooComponent(); }');
      final builder1 = WidgetInventoryBuilder(scanPaths: [tmp.path]);
      final first = await builder1.build();
      final hash1 = (await first.byClassName('FooComponent')).single.md5Hash;

      file.writeAsStringSync(
        'class FooComponent { const FooComponent(); '
        'void changed() {} }',
      );
      final builder2 = WidgetInventoryBuilder(scanPaths: [tmp.path]);
      final second = await builder2.build();
      final hash2 = (await second.byClassName('FooComponent')).single.md5Hash;
      expect(hash2, isNot(hash1));
    });

    test('entries are ordered by filePath then className', () async {
      final builder = WidgetInventoryBuilder(
        scanPaths: [fixtureRoot],
        projectRoot: Directory.current.path,
      );
      final inv = await builder.build();
      final entries = await inv.entries();
      for (var i = 1; i < entries.length; i++) {
        final prev = entries[i - 1];
        final cur = entries[i];
        final pathCmp = prev.filePath.compareTo(cur.filePath);
        if (pathCmp == 0) {
          expect(prev.className.compareTo(cur.className), lessThan(0));
        } else {
          expect(pathCmp, lessThan(0));
        }
      }
    });

    test('inventory sourceId is "dart_source"', () async {
      final builder = WidgetInventoryBuilder(scanPaths: [fixtureRoot]);
      final inv = await builder.build();
      expect(inv.sourceId, 'dart_source');
    });

    test('emitJsonTo writes a parseable JSON file', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_inventory_json_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final output = p.join(tmp.path, 'widget_inventory.json');

      final builder = WidgetInventoryBuilder(
        scanPaths: [fixtureRoot],
        projectRoot: Directory.current.path,
      );
      final inv = await builder.build();
      await builder.emitJsonTo(output, inv);

      final raw = File(output).readAsStringSync();
      final parsed = jsonDecode(raw) as Map<String, Object?>;
      expect(parsed['version'], '1.0.0');
      expect(parsed['source'], 'dart_source');
      expect(parsed['entries'], isA<List>());
      expect((parsed['entries'] as List), hasLength(6));
    });

    test('journal records start + completion events', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_inventory_j_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final journal = JsonlRunJournal.forRunDirectory(tmp.path);

      final builder = WidgetInventoryBuilder(scanPaths: [fixtureRoot]);
      await builder.build(journal: journal);
      final events = await journal.readAll().toList();
      await journal.close();

      expect(events.first.kind, JournalEventKind.started);
      expect(events.last.kind, JournalEventKind.completed);
      expect(events.last.payload['widgets_found'], 6);
    });
  });
}
