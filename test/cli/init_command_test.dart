// Smoke tests for `alea init`. Verifies both templates produce the expected
// file tree, respect --dry-run, refuse overwrites without --force, and
// validate package names.

import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('alea init', () {
    test('--template project --dry-run lists files without writing', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_dry_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final code = await AleaCliRunner().run([
        'init',
        'my_app',
        '--output',
        tmp.path,
        '--template',
        'project',
        '--dry-run',
      ]);

      expect(code, 0);
      // Nothing must be written.
      expect(File(p.join(tmp.path, '.alea.yaml')).existsSync(), isFalse);
      expect(
        Directory(p.join(tmp.path, 'lib/src/domain')).existsSync(),
        isFalse,
      );
    });

    test('--template project writes the full skeleton', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_project_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final code = await AleaCliRunner().run([
        'init',
        'my_app',
        '--output',
        tmp.path,
        '--template',
        'project',
      ]);

      expect(code, 0);
      final expected = [
        '.alea.yaml',
        'lib/src/domain/.gitkeep',
        'lib/src/infrastructure/.gitkeep',
        'lib/src/presentation/.gitkeep',
        'lib/src/theme/tokens.dart',
        'lib/src/theme/app_theme.dart',
        'lib/src/app/router.dart',
        'test/fakes/.gitkeep',
      ];
      for (final rel in expected) {
        expect(
          File(p.join(tmp.path, rel)).existsSync(),
          isTrue,
          reason: '$rel should have been created',
        );
      }

      // .alea.yaml must reference the package name we passed.
      final yaml = File(p.join(tmp.path, '.alea.yaml')).readAsStringSync();
      expect(yaml, contains('package_name: my_app'));
      expect(yaml, contains('style: riverpod_manual'));

      // tokens.dart must be valid Dart-looking content with AppColors.
      final tokens = File(
        p.join(tmp.path, 'lib/src/theme/tokens.dart'),
      ).readAsStringSync();
      expect(tokens, contains('class AppColors'));
      expect(tokens, contains('class AppTypography'));
    });

    test(
      '--template feature points token_catalog at sibling design_system',
      () async {
        final tmp = Directory.systemTemp.createTempSync('alea_init_feature_');
        addTearDown(() => tmp.deleteSync(recursive: true));

        final code = await AleaCliRunner().run([
          'init',
          'feature_wallet',
          '--output',
          tmp.path,
          '--template',
          'feature',
        ]);

        expect(code, 0);
        expect(File(p.join(tmp.path, 'pubspec.yaml')).existsSync(), isTrue);
        expect(File(p.join(tmp.path, '.alea.yaml')).existsSync(), isTrue);
        expect(
          File(p.join(tmp.path, 'lib/feature_wallet.dart')).existsSync(),
          isTrue,
        );

        final yaml = File(p.join(tmp.path, '.alea.yaml')).readAsStringSync();
        expect(yaml, contains('package_name: feature_wallet'));
        expect(yaml, contains('source: ../design_system/lib/'));

        final pubspec = File(
          p.join(tmp.path, 'pubspec.yaml'),
        ).readAsStringSync();
        expect(pubspec, contains('name: feature_wallet'));

        final barrel = File(
          p.join(tmp.path, 'lib/feature_wallet.dart'),
        ).readAsStringSync();
        expect(barrel, contains('library feature_wallet;'));
      },
    );

    test('--design-system-path overrides the default sibling path', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_dspath_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final code = await AleaCliRunner().run([
        'init',
        'feature_wallet',
        '--output',
        tmp.path,
        '--template',
        'feature',
        '--design-system-path',
        '../../shared/design_system',
      ]);

      expect(code, 0);
      final yaml = File(p.join(tmp.path, '.alea.yaml')).readAsStringSync();
      expect(yaml, contains('source: ../../shared/design_system/lib/'));
    });

    test('refuses to overwrite an existing file without --force', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_collide_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      // Pre-create one of the files the template would write.
      final preexisting = File(p.join(tmp.path, '.alea.yaml'));
      preexisting.createSync(recursive: true);
      preexisting.writeAsStringSync('# do not overwrite me\n');

      final code = await AleaCliRunner().run([
        'init',
        'my_app',
        '--output',
        tmp.path,
        '--template',
        'project',
      ]);

      expect(code, 0);
      // The pre-existing file must be untouched.
      expect(preexisting.readAsStringSync(), '# do not overwrite me\n');
      // But sibling files should still be created.
      expect(
        File(p.join(tmp.path, 'lib/src/theme/tokens.dart')).existsSync(),
        isTrue,
      );
    });

    test('--force overwrites pre-existing files', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_force_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final preexisting = File(p.join(tmp.path, '.alea.yaml'));
      preexisting.createSync(recursive: true);
      preexisting.writeAsStringSync('# old\n');

      final code = await AleaCliRunner().run([
        'init',
        'my_app',
        '--output',
        tmp.path,
        '--template',
        'project',
        '--force',
      ]);

      expect(code, 0);
      expect(preexisting.readAsStringSync(), contains('package_name: my_app'));
    });

    test('invalid package name yields EX_USAGE (64)', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_badname_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final code = await AleaCliRunner().run([
        'init',
        'My-App-WithCaps',
        '--output',
        tmp.path,
      ]);
      expect(code, 64);
      expect(File(p.join(tmp.path, '.alea.yaml')).existsSync(), isFalse);
    });

    test('positional package name defaults to output dir basename', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_default_');
      // Create a subdir whose name is the implicit package name.
      final pkgDir = Directory(p.join(tmp.path, 'auto_named'))
        ..createSync(recursive: true);
      addTearDown(() => tmp.deleteSync(recursive: true));

      final code = await AleaCliRunner().run([
        'init',
        '--output',
        pkgDir.path,
        '--template',
        'project',
      ]);
      expect(code, 0);
      final yaml = File(p.join(pkgDir.path, '.alea.yaml')).readAsStringSync();
      expect(yaml, contains('package_name: auto_named'));
    });
  });
}
