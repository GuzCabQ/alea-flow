// ALEA — ContextPacket contract.
//
// A consolidated, hash-stable snapshot of a consumer's `.alea.yaml` (plus
// any declared auxiliary sources) rendered as markdown so a skill can send
// it as a single LLM prefix. When the same packet is reused across skills
// inside the same TTL window, Anthropic's 5-minute prompt cache hits
// (≈10× cheaper) on the prefix.
//
// File format: YAML front-matter (metadata) + markdown body. One file,
// one read. The builder produces it; consumers `parse()` it.
//
//   ---
//   schema_version: "1.0.0"
//   hash: deadbeef...
//   generated_at: 2026-05-23T10:00:00Z
//   expires_at: 2026-05-23T10:05:00Z
//   sources:
//     - path: .alea.yaml
//       md5: cafef00d...
//   ---
//
//   # ALEA Context Packet — my_app
//   ...
//
// The contract type lives in `contracts/` because it is pure data. The
// builder lives in `core/context/`.

import 'dart:async';

/// Fingerprint of one source file that contributed to the packet body.
class SourceFingerprint {
  /// Project-relative path. Forward slashes; no leading `./`.
  final String path;

  /// md5 of the source content at packet-generation time.
  final String md5;

  const SourceFingerprint({required this.path, required this.md5});

  Map<String, Object?> toJson() => {'path': path, 'md5': md5};

  static SourceFingerprint fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final md5 = json['md5'];
    if (path is! String || md5 is! String) {
      throw const FormatException(
        'SourceFingerprint.fromJson: path and md5 must be strings',
      );
    }
    return SourceFingerprint(path: path, md5: md5);
  }
}

/// Immutable snapshot of the consumer's rules, sized for a single LLM
/// invocation. Reusable across skills as long as [hash] still matches the
/// current sources and [expiresAt] is in the future.
class ContextPacket {
  /// Schema version of the packet format. Bumped on incompatible changes
  /// to the front-matter shape or to the markdown sections.
  static const String currentSchemaVersion = '1.0.0';

  final String schemaVersion;

  /// Combined fingerprint over [sources]. Constant when the inputs are
  /// constant; changes the moment any source file's content changes.
  final String hash;

  /// Per-source fingerprints. Builders write one entry per file that
  /// actually contributed bytes to [body].
  final List<SourceFingerprint> sources;

  /// Rendered markdown body. This is the string consumers send to the LLM.
  final String body;

  /// UTC timestamp when the packet was built.
  final DateTime generatedAt;

  /// UTC timestamp after which the packet should be treated as stale.
  /// Default lifetime is the builder's TTL (typically 5 minutes — chosen
  /// to align with Anthropic's prompt-cache window).
  final DateTime expiresAt;

  const ContextPacket({
    this.schemaVersion = currentSchemaVersion,
    required this.hash,
    required this.sources,
    required this.body,
    required this.generatedAt,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  /// Serialize the packet to its on-disk form: YAML front-matter + markdown
  /// body. Round-trippeable via [parse].
  String render() {
    final buf = StringBuffer();
    buf.writeln('---');
    buf.writeln('schema_version: "$schemaVersion"');
    buf.writeln('hash: $hash');
    buf.writeln('generated_at: ${generatedAt.toUtc().toIso8601String()}');
    buf.writeln('expires_at: ${expiresAt.toUtc().toIso8601String()}');
    buf.writeln('sources:');
    for (final s in sources) {
      buf.writeln('  - path: ${s.path}');
      buf.writeln('    md5: ${s.md5}');
    }
    buf.writeln('---');
    buf.writeln();
    buf.write(body);
    return buf.toString();
  }

  /// Parse a packet from its rendered form. Throws [FormatException] when
  /// the front matter is missing or malformed.
  static ContextPacket parse(String raw) {
    final lines = raw.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') {
      throw const FormatException(
        'ContextPacket: missing opening "---" front-matter delimiter',
      );
    }
    var i = 1;
    final fm = <String, Object?>{};
    final sources = <SourceFingerprint>[];
    String? currentSourcePath;
    while (i < lines.length && lines[i].trim() != '---') {
      final line = lines[i];
      if (line.startsWith('sources:')) {
        // The remaining front-matter lines are the sources block; consume.
        i++;
        while (i < lines.length && lines[i].trim() != '---') {
          final src = lines[i];
          if (src.startsWith('  - path:')) {
            currentSourcePath = src.substring('  - path:'.length).trim();
          } else if (src.startsWith('    md5:')) {
            if (currentSourcePath == null) {
              throw const FormatException(
                'ContextPacket: stray "md5:" without preceding "path:"',
              );
            }
            sources.add(
              SourceFingerprint(
                path: currentSourcePath,
                md5: src.substring('    md5:'.length).trim(),
              ),
            );
            currentSourcePath = null;
          }
          i++;
        }
        break;
      }
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) {
        i++;
        continue;
      }
      final key = line.substring(0, colonIdx).trim();
      var value = line.substring(colonIdx + 1).trim();
      if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        value = value.substring(1, value.length - 1);
      }
      fm[key] = value;
      i++;
    }
    if (i >= lines.length) {
      throw const FormatException(
        'ContextPacket: missing closing "---" front-matter delimiter',
      );
    }
    // Skip the closing "---" and the optional blank line.
    i++;
    if (i < lines.length && lines[i].trim().isEmpty) i++;
    final bodyBuf = StringBuffer();
    for (var j = i; j < lines.length; j++) {
      bodyBuf.write(lines[j]);
      if (j < lines.length - 1) bodyBuf.write('\n');
    }

    final hash = fm['hash'];
    final schemaVersion = fm['schema_version'] ?? currentSchemaVersion;
    final generatedAt = fm['generated_at'];
    final expiresAt = fm['expires_at'];
    if (hash is! String || generatedAt is! String || expiresAt is! String) {
      throw const FormatException(
        'ContextPacket: front matter must include hash, generated_at, expires_at',
      );
    }
    return ContextPacket(
      schemaVersion: schemaVersion as String,
      hash: hash,
      sources: List.unmodifiable(sources),
      body: bodyBuf.toString(),
      generatedAt: DateTime.parse(generatedAt).toUtc(),
      expiresAt: DateTime.parse(expiresAt).toUtc(),
    );
  }

  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'hash': hash,
    'generated_at': generatedAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'sources': sources.map((s) => s.toJson()).toList(),
    'body_length': body.length,
  };
}

/// Thrown by `ContextPacketBuilder` when sources cannot be read or the
/// configured TTL is invalid.
class ContextPacketException implements Exception {
  final String message;
  const ContextPacketException(this.message);
  @override
  String toString() => 'ContextPacketException(message=$message)';
}

/// Marker for exposing the contract as a public API surface — kept here so
/// the `lib/alea.dart` barrel does not need to add scaffolding-style
/// `show` clauses.
typedef ContextPacketFuture = Future<ContextPacket>;
