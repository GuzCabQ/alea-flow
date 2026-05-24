// ALEA — ContextPacketBuilder.
//
// Produces (or reuses) the `.pipeline/runs/<id>/context-packet.md` file
// that skills inject as a single LLM prefix. Reuse logic:
//
//   - Existing packet file present
//   - AND its `hash` matches the freshly computed source fingerprint
//   - AND its `expires_at` is in the future
//   => return existing packet, no rewrite.
//
//   Any of those checks fails (or `force: true`) => regenerate from scratch.
//
// Sources considered for the fingerprint: `.alea.yaml` only, in v1. The
// builder's design lets future versions append more files without changing
// the call surface.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../contracts/context_packet.dart';
import '../../contracts/project_config.dart';
import '../../contracts/run_journal.dart';
import '../config/loader.dart';

class ContextPacketBuilder {
  /// Absolute path of the consumer's project root.
  final String projectRoot;

  /// How long a freshly-built packet stays valid. Default 5 minutes,
  /// matching Anthropic's prompt-cache TTL.
  final Duration ttl;

  /// Optional clock injection — used by tests to make `isExpired` checks
  /// deterministic.
  final DateTime Function() clock;

  /// Sources whose content contributes to the packet. The default ([
  /// `.alea.yaml` ]) is fine for v1; consumers can pass additional
  /// project-relative paths when they want their packet to invalidate on
  /// other files (e.g. the `theme` directory).
  final List<String> sourcePaths;

  final RunJournal? journal;

  ContextPacketBuilder({
    required this.projectRoot,
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? clock,
    List<String>? sourcePaths,
    this.journal,
  }) : clock = clock ?? (() => DateTime.now().toUtc()),
       sourcePaths = List.unmodifiable(sourcePaths ?? const ['.alea.yaml']);

  /// Build (or reuse) the packet under [runDirectory]. When [runDirectory]
  /// is null, the packet is built and returned without persistence —
  /// useful for ad-hoc preview or for in-memory consumers.
  Future<ContextPacket> build({
    String? runDirectory,
    bool force = false,
  }) async {
    final fingerprints = await _computeFingerprints();
    final combinedHash = _combinedHash(fingerprints);

    final outputPath = runDirectory == null
        ? null
        : p.join(runDirectory, 'context-packet.md');

    if (!force && outputPath != null) {
      final cached = await _maybeReadCached(outputPath, combinedHash);
      if (cached != null) {
        await journal?.record(
          JournalEvent(
            source: 'context_packet:builder',
            kind: JournalEventKind.completed,
            payload: {
              'action': 'reused',
              'hash': combinedHash,
              'expires_at': cached.expiresAt.toIso8601String(),
            },
          ),
        );
        return cached;
      }
    }

    final config = _loadConfig();
    final body = _renderBody(config);
    final now = clock().toUtc();
    final packet = ContextPacket(
      hash: combinedHash,
      sources: fingerprints,
      body: body,
      generatedAt: now,
      expiresAt: now.add(ttl),
    );

    if (outputPath != null) {
      final parent = Directory(p.dirname(outputPath));
      if (!await parent.exists()) await parent.create(recursive: true);
      await File(outputPath).writeAsString(packet.render(), flush: true);
    }

    await journal?.record(
      JournalEvent(
        source: 'context_packet:builder',
        kind: JournalEventKind.completed,
        payload: {
          'action': force ? 'forced' : 'generated',
          'hash': combinedHash,
          'body_bytes': body.length,
          'sources': fingerprints.length,
        },
      ),
    );

    return packet;
  }

  // ── Internals ───────────────────────────────────────────────────────────

  ProjectConfig _loadConfig() {
    try {
      return loadProjectConfig(projectRoot);
    } on ProjectConfigException catch (e) {
      throw ContextPacketException('cannot load .alea.yaml — ${e.toString()}');
    }
  }

  Future<List<SourceFingerprint>> _computeFingerprints() async {
    final out = <SourceFingerprint>[];
    for (final rel in sourcePaths) {
      final absolute = p.join(projectRoot, rel);
      final file = File(absolute);
      if (!await file.exists()) {
        throw ContextPacketException('source file does not exist: $rel');
      }
      final content = await file.readAsString();
      out.add(
        SourceFingerprint(
          path: rel,
          md5: md5.convert(content.codeUnits).toString(),
        ),
      );
    }
    return List.unmodifiable(out);
  }

  String _combinedHash(List<SourceFingerprint> fingerprints) {
    final buf = StringBuffer();
    for (final f in fingerprints) {
      buf.write(f.path);
      buf.write(':');
      buf.write(f.md5);
      buf.write('\n');
    }
    return md5.convert(buf.toString().codeUnits).toString();
  }

  Future<ContextPacket?> _maybeReadCached(
    String outputPath,
    String expectedHash,
  ) async {
    final file = File(outputPath);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final cached = ContextPacket.parse(raw);
      if (cached.hash != expectedHash) return null;
      if (cached.expiresAt.isBefore(clock().toUtc())) return null;
      return cached;
    } on FormatException {
      return null;
    }
  }

  // ── Markdown rendering ──────────────────────────────────────────────────

  String _renderBody(ProjectConfig config) {
    final buf = StringBuffer();
    buf.writeln('# ALEA Context Packet — ${config.project.packageName}');
    buf.writeln();
    buf.writeln(
      'This file is auto-generated. Do not edit by hand. Builders re-emit '
      'it whenever any source in the front-matter changes; consumers (LLM '
      'skills) consume it as a single, hash-stable prefix to maximize '
      "prompt-cache hits.",
    );
    buf.writeln();

    buf.writeln('## Project');
    buf.writeln();
    buf.writeln('- **Package**: `${config.project.packageName}`');
    buf.writeln('- **Pubspec**: `${config.project.pubspecPath}`');
    if (config.project.displayName != null) {
      buf.writeln('- **Display name**: ${config.project.displayName}');
    }
    buf.writeln();

    buf.writeln('## Architecture');
    buf.writeln();
    buf.writeln('### Layers');
    buf.writeln();
    for (final entry in config.architecture.layers.entries) {
      buf.writeln(
        '- **${entry.key}** — paths: '
        '${entry.value.paths.map((p) => '`$p`').join(', ')}',
      );
      if (entry.value.mayImport.isNotEmpty) {
        buf.writeln(
          '  - may import: '
          '${entry.value.mayImport.map((s) => '`$s`').join(', ')}',
        );
      }
      if (entry.value.forbidImports.isNotEmpty) {
        buf.writeln(
          '  - forbids: '
          '${entry.value.forbidImports.map((s) => '`$s`').join(', ')}',
        );
      }
    }
    buf.writeln();

    if (config.architecture.packageBoundaries.isNotEmpty) {
      buf.writeln('### Package boundaries');
      buf.writeln();
      for (final b in config.architecture.packageBoundaries) {
        buf.writeln('- **${b.name}**');
        if (b.description != null) buf.writeln('  - ${b.description}');
        buf.writeln(
          '  - applies to: '
          '${b.appliesTo.map((s) => '`$s`').join(', ')}',
        );
        buf.writeln('  - forbids: ${b.forbid.map((s) => '`$s`').join(', ')}');
      }
      buf.writeln();
    }

    if (config.architecture.wiring != null &&
        config.architecture.wiring!.rules.isNotEmpty) {
      buf.writeln('### Wiring');
      buf.writeln();
      for (final r in config.architecture.wiring!.rules) {
        buf.writeln(
          '- **${r.name}** — `${r.classPattern}` registered in '
          '`${r.manifestFile}` via `${r.registrationCall}`',
        );
      }
      buf.writeln();
    }

    buf.writeln('## State management');
    buf.writeln();
    buf.writeln('- **Style**: `${config.stateManagement.style}`');
    if (config.stateManagement.rules.isNotEmpty) {
      buf.writeln('- Rules:');
      for (final r in config.stateManagement.rules.entries) {
        buf.writeln('  - `${r.key}`: `${r.value}`');
      }
    }
    buf.writeln();

    buf.writeln('## Routing');
    buf.writeln();
    buf.writeln('- **Package**: `${config.routing.package}`');
    buf.writeln('- **Router file**: `${config.routing.routerPath}`');
    buf.writeln();

    buf.writeln('## Theme');
    buf.writeln();
    buf.writeln('- **Path**: `${config.theme.path}`');
    if (config.theme.brandColors.isNotEmpty) {
      buf.writeln('- **Brand colors**:');
      for (final c in config.theme.brandColors.entries) {
        buf.writeln('  - `${c.key}`: `${c.value}`');
      }
    }
    if (config.theme.typography.isNotEmpty) {
      buf.writeln('- **Typography**:');
      for (final t in config.theme.typography.entries) {
        buf.writeln('  - `${t.key}`: `${t.value}`');
      }
    }
    if (config.theme.tokenCatalog != null) {
      buf.writeln(
        '- **Token catalog**: adapter='
        '`${config.theme.tokenCatalog!.adapter}`, source='
        '`${config.theme.tokenCatalog!.source}`',
      );
    }
    buf.writeln();

    buf.writeln('## Testing');
    buf.writeln();
    buf.writeln('- **Framework**: `${config.testing.framework}`');
    buf.writeln('- **Fakes path**: `${config.testing.fakesPath}`');
    buf.writeln('- **Pattern**: `${config.testing.pattern}`');
    buf.writeln('- **Override target**: `${config.testing.overrideTarget}`');
    buf.writeln(
      '- **Prefer fakes over mocks**: '
      '`${config.testing.preferFakesOverMocks}`',
    );
    buf.writeln(
      '- **Fake class pattern**: '
      '`${config.testing.fakeClassPattern}`',
    );
    buf.writeln();

    buf.writeln('## Coverage thresholds');
    buf.writeln();
    for (final t in config.coverage.thresholds.entries) {
      buf.writeln('- `${t.key}`: ${t.value}%');
    }
    buf.writeln();

    buf.writeln('## Ticket source');
    buf.writeln();
    buf.writeln('- **Adapter**: `${config.ticketSource.adapter}`');
    buf.writeln();

    buf.writeln('## Design source');
    buf.writeln();
    buf.writeln(
      '- **Default adapter**: `${config.designSource.defaultAdapter}`',
    );
    if (config.designSource.adapters.isNotEmpty) {
      buf.writeln('- **Enabled adapters**:');
      for (final a in config.designSource.adapters.entries) {
        buf.writeln('  - `${a.key}`: enabled=`${a.value.enabled}`');
      }
    }
    buf.writeln();

    buf.writeln('## MR policy');
    buf.writeln();
    buf.writeln('- **Policy**: `${config.mr.policy}`');
    buf.writeln('- **Branch pattern**: `${config.mr.branchPattern}`');
    if (config.mr.prePush.isNotEmpty) {
      buf.writeln('- **Pre-push steps**:');
      for (final s in config.mr.prePush) {
        buf.writeln('  - `$s`');
      }
    }
    buf.writeln();

    buf.writeln('## Pipeline operations');
    buf.writeln();
    buf.writeln('- **Default mode**: `${config.pipeline.defaultMode}`');
    buf.writeln(
      '- **Available modes**: '
      '${config.pipeline.modesAvailable.map((m) => '`$m`').join(', ')}',
    );
    buf.writeln('- **Cost warn**: \$${config.pipeline.costWarnUsd}');
    buf.writeln('- **Cost hard stop**: \$${config.pipeline.costHardStopUsd}');
    buf.writeln();

    if (config.analyzers.enabled.isNotEmpty ||
        config.analyzers.severityOverrides.isNotEmpty ||
        config.analyzers.options.isNotEmpty) {
      buf.writeln('## Analyzers');
      buf.writeln();
      if (config.analyzers.enabled.isNotEmpty) {
        buf.writeln(
          '- **Enabled**: '
          '${config.analyzers.enabled.map((n) => '`$n`').join(', ')}',
        );
      }
      if (config.analyzers.severityOverrides.isNotEmpty) {
        buf.writeln('- **Severity overrides**:');
        for (final o in config.analyzers.severityOverrides.entries) {
          buf.writeln('  - `${o.key}` → `${o.value}`');
        }
      }
      if (config.analyzers.options.isNotEmpty) {
        buf.writeln('- **Per-analyzer options**:');
        for (final opt in config.analyzers.options.entries) {
          buf.writeln('  - `${opt.key}`:');
          for (final kv in opt.value.entries) {
            buf.writeln('    - `${kv.key}`: `${kv.value}`');
          }
        }
      }
      buf.writeln();
    }

    return buf.toString();
  }
}
