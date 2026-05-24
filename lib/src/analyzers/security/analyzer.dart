// ALEA — Security Analyzer.
//
// Detects hardcoded secrets, print() leaks, and dart:io imports in the domain
// layer. Ported from tools/pipeline/lib/src/analyzers/security_analyzer.dart.
//
// Domain-layer check is now config-aware: walks `config.architecture.layers`
// to find the layer whose name is `domain` (if present). Falls back to the
// path-segment heuristic when no `domain` layer exists.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import '../../contracts/analyzer.dart';
import '../../contracts/project_config.dart';

// Variable/field name patterns that suggest the value is a secret.
final _secretNamePattern = RegExp(
  r'(api[_-]?key|secret|password|passwd|auth[_-]?token|'
  r'private[_-]?key|bearer[_-]?token|access[_-]?token|client[_-]?secret)',
  caseSensitive: false,
);
// Minimum string length to consider a value a potential secret.
const _minSecretValueLength = 12;

class SecurityAnalyzer extends Analyzer {
  @override
  String get name => 'security';

  @override
  Future<List<AnalysisIssue>> doAnalyze(AnalyzerContext ctx) async {
    final issues = <AnalysisIssue>[];
    final domainPaths = _resolveDomainPaths(ctx.config);

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

      _checkDartIoInDomain(
        filePath,
        parsed.unit,
        parsed.lineInfo,
        domainPaths,
        issues,
      );

      final visitor = _SecurityVisitor(filePath, parsed.lineInfo);
      parsed.unit.accept(visitor);
      issues.addAll(visitor.issues);
    }
    return issues;
  }

  List<String> _resolveDomainPaths(ProjectConfig config) {
    final domain = config.architecture.layers['domain'];
    if (domain != null) return domain.paths;
    // Fallback: legacy /domain/ segment heuristic.
    return const ['/domain/'];
  }

  void _checkDartIoInDomain(
    String filePath,
    CompilationUnit unit,
    LineInfo lineInfo,
    List<String> domainPaths,
    List<AnalysisIssue> issues,
  ) {
    final isDomainFile = domainPaths.any((path) {
      final normalized = path.replaceAll(r'\', '/');
      final withSlash = normalized.endsWith('/') ? normalized : '$normalized/';
      return filePath.replaceAll(r'\', '/').contains(withSlash);
    });
    if (!isDomainFile) return;

    for (final directive in unit.directives) {
      if (directive is! ImportDirective) continue;
      final uri = directive.uri.stringValue ?? '';
      if (uri == 'dart:io' || uri.startsWith('dart:io/')) {
        final line = lineInfo.getLocation(directive.offset).lineNumber;
        issues.add(
          AnalysisIssue(
            file: filePath,
            line: line,
            rule: 'dart_io_in_domain',
            ruleId: 'security/dart_io_in_domain',
            message:
                'Domain layer must not import dart:io — domain must be '
                'platform-independent. Move platform-specific logic to infrastructure.',
            severity: Severity.blocker,
          ),
        );
      }
    }
  }
}

class _SecurityVisitor extends RecursiveAstVisitor<void> {
  _SecurityVisitor(this.filePath, this.lineInfo);
  final String filePath;
  final LineInfo lineInfo;
  final List<AnalysisIssue> issues = [];

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    _checkVariableList(node.variables);
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    _checkVariableList(node.fields);
    super.visitFieldDeclaration(node);
  }

  @override
  void visitVariableDeclarationStatement(VariableDeclarationStatement node) {
    _checkVariableList(node.variables);
    super.visitVariableDeclarationStatement(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if ((name == 'print' || name == 'debugPrint') && node.target == null) {
      final line = lineInfo.getLocation(node.offset).lineNumber;
      issues.add(
        AnalysisIssue(
          file: filePath,
          line: line,
          rule: 'print_statement',
          ruleId: 'security/print_statement',
          message:
              '$name() leaks data to device logs in production. '
              'Use the logging package instead.',
          severity: Severity.major,
        ),
      );
    }
    super.visitMethodInvocation(node);
  }

  void _checkVariableList(VariableDeclarationList variables) {
    for (final variable in variables.variables) {
      final name = variable.name.lexeme;
      if (!_secretNamePattern.hasMatch(name)) continue;
      final initializer = variable.initializer;
      if (initializer is! SimpleStringLiteral) continue;
      if (initializer.value.length < _minSecretValueLength) continue;

      final line = lineInfo.getLocation(variable.offset).lineNumber;
      issues.add(
        AnalysisIssue(
          file: filePath,
          line: line,
          rule: 'hardcoded_secret',
          ruleId: 'security/hardcoded_secret',
          message:
              '"$name" appears to contain a hardcoded secret. '
              'Use environment variables or a secrets manager instead.',
          severity: Severity.blocker,
        ),
      );
    }
  }
}
