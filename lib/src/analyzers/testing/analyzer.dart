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

    for (final filePath in ctx.filePaths) {
      final testPath = _expectedTestPath(filePath, layerPaths, ctx.projectRoot);
      if (testPath == null) continue; // outside layer paths

      if (!File(testPath).existsSync()) {
        issues.add(
          AnalysisIssue(
            file: filePath,
            line: 1,
            rule: 'missing_test_file',
            ruleId: 'testing/missing_test',
            message:
                'No test file found. Expected: '
                '${p.relative(testPath, from: ctx.projectRoot)}',
            severity: Severity.critical,
          ),
        );
        continue;
      }

      if (preferFakes) {
        issues.addAll(_checkMockUsage(testPath));
      }
    }
    return issues;
  }

  /// Map a layer source file to its expected test path.
  /// `<layerPath>/.../foo.dart` → `<projectRoot>/test/.../foo_test.dart`
  /// where the path relative to the matching layerPath is preserved.
  String? _expectedTestPath(
    String filePath,
    List<String> layerPaths,
    String projectRoot,
  ) {
    final normalized = filePath.replaceAll(r'\', '/');
    for (final layerPath in layerPaths) {
      final marker = layerPath.endsWith('/') ? layerPath : '$layerPath/';
      final idx = normalized.indexOf(marker);
      if (idx == -1) continue;
      final relPath = normalized.substring(idx + marker.length);
      final dir = p.dirname(relPath);
      final base = p.basenameWithoutExtension(relPath);
      final testRel = p.join(dir == '.' ? '' : dir, '${base}_test.dart');
      return p.join(projectRoot, 'test', testRel);
    }
    return null;
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
