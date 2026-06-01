// ALEA — Code Complexity Analyzer.
//
// Measures cyclomatic complexity (per McCabe) and function length per
// method/function in a Dart compilation unit. Two thresholds per metric.
//
// Ported from tools/pipeline/lib/src/analyzers/code_complexity_analyzer.dart.

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../../contracts/analyzer.dart';

class CodeComplexityAnalyzer extends Analyzer {
  CodeComplexityAnalyzer({
    this.complexityThresholdMajor = 10,
    this.complexityThresholdCritical = 20,
    this.lengthThresholdMajor = 50,
    this.lengthThresholdCritical = 100,
  });
  final int complexityThresholdMajor;
  final int complexityThresholdCritical;
  final int lengthThresholdMajor;
  final int lengthThresholdCritical;

  @override
  String get name => 'code_complexity';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final issues = <AnalysisIssue>[];
    for (final normalizedPath in ctx.filePaths.map(p.normalize)) {
      late final ParseStringResult parsed;
      try {
        parsed = parseFile(
          path: normalizedPath,
          featureSet: FeatureSet.latestLanguageVersion(),
          throwIfDiagnostics: false,
        );
      } on Exception {
        continue;
      }
      final visitor = _FunctionVisitor(parsed.lineInfo);
      parsed.unit.accept(visitor);
      for (final metrics in visitor.functions) {
        _emitForMetrics(metrics, normalizedPath, issues);
      }
    }
    return issues;
  }

  void _emitForMetrics(
    _FunctionMetrics m,
    String file,
    List<AnalysisIssue> issues,
  ) {
    if (!m.exemptFromCyclomatic && m.complexity > complexityThresholdCritical) {
      issues.add(
        AnalysisIssue(
          file: file,
          line: m.startLine,
          rule: 'code_complexity',
          ruleId: 'code_complexity/cyclomatic_critical',
          message:
              '${m.name} has cyclomatic complexity ${m.complexity} '
              '(threshold: $complexityThresholdCritical)',
          severity: Severity.critical,
        ),
      );
    } else if (!m.exemptFromCyclomatic &&
        m.complexity > complexityThresholdMajor) {
      issues.add(
        AnalysisIssue(
          file: file,
          line: m.startLine,
          rule: 'code_complexity',
          ruleId: 'code_complexity/cyclomatic_major',
          message:
              '${m.name} has cyclomatic complexity ${m.complexity} '
              '(threshold: $complexityThresholdMajor)',
          severity: Severity.major,
        ),
      );
    }
    if (m.length > lengthThresholdCritical) {
      issues.add(
        AnalysisIssue(
          file: file,
          line: m.startLine,
          rule: 'function_length',
          ruleId: 'code_complexity/length_critical',
          message:
              '${m.name} is ${m.length} lines long '
              '(threshold: $lengthThresholdCritical)',
          severity: Severity.critical,
        ),
      );
    } else if (m.length > lengthThresholdMajor) {
      issues.add(
        AnalysisIssue(
          file: file,
          line: m.startLine,
          rule: 'function_length',
          ruleId: 'code_complexity/length_major',
          message:
              '${m.name} is ${m.length} lines long '
              '(threshold: $lengthThresholdMajor)',
          severity: Severity.major,
        ),
      );
    }
  }
}

class _FunctionMetrics {
  _FunctionMetrics(this.name);
  final String name;
  int complexity = 1;
  int length = 0;
  int startLine = 0;

  /// Value-object equality surface (`operator ==`, `hashCode`) is exempt from
  /// the cyclomatic check: its McCabe count comes from the flat `&&`/`?:` chain
  /// over fields, not real branching logic (CC-1 calibration). Length still
  /// applies.
  bool exemptFromCyclomatic = false;
}

class _FunctionVisitor extends RecursiveAstVisitor<void> {
  _FunctionVisitor(this.lineInfo);
  final LineInfo lineInfo;
  final List<_FunctionMetrics> functions = [];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final metrics = _FunctionMetrics(node.name.lexeme)
      ..startLine = lineInfo.getLocation(node.offset).lineNumber
      ..exemptFromCyclomatic =
          (node.isOperator && node.name.lexeme == '==') ||
          (node.isGetter && node.name.lexeme == 'hashCode');
    _measureBody(metrics, node.body);
    functions.add(metrics);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (!node.isGetter && !node.isSetter) {
      final metrics = _FunctionMetrics(node.name.lexeme)
        ..startLine = lineInfo.getLocation(node.offset).lineNumber;
      _measureBody(metrics, node.functionExpression.body);
      functions.add(metrics);
    }
    super.visitFunctionDeclaration(node);
  }

  void _measureBody(_FunctionMetrics metrics, FunctionBody body) {
    if (body is BlockFunctionBody) {
      final startLine = lineInfo.getLocation(body.offset).lineNumber;
      final endLine = lineInfo.getLocation(body.endToken.offset).lineNumber;
      metrics.length = endLine - startLine;
    }
    final counter = _ComplexityCountVisitor();
    body.accept(counter);
    metrics.complexity = 1 + counter.count;
  }
}

class _ComplexityCountVisitor extends RecursiveAstVisitor<void> {
  int count = 0;

  @override
  void visitIfStatement(IfStatement node) {
    count++;
    super.visitIfStatement(node);
  }

  @override
  void visitForStatement(ForStatement node) {
    count++;
    super.visitForStatement(node);
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    count++;
    super.visitWhileStatement(node);
  }

  @override
  void visitDoStatement(DoStatement node) {
    count++;
    super.visitDoStatement(node);
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    count++;
    super.visitSwitchCase(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    count++;
    super.visitCatchClause(node);
  }

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    count++;
    super.visitConditionalExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (node.operator.type == TokenType.AMPERSAND_AMPERSAND ||
        node.operator.type == TokenType.BAR_BAR) {
      count++;
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Do not recurse — nested closures have separate complexity.
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // Do not recurse — local named functions are separate.
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    count++;
    super.visitSwitchPatternCase(node);
  }

  @override
  void visitSwitchExpressionCase(SwitchExpressionCase node) {
    count++;
    super.visitSwitchExpressionCase(node);
  }

  @override
  void visitGuardedPattern(GuardedPattern node) {
    if (node.whenClause != null) count++;
    super.visitGuardedPattern(node);
  }
}
