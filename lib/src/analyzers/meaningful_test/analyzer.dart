// ALEA — Meaningful Test Analyzer.
//
// ADVISORY (bucket 2): flags tests that cannot fail — a tautological `expect`
// or a test body with no assertion at all. These are *signals* for human/AI
// review of the criteria→test gap, NOT hard gates: a heuristic that mis-fires
// (e.g. a test that asserts via a custom helper the analyzer can't see) must
// never block. Hence every issue is `Severity.minor` and never reprueba el
// gate (`AnalysisResult.passed` ignores minor).
//
// Only runs on `*_test.dart` files (cuts false positives from non-test code
// that happens to call a function named `test`/`expect`).
//
// Precision of the two rules:
//   - tautological_expect: `expect(a, b)` where a≡b textually, or a boolean
//     literal paired with its matching `isTrue`/`isFalse`. Very low FP rate.
//   - no_assertion: a `test`/`testWidgets` body with zero
//     expect/expectLater/verify(Never)/verifyInOrder calls. Higher FP rate
//     (custom assertion helpers) — acceptable because advisory.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../contracts/analyzer.dart';

const _testNames = {'test', 'testWidgets'};
const _assertionNames = {
  'expect',
  'expectLater',
  'verify',
  'verifyNever',
  'verifyInOrder',
};

class MeaningfulTestAnalyzer extends Analyzer {
  @override
  String get name => 'meaningful_test';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final issues = <AnalysisIssue>[];
    for (final filePath in ctx.filePaths) {
      if (!filePath.endsWith('_test.dart')) continue;
      late final ParseStringResult parsed;
      try {
        parsed = parseFile(
          path: filePath,
          featureSet: FeatureSet.latestLanguageVersion(),
        );
      } on FileSystemException {
        continue;
      }
      final visitor = _MeaningfulTestVisitor(filePath, parsed.lineInfo);
      parsed.unit.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }
}

class _MeaningfulTestVisitor extends RecursiveAstVisitor<void> {
  _MeaningfulTestVisitor(this.filePath, this.lineInfo);
  final String filePath;
  final LineInfo lineInfo;
  final List<AnalysisIssue> issues = [];

  /// One counter per enclosing `test`/`testWidgets` scope (groups nest).
  final List<int> _assertionStack = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;

    if (node.target == null && _testNames.contains(method)) {
      _assertionStack.add(0);
      super.visitMethodInvocation(node);
      final count = _assertionStack.removeLast();
      if (count == 0) {
        _add(
          node.offset,
          rule: 'test_without_assertion',
          ruleId: 'meaningful_test/no_assertion',
          message:
              'Test has no assertion (expect/verify). It cannot fail — add an '
              'assertion that verifies the behavior under test.',
        );
      }
      return;
    }

    if (node.target == null && _assertionNames.contains(method)) {
      if (_assertionStack.isNotEmpty) _assertionStack.last++;
      if (method == 'expect') _checkTautology(node);
    }

    super.visitMethodInvocation(node);
  }

  void _checkTautology(MethodInvocation node) {
    final args = node.argumentList.arguments;
    if (args.length < 2) return;
    final a = args[0];
    final b = args[1];
    final identical = a.toSource() == b.toSource();
    final boolTaut =
        (a is BooleanLiteral && b is BooleanLiteral && a.value == b.value) ||
        (a is BooleanLiteral &&
            b is SimpleIdentifier &&
            ((a.value && b.name == 'isTrue') ||
                (!a.value && b.name == 'isFalse')));
    if (identical || boolTaut) {
      _add(
        node.offset,
        rule: 'tautological_expect',
        ruleId: 'meaningful_test/tautological_expect',
        message:
            'expect(${a.toSource()}, ${b.toSource()}) is tautological — it '
            'always passes and verifies nothing. Assert against the value '
            'under test.',
      );
    }
  }

  void _add(
    int offset, {
    required String rule,
    required String ruleId,
    required String message,
  }) {
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: lineInfo.getLocation(offset).lineNumber,
        rule: rule,
        ruleId: ruleId,
        message: message,
        severity: Severity.minor, // advisory — never blocks (P1)
      ),
    );
  }
}
