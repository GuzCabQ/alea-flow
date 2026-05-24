// ALEA — Token catalog factory.
//
// Single entry point that resolves a [DesignTokenCatalog] implementation
// from a consumer's [ProjectConfig]. Callers (resolvers, CLI subcommands,
// future analyzers) depend only on this factory and the catalog contract —
// never on a specific adapter class.
//
// Boundary rule (enforced by PackageBoundaryAnalyzer):
//   lib/src/core/ MUST NOT import this file. Core orchestration discovers
//   adapters by name lookup against config, never by static import. Adapter
//   resolution is performed by code that already lives outside the core
//   ring (CLI bin/, analyzers that opt into a catalog explicitly, or
//   consumer code that wires its own pipeline).

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../contracts/design_token_catalog.dart';
import '../../contracts/project_config.dart';
import 'dart_source/adapter.dart';
import 'json/adapter.dart';

/// Build a [DesignTokenCatalog] from [config]. Returns null when the
/// consumer has not declared a `theme.token_catalog` section — callers
/// must tolerate this and fall back to their default behavior.
///
/// [projectRoot] is required to resolve [TokenCatalogConfig.source] against
/// when it is a relative path.
///
/// Throws [ProjectConfigException] if the adapter name is unknown or if
/// the source path resolves outside [projectRoot] but does not exist (the
/// monorepo failure mode — see ADR-0011). Within-project source paths
/// remain lazy: adapter instantiation never reads them, the first I/O
/// happens when a catalog method is awaited.
DesignTokenCatalog? buildTokenCatalog(
  ProjectConfig config, {
  required String projectRoot,
}) {
  final spec = config.theme.tokenCatalog;
  if (spec == null) return null;

  final absoluteSource = p.isAbsolute(spec.source)
      ? p.normalize(spec.source)
      : p.normalize(p.join(projectRoot, spec.source));

  // For sources that point OUTSIDE the consumer's project root (typically
  // a sibling package in a monorepo, per ADR-0011 Part 2), validate
  // existence eagerly. Debugging "directory not found" across package
  // boundaries is significantly harder than within a single package, and
  // the failure mode otherwise surfaces deep inside an adapter method.
  if (!_isWithinProject(absoluteSource, projectRoot) &&
      !Directory(absoluteSource).existsSync() &&
      !File(absoluteSource).existsSync()) {
    throw ProjectConfigException(
      'theme.token_catalog.source resolves outside the project root, '
      'but the target does not exist:\n'
      '  declared:  ${spec.source}\n'
      '  resolved:  $absoluteSource\n'
      '  project:   $projectRoot\n'
      'For monorepo setups (ADR-0011), ensure the sibling package exists '
      'at this relative path before running ALEA.',
      field: 'theme.token_catalog.source',
    );
  }

  switch (spec.adapter.toLowerCase()) {
    case 'dart_source':
      return DartSourceTokenCatalogAdapter.fromConventions(
        absoluteSourcePath: absoluteSource,
        conventions: spec.conventions,
      );
    case 'json':
      return JsonTokenCatalogAdapter.fromConventions(
        absoluteSourcePath: absoluteSource,
        conventions: spec.conventions,
      );
    default:
      throw ProjectConfigException(
        'Unknown theme.token_catalog.adapter "${spec.adapter}". '
        'Supported adapters: dart_source, json.',
        field: 'theme.token_catalog.adapter',
      );
  }
}

/// Names of adapters this factory knows how to build. Useful for help text
/// and for tests that want to assert exhaustiveness.
const List<String> supportedTokenCatalogAdapters = ['dart_source', 'json'];

/// True when [absoluteSource] is the same path as [projectRoot] or sits
/// inside it. Used by the factory to decide whether to eager-validate the
/// source path (external paths) or stay lazy (intra-project paths).
bool _isWithinProject(String absoluteSource, String projectRoot) {
  final rootNorm = p.normalize(projectRoot);
  final sourceNorm = p.normalize(absoluteSource);
  return rootNorm == sourceNorm || p.isWithin(rootNorm, sourceNorm);
}
