// ALEA — Design Principles Analyzer.
//
// Enforces basic SOLID-flavored constraints: max public methods per class
// (SRP), max constructor parameters (low coupling).
//
// Ported from tools/pipeline/lib/src/analyzers/design_principles_analyzer.dart.
//
// Thresholds are config-exposed via `.alea.yaml`:
//   analyzers:
//     options:
//       design_principles:
//         max_public_methods: 10       # default
//         max_constructor_params: 7    # default

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../contracts/analyzer.dart';

class DesignPrinciplesAnalyzer extends Analyzer {
  @override
  String get name => 'design_principles';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final opts = ctx.config.analyzers.optionsFor(name);
    final maxPublicMethods =
        (opts['max_public_methods'] as num?)?.toInt() ?? 10;
    final maxConstructorParams =
        (opts['max_constructor_params'] as num?)?.toInt() ?? 7;

    final issues = <AnalysisIssue>[];
    for (final filePath in ctx.filePaths) {
      late final ParseStringResult parsed;
      try {
        parsed = parseFile(
          path: filePath,
          featureSet: FeatureSet.latestLanguageVersion(),
        );
      } on FileSystemException {
        continue;
      }
      final visitor = _DesignVisitor(
        filePath,
        parsed.lineInfo,
        maxPublicMethods: maxPublicMethods,
        maxConstructorParams: maxConstructorParams,
      );
      parsed.unit.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _DesignVisitor extends RecursiveAstVisitor<void> {
  _DesignVisitor(
    this.filePath,
    this.lineInfo, {
    required this.maxPublicMethods,
    required this.maxConstructorParams,
  });

  final String filePath;
  final LineInfo lineInfo;
  final int maxPublicMethods;
  final int maxConstructorParams;
  final List<AnalysisIssue> issues = [];

  String? _currentClassName;
  int _publicMethodCount = 0;
  int _currentClassOffset = -1;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final prevName = _currentClassName;
    final prevCount = _publicMethodCount;
    final prevOffset = _currentClassOffset;

    _currentClassName = node.namePart.typeName.lexeme;
    _publicMethodCount = 0;
    _currentClassOffset = node.offset;

    super.visitClassDeclaration(node);

    if (_publicMethodCount > maxPublicMethods) {
      final line = lineInfo.getLocation(_currentClassOffset).lineNumber;
      issues.add(
        AnalysisIssue(
          file: filePath,
          line: line,
          rule: 'class_too_many_methods',
          ruleId: 'design_principles/srp_violation',
          message:
              '$_currentClassName has $_publicMethodCount public methods '
              '(limit: $maxPublicMethods). '
              'Consider splitting it into focused classes (SRP).',
          severity: Severity.major,
        ),
      );
    }

    _currentClassName = prevName;
    _publicMethodCount = prevCount;
    _currentClassOffset = prevOffset;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final name = node.name.lexeme;
    if (_currentClassName != null &&
        !name.startsWith('_') &&
        !node.isOperator &&
        !node.isGetter &&
        !node.isSetter) {
      _publicMethodCount++;
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final paramCount = node.parameters.parameters.length;
    if (paramCount > maxConstructorParams) {
      final line = lineInfo.getLocation(node.offset).lineNumber;
      final className = _currentClassName ?? '(unknown)';
      issues.add(
        AnalysisIssue(
          file: filePath,
          line: line,
          rule: 'constructor_too_many_params',
          ruleId: 'design_principles/coupling',
          message:
              '$className constructor has $paramCount parameters '
              '(limit: $maxConstructorParams). '
              'Extract related parameters into value objects to reduce coupling.',
          severity: Severity.major,
        ),
      );
    }
    super.visitConstructorDeclaration(node);
  }
}
