// ALEA — filesystem scanner for canonical Clean Architecture layer paths.
//
// Conservative by design (v1): only matches canonical English names in two
// common locations (`lib/src/<layer>/` and `lib/<layer>/`). Anything else —
// `data/` instead of `infrastructure/`, Spanish names, feature-first
// (`lib/features/<x>/<layer>/`), `ui/` instead of `presentation/`, etc. —
// returns `null` for that layer so the generator emits an explicit
// placeholder with editing instructions.
//
// Real multi-variant detection is deferred to Item A of
// docs/proposals/0001-adoption-flow-overhaul.md (Diagnostics layer).

import 'dart:io';

import 'package:path/path.dart' as p;

class LayerPaths {
  const LayerPaths({
    required this.domainPath,
    required this.infrastructurePath,
    required this.presentationPath,
    required this.themePath,
  });

  /// Detected `domain` layer path relative to the project root, or `null` if
  /// no canonical folder was found.
  final String? domainPath;

  /// Detected `infrastructure` layer path, or `null`.
  final String? infrastructurePath;

  /// Detected `presentation` layer path, or `null`.
  final String? presentationPath;

  /// Detected `theme` folder path, or `null`.
  final String? themePath;

  /// True when all three architectural layers were detected. Theme presence
  /// is not required for completeness — many projects keep theme elsewhere.
  bool get allLayersDetected =>
      domainPath != null &&
      infrastructurePath != null &&
      presentationPath != null;
}

class LayerScanner {
  const LayerScanner();

  /// Scans [projectRoot] looking for canonical Clean Architecture layer
  /// folders. Returns a [LayerPaths] with `null` entries for whatever was
  /// not found. Never throws on a non-existent project root — returns an
  /// all-null [LayerPaths] instead, so the caller can render placeholders
  /// uniformly.
  LayerPaths scan(String projectRoot) {
    return LayerPaths(
      domainPath: _findFirstExisting(projectRoot, const [
        'lib/src/domain',
        'lib/domain',
      ]),
      infrastructurePath: _findFirstExisting(projectRoot, const [
        'lib/src/infrastructure',
        'lib/infrastructure',
      ]),
      presentationPath: _findFirstExisting(projectRoot, const [
        'lib/src/presentation',
        'lib/presentation',
      ]),
      themePath: _findFirstExisting(projectRoot, const [
        'lib/src/theme',
        'lib/theme',
      ]),
    );
  }

  String? _findFirstExisting(String projectRoot, List<String> candidates) {
    for (final relative in candidates) {
      final abs = p.join(projectRoot, relative);
      if (Directory(abs).existsSync()) {
        return '$relative/';
      }
    }
    return null;
  }
}
