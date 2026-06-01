// Smoke tests for `aflow init`. Verifies both templates produce the expected
// file tree, respect --dry-run, refuse overwrites without --force, and
// validate package names.

import 'dart:io';

import 'package:alea_flow/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('aflow init', () {
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

  group('aflow init --template config', () {
    void writePubspec(Directory dir, String content) {
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(content);
    }

    test('generates .alea.yaml from pubspec + filesystem scan', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_cfg_full_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      writePubspec(tmp, '''
name: my_app
environment:
  sdk: ^3.0.0
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.0.0
  go_router: ^12.0.0
''');
      Directory(p.join(tmp.path, 'lib/src/domain')).createSync(recursive: true);
      Directory(
        p.join(tmp.path, 'lib/src/infrastructure'),
      ).createSync(recursive: true);
      Directory(
        p.join(tmp.path, 'lib/src/presentation'),
      ).createSync(recursive: true);
      Directory(p.join(tmp.path, 'lib/src/theme')).createSync(recursive: true);

      final code = await AleaCliRunner().run([
        'init',
        '--output',
        tmp.path,
        '--template',
        'config',
      ]);
      expect(code, 0);

      final yaml = File(p.join(tmp.path, '.alea.yaml')).readAsStringSync();
      expect(yaml, contains('package_name: my_app'));
      expect(yaml, contains('style: riverpod_manual'));
      expect(yaml, contains('package: go_router'));
      expect(yaml, contains('paths: [lib/src/domain/]'));
      // No actual PLACEHOLDER blocks — the header's marker legend always
      // contains the string `# PLACEHOLDER`, so we discriminate on the
      // body phrasing that only real placeholders carry.
      expect(
        yaml,
        isNot(contains('PLACEHOLDER — could not auto-detect a')),
        reason: 'all relevant fields detected; no placeholder bodies expected',
      );
      expect(
        yaml,
        isNot(contains('PLACEHOLDER — no known')),
        reason: 'all relevant deps detected; no placeholder bodies expected',
      );
    });

    test('emits PLACEHOLDERs when nothing is detected', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_cfg_empty_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      writePubspec(tmp, '''
name: bare_pkg
environment:
  sdk: ^3.0.0
''');

      final code = await AleaCliRunner().run([
        'init',
        '--output',
        tmp.path,
        '--template',
        'config',
      ]);
      expect(code, 0);

      final yaml = File(p.join(tmp.path, '.alea.yaml')).readAsStringSync();
      expect(yaml, contains('# PLACEHOLDER'));
      expect(yaml, contains('package_name: bare_pkg'));
      // No flutter dep → dart_test
      expect(yaml, contains('framework: dart_test'));
      expect(yaml, contains('dart format ., dart analyze, dart test'));
    });

    test('exits 1 when pubspec.yaml is missing', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_cfg_nopub_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final code = await AleaCliRunner().run([
        'init',
        '--output',
        tmp.path,
        '--template',
        'config',
      ]);
      expect(code, 1);
      expect(File(p.join(tmp.path, '.alea.yaml')).existsSync(), isFalse);
    });

    test('exits 1 when pubspec.yaml is malformed', () async {
      final tmp = Directory.systemTemp.createTempSync(
        'alea_init_cfg_malformed_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      File(
        p.join(tmp.path, 'pubspec.yaml'),
      ).writeAsStringSync('this is: not: a: valid: { mapping');

      final code = await AleaCliRunner().run([
        'init',
        '--output',
        tmp.path,
        '--template',
        'config',
      ]);
      expect(code, 1);
    });

    test(
      'exits 2 when .alea.yaml already exists and --force is not set',
      () async {
        final tmp = Directory.systemTemp.createTempSync(
          'alea_init_cfg_exists_',
        );
        addTearDown(() => tmp.deleteSync(recursive: true));
        writePubspec(tmp, 'name: my_app\n');
        File(
          p.join(tmp.path, '.alea.yaml'),
        ).writeAsStringSync('# do not touch\n');

        final code = await AleaCliRunner().run([
          'init',
          '--output',
          tmp.path,
          '--template',
          'config',
        ]);
        expect(code, 2);
        expect(
          File(p.join(tmp.path, '.alea.yaml')).readAsStringSync(),
          '# do not touch\n',
        );
      },
    );

    test('--force overwrites existing .alea.yaml', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_cfg_force_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      writePubspec(tmp, 'name: my_app\n');
      File(p.join(tmp.path, '.alea.yaml')).writeAsStringSync('# old\n');

      final code = await AleaCliRunner().run([
        'init',
        '--output',
        tmp.path,
        '--template',
        'config',
        '--force',
      ]);
      expect(code, 0);
      final yaml = File(p.join(tmp.path, '.alea.yaml')).readAsStringSync();
      expect(yaml, contains('package_name: my_app'));
      expect(yaml, isNot(contains('# old')));
    });

    test('--dry-run writes nothing but exits 0', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_cfg_dry_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      writePubspec(tmp, 'name: my_app\n');

      final code = await AleaCliRunner().run([
        'init',
        '--output',
        tmp.path,
        '--template',
        'config',
        '--dry-run',
      ]);
      expect(code, 0);
      expect(File(p.join(tmp.path, '.alea.yaml')).existsSync(), isFalse);
    });

    test('exits 64 when pubspec name is invalid', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_cfg_badname_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      writePubspec(tmp, 'name: Bad-Name-Caps\n');

      final code = await AleaCliRunner().run([
        'init',
        '--output',
        tmp.path,
        '--template',
        'config',
      ]);
      expect(code, 64);
      expect(File(p.join(tmp.path, '.alea.yaml')).existsSync(), isFalse);
    });

    test('positional arg is ignored under --template config', () async {
      final tmp = Directory.systemTemp.createTempSync('alea_init_cfg_pos_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      writePubspec(tmp, 'name: real_name\n');

      final code = await AleaCliRunner().run([
        'init',
        'ignored_positional',
        '--output',
        tmp.path,
        '--template',
        'config',
      ]);
      expect(code, 0);
      final yaml = File(p.join(tmp.path, '.alea.yaml')).readAsStringSync();
      expect(yaml, contains('package_name: real_name'));
      expect(yaml, isNot(contains('ignored_positional')));
    });

    test(
      'init --no-install-commands does not install even with --platform',
      () async {
        final tmp = Directory.systemTemp.createTempSync('aflow_init_no_');
        addTearDown(() => tmp.deleteSync(recursive: true));
        File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync(
          'name: demo\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
        );
        final code = await AleaCliRunner().run([
          'init',
          '--output',
          tmp.path,
          '--template',
          'config',
          '--platform',
          'claude',
          '--no-install-commands',
        ]);
        expect(code, 0);
        expect(Directory(p.join(tmp.path, '.claude')).existsSync(), isFalse);
      },
    );

    test('init without --platform installs nothing', () async {
      final tmp = Directory.systemTemp.createTempSync('aflow_init_none_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync(
        'name: demo\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
      );
      final code = await AleaCliRunner().run([
        'init',
        '--output',
        tmp.path,
        '--template',
        'config',
      ]);
      expect(code, 0);
      expect(Directory(p.join(tmp.path, '.claude')).existsSync(), isFalse);
    });

    test('init --platform claude installs commands after config', () async {
      final tmp = Directory.systemTemp.createTempSync('aflow_init_platform_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync(
        'name: demo\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
      );

      final code = await AleaCliRunner().run([
        'init',
        '--output',
        tmp.path,
        '--template',
        'config',
        '--platform',
        'claude',
      ]);

      expect(code, 0);
      expect(
        Directory(p.join(tmp.path, '.claude', 'commands')).existsSync(),
        isTrue,
      );
    });
  });
}
