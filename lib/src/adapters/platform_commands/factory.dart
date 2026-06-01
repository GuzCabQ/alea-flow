// ALEA — platform_commands family factory.

import '../../contracts/platform_command_adapter.dart';
import 'claude/adapter.dart';
import 'codex/adapter.dart';
import 'cursor/adapter.dart';
import 'gemini/adapter.dart';

/// All supported platform adapters, in menu order.
List<PlatformCommandAdapter> allAdapters() => [
  ClaudeCommandAdapter(),
  GeminiCommandAdapter(),
  CodexCommandAdapter(),
  CursorCommandAdapter(),
];

/// Resolve an adapter by [platformId], or null if unknown.
PlatformCommandAdapter? adapterById(String platformId) {
  for (final a in allAdapters()) {
    if (a.platformId == platformId) return a;
  }
  return null;
}

/// Result of resolving a `--platform` spec string into adapters.
class PlatformSelection {
  /// Resolved adapters, deduped, in menu order.
  final List<PlatformCommandAdapter> adapters;

  /// Tokens that did not match any known platform.
  final List<String> unknown;

  const PlatformSelection(this.adapters, this.unknown);
}

/// Parse a `--platform` spec ("all" or a comma list) into adapters. Expands
/// "all", trims/lowercases tokens, dedupes by platformId, and collects unknown
/// tokens separately (the caller decides whether an unknown token is fatal).
PlatformSelection resolvePlatformSpec(String spec) {
  final tokens = spec.trim().toLowerCase() == 'all'
      ? <String>['all']
      : spec
            .split(',')
            .map((s) => s.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toList();
  final adapters = <PlatformCommandAdapter>[];
  final seen = <String>{};
  final unknown = <String>[];
  for (final id in tokens) {
    if (id == 'all') {
      for (final a in allAdapters()) {
        if (seen.add(a.platformId)) adapters.add(a);
      }
      continue;
    }
    final a = adapterById(id);
    if (a == null) {
      unknown.add(id);
      continue;
    }
    if (seen.add(a.platformId)) adapters.add(a);
  }
  return PlatformSelection(adapters, unknown);
}
