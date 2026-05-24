// ALEA — InMemoryWidgetInventory.
//
// Default [WidgetInventory] implementation: holds a pre-computed list of
// entries in memory. Returned by [WidgetInventoryBuilder] and used by tests
// that want to inject a fixed inventory.

import 'dart:async';

import '../contracts/widget_inventory.dart';

class InMemoryWidgetInventory implements WidgetInventory {
  InMemoryWidgetInventory({
    required List<WidgetEntry> entries,
    this.sourceId = 'in_memory',
  }) : _entries = List.unmodifiable(entries);

  final List<WidgetEntry> _entries;

  @override
  final String sourceId;

  @override
  Future<List<WidgetEntry>> entries() async => _entries;

  @override
  Future<List<WidgetEntry>> byClassName(String name) async =>
      _entries.where((e) => e.className == name).toList(growable: false);
}
