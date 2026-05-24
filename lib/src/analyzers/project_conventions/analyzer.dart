// ALEA — Project Conventions Analyzer.
//
// Naming + TODO discipline:
//   - Type declarations (class/enum/mixin/extension) must be PascalCase.
//   - Methods/functions must be lowerCamelCase.
//   - TODO/FIXME comments must reference a ticket.
//
// Ported from tools/pipeline/lib/src/analyzers/project_conventions_analyzer.dart.
// Updated for analyzer 6.x API (`node.name.lexeme` instead of `namePart.typeName`).

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../contracts/analyzer.dart';

// Ticket reference patterns accepted in TODO/FIXME comments. Covers the
// common forms across trackers (DEV-, JIRA-, GH-, #N).
final _ticketPattern = RegExp(r'DEV-\d+|JIRA-\d+|GH-\d+|#\d+');

const _generatedSuffixes = ['.g.dart', '.freezed.dart', '.mocks.dart'];

class ProjectConventionsAnalyzer extends Analyzer {
  @override
  String get name => 'project_conventions';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final issues = <AnalysisIssue>[];
    for (final filePath in ctx.filePaths) {
      if (_isGenerated(filePath)) continue;
      late final ParseStringResult parsed;
      try {
        parsed = parseFile(
          path: filePath,
          featureSet: FeatureSet.latestLanguageVersion(),
        );
      } on FileSystemException {
        continue;
      }
      final visitor = _NamingVisitor(filePath, parsed.lineInfo);
      parsed.unit.accept(visitor);
      issues.addAll(visitor.issues);
      _checkTodos(filePath, issues);
    }
    return issues;
  }

  bool _isGenerated(String path) =>
      _generatedSuffixes.any((s) => path.endsWith(s));

  void _checkTodos(String filePath, List<AnalysisIssue> issues) {
    final List<String> lines;
    try {
      lines = File(filePath).readAsLinesSync();
    } on FileSystemException {
      return;
    }
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.contains('TODO') && !line.contains('FIXME')) continue;
      final commentIdx = line.indexOf('//');
      if (commentIdx == -1) continue;
      final comment = line.substring(commentIdx);
      if (!comment.contains('TODO') && !comment.contains('FIXME')) continue;
      if (_ticketPattern.hasMatch(comment)) continue;
      issues.add(
        AnalysisIssue(
          file: filePath,
          line: i + 1,
          rule: 'todo_without_ticket',
          ruleId: 'project_conventions/todo_no_ticket',
          message:
              'TODO/FIXME without a ticket reference. '
              'Add a ticket ID, e.g. // TODO(DEV-1234): description.',
          severity: Severity.minor,
        ),
      );
    }
  }
}

class _NamingVisitor extends RecursiveAstVisitor<void> {
  _NamingVisitor(this.filePath, this.lineInfo);
  final String filePath;
  final LineInfo lineInfo;
  final List<AnalysisIssue> issues = [];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final token = node.namePart.typeName;
    _checkTypeName(token.lexeme, token.offset);
    super.visitClassDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final token = node.namePart.typeName;
    _checkTypeName(token.lexeme, token.offset);
    super.visitEnumDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _checkTypeName(node.name.lexeme, node.name.offset);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final nameTok = node.name;
    if (nameTok != null) _checkTypeName(nameTok.lexeme, nameTok.offset);
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (!node.isOperator) {
      _checkMemberName(node.name.lexeme, node.name.offset);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final name = node.name.lexeme;
    if (name != 'main') _checkMemberName(name, node.name.offset);
    super.visitFunctionDeclaration(node);
  }

  void _checkTypeName(String name, int offset) {
    final stripped = name.startsWith('_') ? name.substring(1) : name;
    if (stripped.isEmpty) return;
    if (_isPascalCase(stripped)) return;
    final line = lineInfo.getLocation(offset).lineNumber;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: line,
        rule: 'naming_class_case',
        ruleId: 'project_conventions/type_pascal_case',
        message:
            '"$name" should be PascalCase. Rename to "${_toPascalCase(stripped)}".',
        severity: Severity.minor,
      ),
    );
  }

  void _checkMemberName(String name, int offset) {
    final stripped = name.startsWith('_') ? name.substring(1) : name;
    if (stripped.isEmpty) return;
    if (_isCamelCase(stripped)) return;
    final line = lineInfo.getLocation(offset).lineNumber;
    issues.add(
      AnalysisIssue(
        file: filePath,
        line: line,
        rule: 'naming_method_case',
        ruleId: 'project_conventions/member_camel_case',
        message:
            '"$name" should be lowerCamelCase. Rename to "${_toCamelCase(stripped)}".',
        severity: Severity.minor,
      ),
    );
  }

  bool _isPascalCase(String n) =>
      n[0] == n[0].toUpperCase() && !n.contains('_');
  bool _isCamelCase(String n) => n[0] == n[0].toLowerCase() && !n.contains('_');

  String _toPascalCase(String n) => n
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join();

  String _toCamelCase(String n) {
    final parts = n.split('_');
    if (parts.isEmpty) return n;
    return parts[0] +
        parts
            .skip(1)
            .map(
              (w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}',
            )
            .join();
  }
}
