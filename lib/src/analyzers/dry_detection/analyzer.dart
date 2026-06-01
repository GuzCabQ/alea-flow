// ALEA — DRY (Don't Repeat Yourself) Detection Analyzer.
//
// Ported from tools/pipeline/lib/src/analyzers/dry_detection_analyzer.dart.
// Mechanical port — only contract surface (BaseAnalyzer → Analyzer) changed.

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../../contracts/analyzer.dart';

class DryDetectionAnalyzer extends Analyzer {
  DryDetectionAnalyzer({this.minOccurrences = 3, this.minLength = 10});
  final int minOccurrences;
  final int minLength;

  @override
  String get name => 'dry_detection';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final opts = ctx.config.analyzers.optionsFor(name);
    final minOccurrences =
        (opts['min_occurrences'] as num?)?.toInt() ?? this.minOccurrences;
    final minLength = (opts['min_length'] as num?)?.toInt() ?? this.minLength;

    final issues = <AnalysisIssue>[];
    final normalizedPaths = ctx.filePaths.map(p.normalize).toList();
    if (normalizedPaths.isEmpty) return issues;

    final collection = AnalysisContextCollection(
      includedPaths: normalizedPaths,
    );

    for (final filePath in normalizedPaths) {
      final context = collection.contextFor(filePath);
      final result = context.currentSession.getParsedUnit(filePath);
      if (result is! ParsedUnitResult) continue;

      final visitor = _StringLiteralVisitor(result.lineInfo);
      result.unit.accept(visitor);

      for (final entry in visitor.occurrences.entries) {
        final literal = entry.key;
        final locations = entry.value;
        if (literal.length >= minLength && locations.length >= minOccurrences) {
          issues.add(
            AnalysisIssue(
              file: filePath,
              line: locations.first,
              rule: 'dry_string_literal',
              ruleId: 'dry_detection/repeated_string',
              message:
                  'String "$literal" appears ${locations.length} times in this '
                  'file. Extract to a named constant.',
              suggestedFix:
                  'Extract the literal to a top-level `const` or static class member.',
              severity: Severity.minor,
            ),
          );
        }
      }
    }
    return issues;
  }
}

class _StringLiteralVisitor extends RecursiveAstVisitor<void> {
  _StringLiteralVisitor(this.lineInfo);
  final LineInfo lineInfo;
  final Map<String, List<int>> occurrences = {};

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    final value = node.value;
    final line = lineInfo.getLocation(node.offset).lineNumber;
    occurrences.putIfAbsent(value, () => []).add(line);
    super.visitSimpleStringLiteral(node);
  }
}
