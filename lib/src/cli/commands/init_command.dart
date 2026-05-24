// ALEA — `alea init` subcommand.
//
// Bootstraps an ALEA-ready project skeleton in a target directory. Two
// templates are shipped:
//
//   --template project   Adds the ALEA layer to a Flutter app (post
//                        `flutter create`): `.alea.yaml`, layer folders,
//                        a theme tokens stub, a router stub, and a
//                        test/fakes/ folder.
//
//   --template feature   Creates a Dart package for use as a feature in a
//                        modular monorepo. The package's `.alea.yaml`
//                        points its token catalog at an external sibling
//                        package (default: `../design_system/lib/`),
//                        enabling a single design system across features.
//
// Both templates are embedded as Dart strings in this file. Substitution
// uses the existing TemplateEngine (`{{var}}` placeholders).
//
// Idempotency: refuses to overwrite existing files unless --force is set.
// --dry-run prints the plan without writing anything.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../../scaffolding/template_engine.dart';

class InitCommand extends Command<int> {
  InitCommand() {
    argParser
      ..addOption(
        'template',
        abbr: 't',
        allowed: ['project', 'feature'],
        defaultsTo: 'project',
        help: 'Which skeleton to generate.',
      )
      ..addOption(
        'output',
        abbr: 'o',
        defaultsTo: '.',
        help: 'Directory to write into.',
      )
      ..addOption(
        'style',
        abbr: 's',
        allowed: ['riverpod_manual', 'bloc', 'provider', 'getx'],
        defaultsTo: 'riverpod_manual',
        help:
            'state_management.style to embed in the generated '
            '.alea.yaml.',
      )
      ..addOption(
        'design-system-path',
        defaultsTo: '../design_system',
        help:
            'For --template feature: relative path from the feature '
            'package to the sibling design system package. The generated '
            '.alea.yaml will point its token catalog at '
            '<design-system-path>/lib/.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Overwrite files that already exist.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the file plan without writing anything.',
      );
  }

  @override
  String get name => 'init';

  @override
  String get description =>
      'Bootstrap an ALEA-ready skeleton (project or feature package).';

  @override
  String get invocation => 'alea init [<package_name>]';

  @override
  Future<int> run() async {
    final res = argResults!;
    final outputDir = p.canonicalize(res['output'] as String);
    final positional = res.rest;
    final packageName = positional.isNotEmpty
        ? positional.first
        : p.basename(outputDir);

    if (!_isValidPackageName(packageName)) {
      stderr.writeln(
        'Invalid package name: "$packageName". Must match [a-z][a-z0-9_]*',
      );
      return 64;
    }

    final template = res['template'] as String;
    final style = res['style'] as String;
    final designSystemPath = res['design-system-path'] as String;
    final force = res['force'] as bool;
    final dryRun = res['dry-run'] as bool;

    final vars = <String, Object?>{
      'package_name': packageName,
      'style': style,
      'design_system_path': designSystemPath,
    };

    final templates = template == 'feature'
        ? _featureTemplate()
        : _projectTemplate();
    final engine = TemplateEngine();
    final rendered = <String, String>{};
    for (final entry in templates.entries) {
      final renderedPath = engine.render(entry.key, vars);
      rendered[renderedPath] = engine.render(entry.value, vars);
    }

    if (dryRun) {
      stdout.writeln('Template:     $template');
      stdout.writeln('Package name: $packageName');
      stdout.writeln('Output:       $outputDir');
      stdout.writeln('Plan (${rendered.length} file(s)):');
      for (final path in rendered.keys) {
        stdout.writeln('  + $path');
      }
      return 0;
    }

    final created = <String>[];
    final skipped = <String>[];
    for (final entry in rendered.entries) {
      final absPath = p.join(outputDir, entry.key);
      final file = File(absPath);
      if (file.existsSync() && !force) {
        skipped.add(entry.key);
        continue;
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      created.add(entry.key);
    }

    stdout.writeln('Template: $template ($packageName)');
    stdout.writeln('Output:   $outputDir');
    stdout.writeln('Created:  ${created.length} file(s)');
    for (final c in created) {
      stdout.writeln('  + $c');
    }
    if (skipped.isNotEmpty) {
      stdout.writeln(
        'Skipped:  ${skipped.length} (already exist — pass --force to overwrite)',
      );
      for (final s in skipped) {
        stdout.writeln('  ! $s');
      }
    }
    stdout.writeln('');
    stdout.writeln('Next steps:');
    if (template == 'project') {
      stdout.writeln(
        '  1. Review lib/src/theme/tokens.dart and edit '
        'brand colors / typography.',
      );
      stdout.writeln('  2. Run: alea analyze --gate domain');
    } else {
      stdout.writeln(
        '  1. Ensure $designSystemPath/lib/ exists and exposes '
        'an AppColors-like class.',
      );
      stdout.writeln(
        '  2. Add this package to your workspace '
        '(melos.yaml or pubspec workspace).',
      );
      stdout.writeln('  3. Run: alea analyze --project-root $outputDir');
    }
    return 0;
  }

  bool _isValidPackageName(String name) =>
      RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name);

  /// Files for `--template project`. Keys are relative paths (may contain
  /// `{{var}}` placeholders), values are the file contents (also rendered).
  Map<String, String> _projectTemplate() => {
    '.alea.yaml': _projectAleaYaml,
    'lib/src/domain/.gitkeep': '',
    'lib/src/infrastructure/.gitkeep': '',
    'lib/src/presentation/.gitkeep': '',
    'lib/src/theme/tokens.dart': _themeTokensStub,
    'lib/src/theme/app_theme.dart': _appThemeStub,
    'lib/src/app/router.dart': _routerStub,
    'test/fakes/.gitkeep': '',
  };

  /// Files for `--template feature`.
  Map<String, String> _featureTemplate() => {
    'pubspec.yaml': _featurePubspec,
    '.alea.yaml': _featureAleaYaml,
    'lib/{{package_name}}.dart': _featureBarrel,
    'lib/src/domain/.gitkeep': '',
    'lib/src/infrastructure/.gitkeep': '',
    'lib/src/presentation/.gitkeep': '',
    'test/fakes/.gitkeep': '',
  };
}

// ─── Project template ──────────────────────────────────────────────────────

const _projectAleaYaml = '''
config_version: "1.0.0"

project:
  package_name: {{package_name}}
  pubspec_path: pubspec.yaml

architecture:
  layers:
    domain:
      paths: [lib/src/domain/]
      forbid_imports: ["package:flutter/"]
    infrastructure:
      paths: [lib/src/infrastructure/]
      may_import: [domain]
    presentation:
      paths: [lib/src/presentation/]
      may_import: [domain]

state_management:
  style: {{style}}

routing:
  package: go_router
  router_path: lib/src/app/router.dart

theme:
  path: lib/src/theme/
  token_catalog:
    adapter: dart_source
    source: lib/src/theme/

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
  pre_push: [dart format ., dart analyze, flutter test]

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

const _themeTokensStub = '''
import 'package:flutter/material.dart';

/// Brand colors. Edit these to match your design system.
///
/// ALEA's `visual_fidelity` analyzer resolves any `Color(0x...)` literal in
/// the presentation layer against this catalog. Adding a color here makes
/// it "approved"; using a raw hex elsewhere will be flagged.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF2196F3);
  static const Color primaryLight = Color(0xFFBBDEFB);
  static const Color secondary = Color(0xFF03DAC6);
  static const Color tertiary = Color(0xFFFF4081);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F5F5);
  static const Color onSurface = Color(0xFF212121);

  static const Color error = Color(0xFFB00020);
  static const Color success = Color(0xFF388E3C);
}

/// Typography scale. Edit families and sizes to match your design system.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Roboto';

  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 57,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );
}
''';

const _appThemeStub = '''
import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      tertiary: AppColors.tertiary,
      surface: AppColors.surface,
      background: AppColors.background,
      onSurface: AppColors.onSurface,
      error: AppColors.error,
    ),
    textTheme: const TextTheme(
      displayLarge: AppTypography.displayLarge,
      headlineLarge: AppTypography.headlineLarge,
      titleLarge: AppTypography.titleLarge,
      bodyLarge: AppTypography.bodyLarge,
      bodyMedium: AppTypography.bodyMedium,
      labelSmall: AppTypography.labelSmall,
    ),
  );
}
''';

const _routerStub = '''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _HomePlaceholder(),
    ),
  ],
);

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Hello, ALEA')));
}
''';

// ─── Feature template ──────────────────────────────────────────────────────

const _featurePubspec = '''
name: {{package_name}}
description: Feature package generated by `alea init --template feature`.
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  meta: ^1.10.0

dev_dependencies:
  test: ^1.24.0
''';

const _featureAleaYaml = '''
config_version: "1.0.0"

project:
  package_name: {{package_name}}
  pubspec_path: pubspec.yaml

architecture:
  layers:
    domain:
      paths: [lib/src/domain/]
      forbid_imports: ["package:flutter/"]
    infrastructure:
      paths: [lib/src/infrastructure/]
      may_import: [domain]
    presentation:
      paths: [lib/src/presentation/]
      may_import: [domain]

state_management:
  style: {{style}}

routing:
  package: go_router
  router_path: lib/src/{{package_name}}_router.dart

# Token catalog points at the sibling design_system package. This is the
# monorepo pattern from ADR-0011: every feature package consumes the same
# catalog instead of redeclaring tokens.
theme:
  path: {{design_system_path}}/lib/
  token_catalog:
    adapter: dart_source
    source: {{design_system_path}}/lib/

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
  pre_push: [dart format ., dart analyze, dart test]

pipeline:
  default_mode: guided
  modes_available: [guided, semi, auto]
  cost_warn_usd: 3.0
  cost_hard_stop_usd: 5.0

gates:
  domain: [domain]
''';

const _featureBarrel = '''
/// {{package_name}} — public API of this feature package.
///
/// Re-export public-facing types from `src/` here. Keep `src/` internal.
library {{package_name}};
''';
