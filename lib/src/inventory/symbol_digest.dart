// ALEA — SymbolDigest.
//
// Produces a compact, deterministic view of a Dart file's public surface:
// classes, constructors, methods, getters/setters, fields, and top-level
// constants — with type/return annotations preserved, but no bodies, no
// imports, no comments. Designed so that callers (LLMs, skills, code
// reviewers) can understand "what's in this file" without paying the token
// cost of the full source.
//
// Pure-ish — uses `package:analyzer` AST + `dart:io` for the file read.
// No catalog dependency, no network access.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

class SymbolDigest {
  final String filePath;
  final List<ClassSymbol> classes;
  final List<TopLevelSymbol> topLevels;

  const SymbolDigest({
    required this.filePath,
    required this.classes,
    required this.topLevels,
  });

  /// Render the digest as plain text. Stable across runs given the same
  /// input — useful for diffing and for measuring token reduction.
  String render() {
    final buf = StringBuffer();
    buf.writeln('# $filePath');
    for (final cls in classes) {
      buf.write(cls.render());
    }
    if (topLevels.isNotEmpty && classes.isNotEmpty) buf.writeln();
    for (final top in topLevels) {
      buf.writeln(top.render());
    }
    return buf.toString();
  }

  Map<String, Object?> toJson() => {
    'file_path': filePath,
    if (classes.isNotEmpty) 'classes': classes.map((c) => c.toJson()).toList(),
    if (topLevels.isNotEmpty)
      'top_levels': topLevels.map((t) => t.toJson()).toList(),
  };
}

class ClassSymbol {
  final String name;
  final String? extendsName;
  final List<String> implementsNames;
  final List<MemberSymbol> members;
  final bool isAbstract;

  const ClassSymbol({
    required this.name,
    this.extendsName,
    this.implementsNames = const [],
    this.members = const [],
    this.isAbstract = false,
  });

  String render() {
    final buf = StringBuffer();
    buf.write(isAbstract ? 'abstract class $name' : 'class $name');
    if (extendsName != null) buf.write(' extends $extendsName');
    if (implementsNames.isNotEmpty) {
      buf.write(' implements ${implementsNames.join(', ')}');
    }
    buf.writeln();
    for (final m in members) {
      buf.write('  ');
      buf.writeln(m.render());
    }
    return buf.toString();
  }

  Map<String, Object?> toJson() => {
    'name': name,
    if (extendsName != null) 'extends': extendsName,
    if (implementsNames.isNotEmpty) 'implements': implementsNames,
    if (isAbstract) 'abstract': true,
    if (members.isNotEmpty) 'members': members.map((m) => m.toJson()).toList(),
  };
}

class MemberSymbol {
  final String kind; // 'constructor' | 'method' | 'getter' | 'setter' | 'field'
  final String name;
  final String? signature; // method/ctor parameter list as Dart source
  final String? returnType;
  final bool isStatic;
  final bool isFinal;

  const MemberSymbol({
    required this.kind,
    required this.name,
    this.signature,
    this.returnType,
    this.isStatic = false,
    this.isFinal = false,
  });

  String render() {
    final buf = StringBuffer();
    if (isStatic) buf.write('static ');
    if (isFinal) buf.write('final ');
    switch (kind) {
      case 'constructor':
        buf.write(name);
        if (signature != null) buf.write(signature);
        break;
      case 'method':
        if (returnType != null) buf.write('$returnType ');
        buf.write(name);
        if (signature != null) buf.write(signature);
        break;
      case 'getter':
        buf.write('${returnType ?? 'dynamic'} get $name');
        break;
      case 'setter':
        buf.write('set $name(${signature ?? ''})');
        break;
      case 'field':
        if (returnType != null) buf.write('$returnType ');
        buf.write(name);
        break;
    }
    return buf.toString();
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'name': name,
    if (signature != null) 'signature': signature,
    if (returnType != null) 'return_type': returnType,
    if (isStatic) 'static': true,
    if (isFinal) 'final': true,
  };
}

class TopLevelSymbol {
  final String kind; // 'function' | 'const' | 'final' | 'variable'
  final String name;
  final String? signature; // parameter list for functions
  final String? returnType;

  const TopLevelSymbol({
    required this.kind,
    required this.name,
    this.signature,
    this.returnType,
  });

  String render() {
    switch (kind) {
      case 'function':
        return '${returnType ?? 'dynamic'} $name${signature ?? '()'}';
      case 'const':
        return 'const ${returnType ?? ''} $name'.trim();
      case 'final':
        return 'final ${returnType ?? ''} $name'.trim();
      case 'variable':
        return '${returnType ?? 'var'} $name';
      default:
        return name;
    }
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'name': name,
    if (signature != null) 'signature': signature,
    if (returnType != null) 'return_type': returnType,
  };
}

/// Build a [SymbolDigest] for the Dart file at [absolutePath].
///
/// Skips members whose name starts with `_` (private by Dart convention).
/// Throws [FileSystemException] when the file does not exist.
SymbolDigest extractSymbolDigest(String absolutePath, {String? projectRoot}) {
  if (!File(absolutePath).existsSync()) {
    throw FileSystemException('File not found', absolutePath);
  }
  final parsed = parseFile(
    path: absolutePath,
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  final classes = <ClassSymbol>[];
  final topLevels = <TopLevelSymbol>[];

  for (final decl in parsed.unit.declarations) {
    if (decl is ClassDeclaration) {
      final name = decl.namePart.typeName.lexeme;
      if (name.startsWith('_')) continue;
      classes.add(_classSymbol(decl));
    } else if (decl is FunctionDeclaration) {
      final fname = decl.name.lexeme;
      if (fname.startsWith('_')) continue;
      topLevels.add(_topLevelFunction(decl));
    } else if (decl is TopLevelVariableDeclaration) {
      for (final v in decl.variables.variables) {
        final vname = v.name.lexeme;
        if (vname.startsWith('_')) continue;
        topLevels.add(_topLevelVariable(decl, v));
      }
    }
  }

  return SymbolDigest(
    filePath: _projectRelative(absolutePath, projectRoot),
    classes: List.unmodifiable(classes),
    topLevels: List.unmodifiable(topLevels),
  );
}

ClassSymbol _classSymbol(ClassDeclaration decl) {
  final extendsName = decl.extendsClause?.superclass.toSource();
  final implementsNames =
      decl.implementsClause?.interfaces
          .map((t) => t.toSource())
          .toList(growable: false) ??
      const <String>[];
  final members = <MemberSymbol>[];
  for (final m in decl.body.members) {
    final mem = _memberSymbol(m);
    if (mem != null) members.add(mem);
  }
  return ClassSymbol(
    name: decl.namePart.typeName.lexeme,
    extendsName: extendsName,
    implementsNames: implementsNames,
    members: List.unmodifiable(members),
    isAbstract: decl.abstractKeyword != null,
  );
}

MemberSymbol? _memberSymbol(ClassMember m) {
  if (m is ConstructorDeclaration) {
    final n = m.name?.lexeme ?? '';
    if (n.startsWith('_')) return null;
    return MemberSymbol(
      kind: 'constructor',
      name: m.name?.lexeme ?? m.typeName?.name ?? '',
      signature: m.parameters.toSource(),
    );
  }
  if (m is MethodDeclaration) {
    final n = m.name.lexeme;
    if (n.startsWith('_')) return null;
    final kind = m.isGetter
        ? 'getter'
        : m.isSetter
        ? 'setter'
        : 'method';
    return MemberSymbol(
      kind: kind,
      name: n,
      signature: m.isGetter ? null : m.parameters?.toSource(),
      returnType: m.returnType?.toSource(),
      isStatic: m.isStatic,
    );
  }
  if (m is FieldDeclaration) {
    final type = m.fields.type?.toSource();
    final out = <MemberSymbol>[];
    for (final v in m.fields.variables) {
      if (v.name.lexeme.startsWith('_')) continue;
      out.add(
        MemberSymbol(
          kind: 'field',
          name: v.name.lexeme,
          returnType: type,
          isStatic: m.isStatic,
          isFinal: m.fields.isFinal || m.fields.isConst,
        ),
      );
    }
    // Return only the first (FieldDeclaration may carry several variables).
    return out.isNotEmpty ? out.first : null;
  }
  return null;
}

TopLevelSymbol _topLevelFunction(FunctionDeclaration decl) {
  final fn = decl.functionExpression;
  return TopLevelSymbol(
    kind: 'function',
    name: decl.name.lexeme,
    signature: fn.parameters?.toSource(),
    returnType: decl.returnType?.toSource(),
  );
}

TopLevelSymbol _topLevelVariable(
  TopLevelVariableDeclaration decl,
  VariableDeclaration v,
) {
  final kind = decl.variables.isConst
      ? 'const'
      : decl.variables.isFinal
      ? 'final'
      : 'variable';
  return TopLevelSymbol(
    kind: kind,
    name: v.name.lexeme,
    returnType: decl.variables.type?.toSource(),
  );
}

String _projectRelative(String absolutePath, String? projectRoot) {
  if (projectRoot == null) return absolutePath;
  // Lightweight inlining of p.relative to avoid pulling path here.
  if (absolutePath.startsWith(projectRoot)) {
    var rel = absolutePath.substring(projectRoot.length);
    while (rel.startsWith('/') || rel.startsWith(r'\')) {
      rel = rel.substring(1);
    }
    return rel.replaceAll(r'\', '/');
  }
  return absolutePath;
}
