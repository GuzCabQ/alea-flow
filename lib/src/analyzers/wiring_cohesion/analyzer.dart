// ALEA — WiringCohesionAnalyzer.
//
// Verifies that every class whose name matches a configured pattern is
// registered (referenced inside a specific call) in a manifest file declared
// by `architecture.wiring.rules[]`. The analyzer ships no presets — it does
// not know that Riverpod uses `registerSingleton`, that GetX uses `Get.put`,
// or that go_router uses `GoRoute`. The consumer's `.alea.yaml` declares all
// of it.
//
// Example consumer config:
//
//   architecture:
//     wiring:
//       rules:
//         - name: service_registration
//           class_pattern: "*Service"
//           manifest_file: lib/src/injector.dart
//           registration_call: registerSingleton
//         - name: screen_route
//           class_pattern: "*Screen"
//           manifest_file: lib/src/config/routes.dart
//           registration_call: GoRoute
//
// Same analyzer, different config → same behaviour for any state-management
// stack. Replacing `registerSingleton` with `Get.put` (and `GoRoute` with
// `GetPage`) makes the rules apply to a GetX project without touching the
// analyzer source.
//
// AST-based: candidate classes are discovered via `ClassDeclaration` nodes;
// registrations are detected by walking method invocations and constructor
// calls inside the manifest file, then collecting any PascalCase identifier
// that appears as part of those invocations' argument trees.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/file_system/file_system.dart' as analyzer_fs;
import 'package:path/path.dart' as p;

import '../../contracts/analyzer.dart';
import '../../contracts/project_config.dart';
import '../../contracts/run_journal.dart';

class WiringCohesionAnalyzer extends Analyzer {
  @override
  String get name => 'wiring_cohesion';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final wiring = ctx.config.architecture.wiring;
    if (wiring == null || wiring.rules.isEmpty) return const [];

    final issues = <AnalysisIssue>[];
    for (final rule in wiring.rules) {
      issues.addAll(await _evaluateRule(ctx, rule));
    }
    return issues;
  }

  Future<List<AnalysisIssue>> _evaluateRule(
    AnalyzerContext ctx,
    WiringRule rule,
  ) async {
    final manifestAbsolute = p.join(ctx.projectRoot, rule.manifestFile);
    if (!File(manifestAbsolute).existsSync()) {
      return [
        AnalysisIssue(
          file: rule.manifestFile,
          rule: 'Wiring cohesion: manifest "${rule.manifestFile}" is missing',
          ruleId: 'wiring_cohesion/${rule.name}/manifest_missing',
          message:
              'The wiring rule "${rule.name}" expects the manifest at '
              '${rule.manifestFile}, but the file does not exist.',
          suggestedFix:
              'Create ${rule.manifestFile} and declare each ${rule.classPattern} '
              'via ${rule.registrationCall}(...).',
          severity: Severity.blocker,
        ),
      ];
    }

    final scanPaths = _resolveScanPaths(ctx, rule, manifestAbsolute);
    final candidates = await _findCandidateClasses(
      scanPaths,
      rule.classPattern,
      excludePath: manifestAbsolute,
    );
    final registered = _findRegisteredClasses(
      manifestAbsolute,
      rule.registrationCall,
    );
    // If the manifest could not be read, skip reporting issues for this rule
    // rather than treating every candidate as unregistered.
    if (registered == null) return const [];

    await ctx.journal?.record(
      JournalEvent(
        source: 'analyzer:$name',
        kind: JournalEventKind.check,
        payload: {
          'rule': rule.name,
          'class_pattern': rule.classPattern,
          'manifest_file': rule.manifestFile,
          'registration_call': rule.registrationCall,
          'candidates': candidates.length,
          'registered': registered.length,
        },
      ),
    );

    final issues = <AnalysisIssue>[];
    for (final candidate in candidates) {
      if (registered.contains(candidate.className)) continue;
      issues.add(
        AnalysisIssue(
          file: candidate.relativePath,
          line: candidate.line,
          rule:
              'Wiring cohesion: ${candidate.className} matches '
              '"${rule.classPattern}" but is not registered',
          ruleId: 'wiring_cohesion/${rule.name}/missing_registration',
          message:
              '${candidate.className} (rule "${rule.name}") should appear inside '
              'a ${rule.registrationCall}(...) call in ${rule.manifestFile}, '
              'but no such reference was found.',
          suggestedFix:
              'Add ${rule.registrationCall}(${candidate.className}(...)) — or '
              'the equivalent shape used by the rest of ${rule.manifestFile} — '
              'so the wiring is complete.',
          severity: Severity.blocker,
        ),
      );
    }
    return issues;
  }

  // ── Candidate discovery ─────────────────────────────────────────────────

  Future<List<_Candidate>> _findCandidateClasses(
    List<String> scanPaths,
    String pattern, {
    required String excludePath,
  }) async {
    final out = <_Candidate>[];
    for (final dirPath in scanPaths) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        if (p.equals(entity.path, excludePath)) continue;
        final ParseStringResult parsed;
        try {
          parsed = parseFile(
            path: entity.path,
            featureSet: FeatureSet.latestLanguageVersion(),
            throwIfDiagnostics: false,
          );
        } on FileSystemException {
          continue; // unreadable file — skip, like every other analyzer
        } on analyzer_fs.FileSystemException {
          continue;
        }
        for (final decl in parsed.unit.declarations) {
          if (decl is! ClassDeclaration) continue;
          final className = decl.namePart.typeName.lexeme;
          if (className.startsWith('_')) continue;
          if (!_matchesPattern(className, pattern)) continue;
          final line = parsed.lineInfo.getLocation(decl.offset).lineNumber;
          out.add(
            _Candidate(
              className: className,
              absolutePath: entity.path,
              relativePath: p.relative(
                entity.path,
                from: _commonRoot(scanPaths),
              ),
              line: line,
            ),
          );
        }
      }
    }
    return out;
  }

  String _commonRoot(List<String> paths) {
    if (paths.isEmpty) return '/';
    if (paths.length == 1) return paths.first;
    // Walk back from one of the paths until everyone agrees. Cheap.
    var candidate = paths.first;
    while (candidate.isNotEmpty) {
      if (paths.every((p) => p.startsWith(candidate))) return candidate;
      candidate = candidate.substring(0, candidate.length - 1);
    }
    return '/';
  }

  // ── Registration discovery ──────────────────────────────────────────────

  Set<String>? _findRegisteredClasses(String manifestAbsolute, String call) {
    final ParseStringResult parsed;
    try {
      parsed = parseFile(
        path: manifestAbsolute,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
    } on FileSystemException {
      return null;
    } on analyzer_fs.FileSystemException {
      return null;
    }
    final visitor = _RegistrationCollector(call);
    parsed.unit.accept(visitor);
    return visitor.registered;
  }

  // ── Path resolution ─────────────────────────────────────────────────────

  List<String> _resolveScanPaths(
    AnalyzerContext ctx,
    WiringRule rule,
    String manifestAbsolute,
  ) {
    final declared = rule.scanPaths.isNotEmpty
        ? rule.scanPaths
        : <String>[
            for (final layer in ctx.config.architecture.layers.values)
              ...layer.paths,
          ];
    final out = <String>[];
    for (final rel in declared) {
      final abs = p.isAbsolute(rel) ? rel : p.join(ctx.projectRoot, rel);
      out.add(p.normalize(abs));
    }
    return out;
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────

bool _matchesPattern(String className, String pattern) {
  if (pattern == '*') return true;
  final startsWildcard = pattern.startsWith('*');
  final endsWildcard = pattern.endsWith('*');
  final inner = pattern.replaceAll('*', '');
  if (inner.isEmpty) return startsWildcard || endsWildcard;
  if (startsWildcard && endsWildcard) return className.contains(inner);
  if (startsWildcard) return className.endsWith(inner);
  if (endsWildcard) return className.startsWith(inner);
  return className == pattern;
}

class _Candidate {
  final String className;
  final String absolutePath;
  final String relativePath;
  final int line;
  const _Candidate({
    required this.className,
    required this.absolutePath,
    required this.relativePath,
    required this.line,
  });
}

/// Walks the manifest AST and collects every PascalCase identifier that
/// appears inside an invocation of [_callName].
///
/// Supported call shapes:
///   - Bare method: `registerSingleton(Foo())` → matches `methodName=='registerSingleton'`
///   - Dotted target: `Get.put(Foo())` → matches `'<target>.<methodName>'`
///   - Constructor: `GoRoute(builder: (_, __) => FooScreen())` → matches
///     `constructorName.type.name2 == 'GoRoute'`.
class _RegistrationCollector extends RecursiveAstVisitor<void> {
  _RegistrationCollector(this.callName);

  final String callName;
  final Set<String> registered = {};

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    if (type == callName) {
      final classes = _ClassRefCollector();
      node.argumentList.accept(classes);
      registered.addAll(classes.classes);
      // Also count type arguments: GoRoute<FooScreen>(...) → 'FooScreen'.
      final typeArgs = node.constructorName.type.typeArguments;
      if (typeArgs != null) {
        for (final ta in typeArgs.arguments) {
          if (ta is NamedType) registered.add(ta.name.lexeme);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    final target = node.target;
    final fullCall = target is SimpleIdentifier
        ? '${target.name}.$method'
        : method;
    if (fullCall == callName || method == callName) {
      final classes = _ClassRefCollector();
      node.argumentList.accept(classes);
      registered.addAll(classes.classes);
      // Type arguments: registerSingleton<FooRepository>(...) → 'FooRepository'.
      final typeArgs = node.typeArguments;
      if (typeArgs != null) {
        for (final ta in typeArgs.arguments) {
          if (ta is NamedType) registered.add(ta.name.lexeme);
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}

/// Collects every PascalCase identifier visited inside a subtree. Used by
/// [_RegistrationCollector] to harvest class names from a single call's
/// argument list.
class _ClassRefCollector extends RecursiveAstVisitor<void> {
  final Set<String> classes = {};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    if (_isPascalCase(name)) classes.add(name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    classes.add(node.name.lexeme);
    super.visitNamedType(node);
  }

  bool _isPascalCase(String s) {
    if (s.isEmpty) return false;
    final c = s.codeUnitAt(0);
    return c >= 0x41 && c <= 0x5A;
  }
}
