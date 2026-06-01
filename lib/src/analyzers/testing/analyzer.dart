// ALEA — Testing Convention Validator.
//
// Two rules:
//   - Every source file under a layer path must have a corresponding test file.
//   - Test files must not import mockito/mocktail when
//     `config.testing.prefer_fakes_over_mocks` is true (the default).
//
// Both rules read paths and conventions from [ProjectConfig]; no hardcoded
// `lib/src/` or `test/` paths.
//
// Ported from tools/pipeline/lib/src/analyzers/testing_validator.dart.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../../contracts/analyzer.dart';

class TestingAnalyzer extends Analyzer {
  @override
  String get name => 'testing';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final issues = <AnalysisIssue>[];
    final layerPaths = ctx.config.architecture.layers.values
        .expand((l) => l.paths)
        .map((p) => p.replaceAll(r'\', '/'))
        .toList();
    final preferFakes = ctx.config.testing.preferFakesOverMocks;
    final missingSeverity = _severityFromName(
      ctx.config.testing.missingTestSeverity,
    );

    for (final filePath in ctx.filePaths) {
      final candidates = _candidateTestPaths(
        filePath,
        layerPaths,
        ctx.projectRoot,
      );
      if (candidates.isEmpty) continue; // outside layer paths
      if (_exemptFromTestRequirement(filePath)) continue; // nothing to test

      String? existing;
      for (final candidate in candidates) {
        if (File(candidate).existsSync()) {
          existing = candidate;
          break;
        }
      }

      if (existing == null) {
        issues.add(
          AnalysisIssue(
            file: filePath,
            line: 1,
            rule: 'missing_test_file',
            ruleId: 'testing/missing_test',
            message:
                'No test file found. Expected: '
                '${p.relative(candidates.first, from: ctx.projectRoot)}',
            severity: missingSeverity,
          ),
        );
        continue;
      }

      if (preferFakes) {
        issues.addAll(_checkMockUsage(existing));
      }
    }
    return issues;
  }

  /// Candidate test paths for a layer source file, most-standard first. The
  /// rule is satisfied if a test exists at ANY of them; the first is what the
  /// "missing" message points the consumer to.
  ///
  /// 1. **lib→test mirror** (standard Dart convention): the project-relative
  ///    path with its leading `lib/` segment replaced by `test/`.
  ///      `lib/src/domain/x.dart` → `test/src/domain/x_test.dart`
  /// 2. **layer-relative** (legacy ALEA convention, kept for back-compat): the
  ///    path relative to the matching layer, under `test/`.
  ///      `lib/src/domain/x.dart` (layer `lib/src/domain/`) → `test/x_test.dart`
  ///
  /// Returns an empty list when [filePath] is not under any layer path.
  List<String> _candidateTestPaths(
    String filePath,
    List<String> layerPaths,
    String projectRoot,
  ) {
    final normalized = filePath.replaceAll(r'\', '/');

    // In scope only if the file lives under a declared layer path.
    String? layerRelative;
    for (final layerPath in layerPaths) {
      final marker = layerPath.endsWith('/') ? layerPath : '$layerPath/';
      final idx = normalized.indexOf(marker);
      if (idx == -1) continue;
      layerRelative = normalized.substring(idx + marker.length);
      break;
    }
    if (layerRelative == null) return const [];

    final candidates = <String>[];

    // 1. lib→test mirror, derived from the project-root-relative path.
    final rel = p.relative(filePath, from: projectRoot).replaceAll(r'\', '/');
    final segs = p.split(rel);
    if (segs.length > 1 && segs.first == 'lib') {
      final mirror = ['test', ...segs.skip(1)];
      mirror[mirror.length - 1] = _asTestFile(mirror.last);
      candidates.add(p.joinAll([projectRoot, ...mirror]));
    }

    // 2. layer-relative (legacy).
    final dir = p.dirname(layerRelative);
    final base = _asTestFile(p.basename(layerRelative));
    final testRel = dir == '.' ? base : p.join(dir, base);
    candidates.add(p.join(projectRoot, 'test', testRel));

    return candidates;
  }

  String _asTestFile(String fileName) =>
      '${p.basenameWithoutExtension(fileName)}_test.dart';

  /// Maps a [Severity] name from config to the enum. Unknown values fall back
  /// to `major` (advisory) — never crash, and never silently escalate to a
  /// blocking severity the consumer did not ask for.
  Severity _severityFromName(String name) {
    for (final s in Severity.values) {
      if (s.name == name) return s;
    }
    return Severity.major;
  }

  /// Files that legitimately need no test: generated code, and files with no
  /// testable surface (plain enums, constants, pure data classes, barrels).
  /// Conservative — anything that declares a function or a method is NOT
  /// exempt (enhanced enums with methods, models with `toJson`, services…).
  bool _exemptFromTestRequirement(String filePath) {
    const generatedSuffixes = [
      '.g.dart',
      '.freezed.dart',
      '.gr.dart',
      '.config.dart',
      '.mocks.dart',
    ];
    if (generatedSuffixes.any(p.basename(filePath).endsWith)) return true;

    final ParseStringResult parsed;
    try {
      parsed = parseFile(
        path: filePath,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
    } on FileSystemException {
      return false; // can't read → don't exempt
    }
    return !_hasTestableSurface(parsed.unit);
  }

  /// True if the unit declares anything worth a unit test: any function or
  /// method (methods include getters and setters) anywhere in the file.
  /// Constructors and bare fields do not count, so plain enums, constants
  /// files and pure data classes are treated as having nothing to test.
  bool _hasTestableSurface(CompilationUnit unit) {
    final visitor = _TestableSurfaceVisitor();
    unit.accept(visitor);
    return visitor.found;
  }

  List<AnalysisIssue> _checkMockUsage(String testPath) {
    late final ParseStringResult parsed;
    try {
      parsed = parseFile(
        path: testPath,
        featureSet: FeatureSet.latestLanguageVersion(),
      );
    } on FileSystemException {
      return const [];
    }

    for (final directive in parsed.unit.directives) {
      if (directive is! ImportDirective) continue;
      final uri = directive.uri.stringValue ?? '';
      if (uri.startsWith('package:mockito/') ||
          uri.startsWith('package:mocktail/')) {
        final line = parsed.lineInfo.getLocation(directive.offset).lineNumber;
        final pkg = uri.split('/').first.split(':').last;
        return [
          AnalysisIssue(
            file: testPath,
            line: line,
            rule: 'mockito_usage',
            ruleId: 'testing/prefers_fakes',
            message:
                'Test file imports $pkg. Project convention is fakes over '
                'mocks (`config.testing.prefer_fakes_over_mocks: true`). '
                'Convert to `FakeXxxRepository implements XxxRepository` under '
                '`config.testing.fakes_path`.',
            severity: Severity.critical,
          ),
        ];
      }
    }
    return const [];
  }
}

/// Flags the unit as having a testable surface on the first function or method
/// it encounters (anywhere in the tree).
class _TestableSurfaceVisitor extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitMethodDeclaration(MethodDeclaration node) => found = true;

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) => found = true;
}
