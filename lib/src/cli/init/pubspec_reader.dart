// ALEA — pubspec.yaml reader for `aflow init --template config`.
//
// Pure function: given a path to a pubspec.yaml, returns a [PubspecData]
// with the fields needed to seed a `.alea.yaml`. Detection of state
// management and routing is intentionally conservative — only canonical
// English package names that map unambiguously to one option.
//
// Detection scope (v1):
//   - state_management: flutter_riverpod | riverpod → 'riverpod_manual',
//     flutter_bloc → 'bloc', provider → 'provider', get → 'getx'.
//   - routing: go_router → 'go_router', auto_route → 'auto_route'.
//   - is_flutter_project: presence of the `flutter` SDK dep.
//
// Out of scope (handled later, see docs/proposals/0001):
//   - Disambiguating multiple state managers coexisting.
//   - Detecting custom forks or aliased deps.
//   - Inferring style from imports rather than from pubspec.

import 'dart:io';

import 'package:yaml/yaml.dart';

class PubspecData {
  const PubspecData({
    required this.packageName,
    required this.isFlutterProject,
    required this.stateManagementStyle,
    required this.stateManagementOrigin,
    required this.routingPackage,
    required this.routingOrigin,
  });

  /// `name:` field of the pubspec. Required; an empty value is a parse error.
  final String packageName;

  /// True if the pubspec declares `flutter` in `dependencies` or
  /// `environment.flutter`. Drives defaults for `testing.framework` and
  /// whether the generated config assumes Flutter widgets exist.
  final bool isFlutterProject;

  /// One of: `riverpod_manual`, `bloc`, `provider`, `getx`, or `null` if no
  /// known state-management dependency was detected.
  final String? stateManagementStyle;

  /// Which pubspec key implied [stateManagementStyle]. Used to render the
  /// `# inferred from <dep>` comment in the generated YAML. `null` when
  /// [stateManagementStyle] is `null`.
  final String? stateManagementOrigin;

  /// One of: `go_router`, `auto_route`, or `null` if no known routing
  /// dependency was detected.
  final String? routingPackage;

  /// Which pubspec key implied [routingPackage]. `null` when
  /// [routingPackage] is `null`.
  final String? routingOrigin;
}

class PubspecReaderException implements Exception {
  const PubspecReaderException(this.message);
  final String message;
  @override
  String toString() => 'PubspecReaderException: $message';
}

class PubspecReader {
  const PubspecReader();

  /// Reads and parses [pubspecPath]. Throws [PubspecReaderException] if the
  /// file is missing, unreadable, malformed, or lacks a `name:` field.
  PubspecData read(String pubspecPath) {
    final file = File(pubspecPath);
    if (!file.existsSync()) {
      throw PubspecReaderException(
        'pubspec.yaml not found at "$pubspecPath". '
        '`aflow init --template config` must be run inside a Flutter or Dart '
        'project (a directory containing pubspec.yaml).',
      );
    }
    final raw = file.readAsStringSync();
    return parse(raw);
  }

  /// Parses raw YAML content. Exposed separately so callers (and tests) can
  /// feed strings without touching the filesystem.
  PubspecData parse(String yamlContent) {
    final dynamic doc;
    try {
      doc = loadYaml(yamlContent);
    } catch (e) {
      throw PubspecReaderException('Failed to parse pubspec.yaml: $e');
    }
    if (doc is! YamlMap) {
      throw PubspecReaderException(
        'pubspec.yaml root must be a map, got ${doc.runtimeType}.',
      );
    }

    final name = doc['name'];
    if (name is! String || name.isEmpty) {
      throw PubspecReaderException(
        'pubspec.yaml is missing a `name:` field or it is empty.',
      );
    }

    final dependencies = _stringKeyedMap(doc['dependencies']);
    final environment = _stringKeyedMap(doc['environment']);

    final isFlutterProject =
        dependencies.containsKey('flutter') ||
        environment.containsKey('flutter');

    final stateMgmt = _detectStateManagement(dependencies);
    final routing = _detectRouting(dependencies);

    return PubspecData(
      packageName: name,
      isFlutterProject: isFlutterProject,
      stateManagementStyle: stateMgmt?.style,
      stateManagementOrigin: stateMgmt?.origin,
      routingPackage: routing?.package,
      routingOrigin: routing?.origin,
    );
  }

  _Detected? _detectStateManagement(Map<String, dynamic> deps) {
    // Order matters: flutter_riverpod is checked before plain riverpod to
    // capture the more specific dependency when both are present.
    if (deps.containsKey('flutter_riverpod')) {
      return const _Detected('riverpod_manual', 'flutter_riverpod');
    }
    if (deps.containsKey('riverpod')) {
      return const _Detected('riverpod_manual', 'riverpod');
    }
    if (deps.containsKey('flutter_bloc')) {
      return const _Detected('bloc', 'flutter_bloc');
    }
    if (deps.containsKey('bloc')) {
      return const _Detected('bloc', 'bloc');
    }
    if (deps.containsKey('provider')) {
      return const _Detected('provider', 'provider');
    }
    if (deps.containsKey('get')) {
      return const _Detected('getx', 'get');
    }
    return null;
  }

  _Detected? _detectRouting(Map<String, dynamic> deps) {
    if (deps.containsKey('go_router')) {
      return const _Detected('go_router', 'go_router');
    }
    if (deps.containsKey('auto_route')) {
      return const _Detected('auto_route', 'auto_route');
    }
    return null;
  }

  Map<String, dynamic> _stringKeyedMap(dynamic node) {
    if (node is YamlMap) {
      return node.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {};
  }
}

class _Detected {
  const _Detected(this.style, this.origin);
  final String style;
  final String origin;

  // Aliases for routing case (same shape, different accessor name in callers).
  String get package => style;
}
