import 'dart:io';

import 'package:alea_flow/src/cli/init/layer_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('LayerScanner.scan', () {
    test('detects canonical lib/src/<layer>/ paths when present', () {
      final tmp = Directory.systemTemp.createTempSync('layer_scan_canon_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      Directory(p.join(tmp.path, 'lib/src/domain')).createSync(recursive: true);
      Directory(
        p.join(tmp.path, 'lib/src/infrastructure'),
      ).createSync(recursive: true);
      Directory(
        p.join(tmp.path, 'lib/src/presentation'),
      ).createSync(recursive: true);
      Directory(p.join(tmp.path, 'lib/src/theme')).createSync(recursive: true);

      final paths = const LayerScanner().scan(tmp.path);
      expect(paths.domainPath, 'lib/src/domain/');
      expect(paths.infrastructurePath, 'lib/src/infrastructure/');
      expect(paths.presentationPath, 'lib/src/presentation/');
      expect(paths.themePath, 'lib/src/theme/');
      expect(paths.allLayersDetected, isTrue);
    });

    test('falls back to lib/<layer>/ when src/ variant is absent', () {
      final tmp = Directory.systemTemp.createTempSync('layer_scan_flat_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      Directory(p.join(tmp.path, 'lib/domain')).createSync(recursive: true);
      Directory(
        p.join(tmp.path, 'lib/presentation'),
      ).createSync(recursive: true);

      final paths = const LayerScanner().scan(tmp.path);
      expect(paths.domainPath, 'lib/domain/');
      expect(paths.presentationPath, 'lib/presentation/');
      expect(paths.infrastructurePath, isNull);
      expect(paths.themePath, isNull);
      expect(paths.allLayersDetected, isFalse);
    });

    test('prefers lib/src/<layer>/ over lib/<layer>/ when both exist', () {
      final tmp = Directory.systemTemp.createTempSync('layer_scan_both_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      Directory(p.join(tmp.path, 'lib/src/domain')).createSync(recursive: true);
      Directory(p.join(tmp.path, 'lib/domain')).createSync(recursive: true);

      final paths = const LayerScanner().scan(tmp.path);
      expect(paths.domainPath, 'lib/src/domain/');
    });

    test(
      'does NOT detect non-canonical names (data, dominio, ui, features)',
      () {
        final tmp = Directory.systemTemp.createTempSync('layer_scan_noncanon_');
        addTearDown(() => tmp.deleteSync(recursive: true));

        // These are common but NOT in the v1 detection scope.
        Directory(p.join(tmp.path, 'lib/data')).createSync(recursive: true);
        Directory(p.join(tmp.path, 'lib/dominio')).createSync(recursive: true);
        Directory(p.join(tmp.path, 'lib/src/ui')).createSync(recursive: true);
        Directory(
          p.join(tmp.path, 'lib/features/auth/domain'),
        ).createSync(recursive: true);

        final paths = const LayerScanner().scan(tmp.path);
        expect(
          paths.domainPath,
          isNull,
          reason: 'lib/features/auth/domain should NOT be detected in v1',
        );
        expect(
          paths.infrastructurePath,
          isNull,
          reason: 'lib/data should NOT be detected as infrastructure',
        );
        expect(
          paths.presentationPath,
          isNull,
          reason: 'lib/src/ui should NOT be detected as presentation',
        );
      },
    );

    test('returns all-null LayerPaths for empty project root', () {
      final tmp = Directory.systemTemp.createTempSync('layer_scan_empty_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final paths = const LayerScanner().scan(tmp.path);
      expect(paths.domainPath, isNull);
      expect(paths.infrastructurePath, isNull);
      expect(paths.presentationPath, isNull);
      expect(paths.themePath, isNull);
      expect(paths.allLayersDetected, isFalse);
    });

    test('does not throw on non-existent project root', () {
      // Behavior: returns all-null, never raises. Callers can render
      // placeholders uniformly.
      final paths = const LayerScanner().scan('/definitely/not/a/path/xyz');
      expect(paths.domainPath, isNull);
      expect(paths.allLayersDetected, isFalse);
    });
  });
}
