// Tests for ContextPacketBuilder.
//
// Strategy: temp-project trees with a minimal `.alea.yaml`. Build packet,
// mutate config, rebuild, assert hash/TTL/reuse semantics.

import 'dart:io';

import 'package:alea_flow/alea_flow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ContextPacketBuilder', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('alea_packet_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('builds a packet rendering every required section', () async {
      _writeMinimalConfig(tmp.path, packageName: 'demo');
      final builder = ContextPacketBuilder(projectRoot: tmp.path);
      final packet = await builder.build();
      // Markdown sections must all be present.
      expect(packet.body, contains('# ALEA Context Packet — demo'));
      expect(packet.body, contains('## Project'));
      expect(packet.body, contains('## Architecture'));
      expect(packet.body, contains('## State management'));
      expect(packet.body, contains('## Routing'));
      expect(packet.body, contains('## Theme'));
      expect(packet.body, contains('## Testing'));
      expect(packet.body, contains('## Coverage thresholds'));
      expect(packet.body, contains('## Ticket source'));
      expect(packet.body, contains('## Design source'));
      expect(packet.body, contains('## MR policy'));
      expect(packet.body, contains('## Pipeline operations'));
    });

    test('hash changes when .alea.yaml content changes', () async {
      _writeMinimalConfig(tmp.path, packageName: 'demo');
      final builder = ContextPacketBuilder(projectRoot: tmp.path);
      final first = await builder.build();

      // Mutate the source.
      _writeMinimalConfig(tmp.path, packageName: 'demo_v2');
      final second = await builder.build();

      expect(second.hash, isNot(first.hash));
      expect(second.body, contains('demo_v2'));
    });

    test(
      'reuses existing packet when hash matches and TTL not exceeded',
      () async {
        _writeMinimalConfig(tmp.path, packageName: 'demo');
        final fixedNow = DateTime.utc(2026, 5, 23, 10);
        final builder = ContextPacketBuilder(
          projectRoot: tmp.path,
          clock: () => fixedNow,
        );
        final first = await builder.build(runDirectory: tmp.path);
        // Touch the file to a known size and re-run.
        final file = File(p.join(tmp.path, 'context-packet.md'));
        final mtimeBefore = await file.lastModified();

        // Wait briefly to ensure mtime would change if rewritten.
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final second = await builder.build(runDirectory: tmp.path);
        final mtimeAfter = await file.lastModified();
        expect(second.hash, first.hash);
        expect(
          mtimeAfter,
          mtimeBefore,
          reason: 'reused packet must not be re-written to disk',
        );
      },
    );

    test('regenerates when source changed inside TTL', () async {
      _writeMinimalConfig(tmp.path, packageName: 'demo');
      final fixedNow = DateTime.utc(2026, 5, 23, 10);
      final builder = ContextPacketBuilder(
        projectRoot: tmp.path,
        clock: () => fixedNow,
      );
      await builder.build(runDirectory: tmp.path);

      _writeMinimalConfig(tmp.path, packageName: 'demo_new');
      final second = await builder.build(runDirectory: tmp.path);
      expect(second.body, contains('demo_new'));
    });

    test('regenerates when TTL expired even if hash unchanged', () async {
      _writeMinimalConfig(tmp.path, packageName: 'demo');
      DateTime now = DateTime.utc(2026, 5, 23, 10);
      final builder = ContextPacketBuilder(
        projectRoot: tmp.path,
        clock: () => now,
        ttl: const Duration(seconds: 30),
      );
      final first = await builder.build(runDirectory: tmp.path);

      // Advance the clock past expiresAt.
      now = first.expiresAt.add(const Duration(seconds: 1));
      final second = await builder.build(runDirectory: tmp.path);

      // Same source content → same hash, but generatedAt advanced.
      expect(second.hash, first.hash);
      expect(second.generatedAt.isAfter(first.generatedAt), isTrue);
    });

    test('force: true regenerates regardless of cache', () async {
      _writeMinimalConfig(tmp.path, packageName: 'demo');
      DateTime now = DateTime.utc(2026, 5, 23, 10);
      final builder = ContextPacketBuilder(
        projectRoot: tmp.path,
        clock: () => now,
      );
      final first = await builder.build(runDirectory: tmp.path);
      now = now.add(const Duration(seconds: 1));
      final second = await builder.build(runDirectory: tmp.path, force: true);
      expect(second.generatedAt.isAfter(first.generatedAt), isTrue);
    });

    test('without runDirectory builds in-memory without persistence', () async {
      _writeMinimalConfig(tmp.path, packageName: 'demo');
      final builder = ContextPacketBuilder(projectRoot: tmp.path);
      final packet = await builder.build();
      expect(packet.body, isNotEmpty);
      // Nothing written under tmp.
      expect(File(p.join(tmp.path, 'context-packet.md')).existsSync(), isFalse);
    });

    test('missing .alea.yaml throws ContextPacketException', () async {
      // tmp has no .alea.yaml.
      final builder = ContextPacketBuilder(projectRoot: tmp.path);
      await expectLater(
        builder.build(),
        throwsA(isA<ContextPacketException>()),
      );
    });

    test('emits journal events with reuse vs generated actions', () async {
      _writeMinimalConfig(tmp.path, packageName: 'demo');
      final journal = JsonlRunJournal.forRunDirectory(tmp.path);
      final builder = ContextPacketBuilder(
        projectRoot: tmp.path,
        journal: journal,
      );
      await builder.build(runDirectory: tmp.path);
      await builder.build(runDirectory: tmp.path);
      await journal.close();

      final events = await journal.readAll().toList();
      final actions = events
          .where((e) => e.source == 'context_packet:builder')
          .map((e) => e.payload['action'])
          .toList();
      expect(actions, ['generated', 'reused']);
    });

    test(
      'rendered packet is round-trippeable via ContextPacket.parse',
      () async {
        _writeMinimalConfig(tmp.path, packageName: 'demo');
        final builder = ContextPacketBuilder(projectRoot: tmp.path);
        final original = await builder.build(runDirectory: tmp.path);
        final raw = File(
          p.join(tmp.path, 'context-packet.md'),
        ).readAsStringSync();
        final replay = ContextPacket.parse(raw);
        expect(replay.hash, original.hash);
        expect(replay.body, original.body);
      },
    );

    test('hash differs across distinct sources', () async {
      _writeMinimalConfig(tmp.path, packageName: 'a');
      final hashA = (await ContextPacketBuilder(
        projectRoot: tmp.path,
      ).build()).hash;
      _writeMinimalConfig(tmp.path, packageName: 'b');
      final hashB = (await ContextPacketBuilder(
        projectRoot: tmp.path,
      ).build()).hash;
      expect(hashA, isNot(hashB));
    });
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────────

void _writeMinimalConfig(String projectRoot, {required String packageName}) {
  final yaml =
      '''
config_version: "1.0.0"

project:
  package_name: $packageName
  pubspec_path: pubspec.yaml

architecture:
  layers:
    domain:
      paths:
        - lib/src/domain/
      forbid_imports:
        - "package:flutter/"
    infrastructure:
      paths:
        - lib/src/infrastructure/
      may_import: [domain]
    presentation:
      paths:
        - lib/src/presentation/
      may_import: [domain]

state_management:
  style: riverpod_manual

routing:
  package: go_router
  router_path: lib/src/app/router.dart

theme:
  path: lib/src/theme/
  brand_colors:
    primary: "#DA1884"
    secondary: "#E0F5F5"
  typography:
    body2: "DM Sans 16/600"

testing:
  framework: flutter_test
  fakes_path: test/fakes/

coverage:
  thresholds:
    domain: 95
    infrastructure: 80
    presentation: 70

ticket_source:
  adapter: file

design_source:
  default: figma

mr:
  policy: single-commit-amend
  branch_pattern: "feature/{ticket_id}-{slug}"
  pre_push:
    - dart format .
    - dart analyze
    - flutter test

pipeline:
  default_mode: guided
  modes_available: [guided, semi, auto]
  cost_warn_usd: 3.0
  cost_hard_stop_usd: 5.0

gates:
  domain: [domain]
  infrastructure: [infra]
  presentation: [presentation]
''';
  File('$projectRoot/.alea.yaml').writeAsStringSync(yaml);
}
