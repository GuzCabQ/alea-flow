// Round-trip tests for the ContextPacket contract.

import 'package:alea_flow/alea_flow.dart';
import 'package:test/test.dart';

void main() {
  group('ContextPacket', () {
    final fixed = DateTime.utc(2026, 5, 23, 10);
    final exp = fixed.add(const Duration(minutes: 5));

    ContextPacket samplePacket() => ContextPacket(
      hash: 'deadbeef',
      sources: const [SourceFingerprint(path: '.alea.yaml', md5: 'cafef00d')],
      body: '# ALEA Context Packet — sample\n\nHello.\n',
      generatedAt: fixed,
      expiresAt: exp,
    );

    test(
      'render produces YAML front matter + body separated by blank line',
      () {
        final rendered = samplePacket().render();
        expect(rendered, startsWith('---\n'));
        expect(rendered, contains('hash: deadbeef'));
        expect(rendered, contains('path: .alea.yaml'));
        expect(rendered, contains('md5: cafef00d'));
        expect(rendered, contains('---\n\n# ALEA Context Packet'));
      },
    );

    test('parse round-trip preserves every front-matter field', () {
      final original = samplePacket();
      final parsed = ContextPacket.parse(original.render());
      expect(parsed.schemaVersion, ContextPacket.currentSchemaVersion);
      expect(parsed.hash, original.hash);
      expect(parsed.sources, hasLength(1));
      expect(parsed.sources.single.path, '.alea.yaml');
      expect(parsed.sources.single.md5, 'cafef00d');
      expect(
        parsed.generatedAt.toIso8601String(),
        original.generatedAt.toIso8601String(),
      );
      expect(
        parsed.expiresAt.toIso8601String(),
        original.expiresAt.toIso8601String(),
      );
      // Body is preserved including its trailing newline.
      expect(parsed.body, original.body);
    });

    test('parse rejects missing opening delimiter', () {
      expect(
        () => ContextPacket.parse('no front matter here'),
        throwsFormatException,
      );
    });

    test('parse rejects missing required field', () {
      expect(
        () => ContextPacket.parse('---\nhash: x\n---\n\nbody'),
        throwsFormatException,
      );
    });

    test('isExpired flips after expiresAt', () {
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      final future = DateTime.now().toUtc().add(const Duration(hours: 1));
      expect(
        ContextPacket(
          hash: 'a',
          sources: const [],
          body: '',
          generatedAt: past,
          expiresAt: past,
        ).isExpired,
        isTrue,
      );
      expect(
        ContextPacket(
          hash: 'a',
          sources: const [],
          body: '',
          generatedAt: past,
          expiresAt: future,
        ).isExpired,
        isFalse,
      );
    });

    test('toJson is JSON-safe and includes body_length, not body', () {
      final json = samplePacket().toJson();
      expect(json['hash'], 'deadbeef');
      expect(json['body_length'], isA<int>());
      expect(
        json.containsKey('body'),
        isFalse,
        reason:
            'body is intentionally omitted to keep toJson() cheap '
            'for journal events',
      );
    });
  });

  group('SourceFingerprint', () {
    test('JSON round-trip', () {
      const sf = SourceFingerprint(path: '.alea.yaml', md5: 'abc');
      final back = SourceFingerprint.fromJson(sf.toJson());
      expect(back.path, sf.path);
      expect(back.md5, sf.md5);
    });

    test('fromJson rejects non-string fields', () {
      expect(
        () => SourceFingerprint.fromJson(const {'path': 1, 'md5': 'x'}),
        throwsFormatException,
      );
    });
  });
}
