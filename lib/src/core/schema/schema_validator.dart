// ALEA — Artifact schema validator.
//
// Validates a pipeline artifact (parsed JSON) against an ALEA schema DSL file
// (the custom YAML format under `contracts/schemas/`). This is the code that
// makes "validate before persisting" a *code-enforced* postcondition instead
// of something an AI claims to have done.
//
// Scope (deliberate, per "no info > wrong info"): the validator checks the
// regular, machine-readable parts of the DSL with HIGH PRECISION —
//   - top-level `required` fields present + non-null
//   - `enum`, `pattern`, `min_items`
//   - scalar/`list<>`/object/custom-type kinds, with `X | null` nullability
//   - `required_when: "field == value"` conditional requirements
// Anything it cannot interpret (exotic pseudo-types, prose rules) is recorded
// in `skipped` and NOT failed — the validator never rejects what it cannot
// judge. So a `valid: true` means "no violation the validator can prove",
// never "the AI says so".

import 'package:yaml/yaml.dart';

class SchemaViolation {
  final String path;
  final String message;
  const SchemaViolation(this.path, this.message);

  Map<String, Object?> toJson() => {'path': path, 'message': message};

  @override
  String toString() => '$path: $message';
}

class SchemaValidationResult {
  final List<SchemaViolation> violations;

  /// Constructs the validator could not check (honesty: not silently passed).
  final List<String> skipped;

  const SchemaValidationResult(this.violations, this.skipped);

  bool get valid => violations.isEmpty;

  Map<String, Object?> toJson() => {
    'valid': valid,
    'violations': violations.map((v) => v.toJson()).toList(),
    if (skipped.isNotEmpty) 'skipped': skipped,
  };
}

/// Validate [artifact] (decoded JSON) against [schema] (parsed schema YAML).
SchemaValidationResult validateArtifact(Map schema, Object? artifact) {
  final violations = <SchemaViolation>[];
  final skipped = <String>[];

  if (artifact is! Map) {
    violations.add(
      const SchemaViolation('(root)', 'artifact must be an object'),
    );
    return SchemaValidationResult(violations, skipped);
  }

  // 1. Top-level required fields.
  final required = schema['required'];
  if (required is List) {
    for (final r in required) {
      final name = r.toString();
      if (artifact[name] == null) {
        violations.add(
          SchemaViolation(name, 'required field is missing or null'),
        );
      }
    }
  }

  // 2. required_when conditionals + field-by-field validation.
  schema.forEach((key, def) {
    if (def is! Map || !def.containsKey('type')) return; // meta or type-def
    final name = key.toString();

    final requiredWhen = def['required_when'];
    if (requiredWhen is String) {
      final met = _evalCondition(requiredWhen, artifact);
      if (met == null) {
        // Unparseable condition: record it instead of silently dropping the
        // requirement (honours the validator's "skipped, not swallowed" rule).
        skipped.add('$name: uncheckable required_when `$requiredWhen`');
      } else if (met && artifact[name] == null) {
        violations.add(
          SchemaViolation(
            name,
            'required when `$requiredWhen` but missing/null',
          ),
        );
      }
    }

    if (artifact.containsKey(name)) {
      _validateValue(artifact[name], def, schema, name, violations, skipped);
    }
  });

  return SchemaValidationResult(violations, skipped);
}

// ── Internals ────────────────────────────────────────────────────────────────

class _Type {
  final bool nullable;
  final String base; // string|bool|int|iso8601|list|object|custom|unknown
  final String? elem; // list element type expr
  final String? custom; // custom type name
  final int? minInt; // for `int >= N`
  const _Type(
    this.base, {
    this.nullable = false,
    this.elem,
    this.custom,
    this.minInt,
  });
}

_Type _parseType(String raw) {
  final parts = raw.split('|').map((s) => s.trim()).toList();
  final nullable = parts.contains('null');
  final t = parts.firstWhere((p) => p != 'null', orElse: () => 'unknown');

  if (t == 'string' ||
      t == 'layer_name' ||
      t == 'relative_path' ||
      t == 'pascal_case_string') {
    return _Type('string', nullable: nullable);
  }
  if (t == 'bool') return _Type('bool', nullable: nullable);
  if (t == 'ISO8601') return _Type('iso8601', nullable: nullable);
  if (t == 'int') return _Type('int', nullable: nullable);
  final intMin = RegExp(r'^int\s*>=\s*(\d+)$').firstMatch(t);
  if (intMin != null) {
    return _Type(
      'int',
      nullable: nullable,
      minInt: int.parse(intMin.group(1)!),
    );
  }
  final list = RegExp(r'^list<(.+)>$').firstMatch(t);
  if (list != null) {
    return _Type('list', nullable: nullable, elem: list.group(1)!.trim());
  }
  if (t == 'object') return _Type('object', nullable: nullable);
  if (t == 'unknown') return const _Type('unknown');
  // A bare capitalised word → custom type reference.
  return _Type('custom', nullable: nullable, custom: t);
}

void _validateValue(
  Object? value,
  Map def,
  Map schema,
  String path,
  List<SchemaViolation> violations,
  List<String> skipped,
) {
  final typeStr = def['type'];
  if (typeStr is! String) return;
  final pt = _parseType(typeStr);

  if (value == null) {
    if (!pt.nullable) {
      violations.add(SchemaViolation(path, 'expected $typeStr, got null'));
    }
    return;
  }

  switch (pt.base) {
    case 'string':
    case 'iso8601':
      if (value is! String) {
        violations.add(
          SchemaViolation(path, 'expected string, got ${_kind(value)}'),
        );
        return;
      }
      if (pt.base == 'iso8601' && DateTime.tryParse(value) == null) {
        violations.add(SchemaViolation(path, 'not a valid ISO8601 timestamp'));
      }
      _checkEnum(value, def, path, violations);
      _checkPattern(value, def, path, violations);
    case 'bool':
      if (value is! bool) {
        violations.add(
          SchemaViolation(path, 'expected bool, got ${_kind(value)}'),
        );
      }
    case 'int':
      if (value is! int) {
        violations.add(
          SchemaViolation(path, 'expected int, got ${_kind(value)}'),
        );
      } else if (pt.minInt != null && value < pt.minInt!) {
        violations.add(SchemaViolation(path, 'must be >= ${pt.minInt}'));
      }
    case 'list':
      if (value is! List) {
        violations.add(
          SchemaViolation(path, 'expected list, got ${_kind(value)}'),
        );
        return;
      }
      final minItems = def['min_items'];
      if (minItems is int && value.length < minItems) {
        violations.add(SchemaViolation(path, 'must have >= $minItems items'));
      }
      for (var i = 0; i < value.length; i++) {
        _validateElement(
          value[i],
          pt.elem!,
          schema,
          '$path[$i]',
          violations,
          skipped,
        );
      }
    case 'object':
      _validateObject(value, def, schema, path, violations, skipped);
    case 'custom':
      final typeDef = schema[pt.custom];
      if (typeDef is Map) {
        _validateObject(value, typeDef, schema, path, violations, skipped);
      } else {
        skipped.add('$path: unknown custom type ${pt.custom}');
      }
    case 'unknown':
      skipped.add('$path: uncheckable type $typeStr');
  }
}

void _validateElement(
  Object? value,
  String elemType,
  Map schema,
  String path,
  List<SchemaViolation> violations,
  List<String> skipped,
) {
  // Wrap the element type in a synthetic field def and reuse _validateValue.
  _validateValue(value, {'type': elemType}, schema, path, violations, skipped);
}

void _validateObject(
  Object? value,
  Map objDef,
  Map schema,
  String path,
  List<SchemaViolation> violations,
  List<String> skipped,
) {
  if (value is! Map) {
    violations.add(
      SchemaViolation(path, 'expected object, got ${_kind(value)}'),
    );
    return;
  }
  final required = objDef['required'];
  if (required is List) {
    for (final r in required) {
      final name = r.toString();
      if (value[name] == null) {
        violations.add(
          SchemaViolation('$path.$name', 'required field missing or null'),
        );
      }
    }
  }
  final fields = objDef['fields'];
  if (fields is Map) {
    fields.forEach((fieldKey, fieldDef) {
      final name = fieldKey.toString();
      if (fieldDef is Map && value.containsKey(name)) {
        _validateValue(
          value[name],
          fieldDef,
          schema,
          '$path.$name',
          violations,
          skipped,
        );
      }
    });
  }
}

void _checkEnum(
  String value,
  Map def,
  String path,
  List<SchemaViolation> violations,
) {
  final allowed = def['enum'];
  if (allowed is List && !allowed.map((e) => e.toString()).contains(value)) {
    violations.add(SchemaViolation(path, '"$value" not in enum $allowed'));
  }
}

void _checkPattern(
  String value,
  Map def,
  String path,
  List<SchemaViolation> violations,
) {
  final pattern = def['pattern'];
  if (pattern is String && !RegExp(pattern).hasMatch(value)) {
    violations.add(SchemaViolation(path, 'does not match pattern `$pattern`'));
  }
}

String _kind(Object? v) {
  if (v is String) return 'string';
  if (v is bool) return 'bool';
  if (v is int) return 'int';
  if (v is double) return 'double';
  if (v is List) return 'list';
  if (v is Map) return 'object';
  return 'null';
}

/// Evaluate a `field == value` condition against the artifact.
///
/// Returns `true`/`false` when the condition is a parseable `field == value`,
/// or `null` when the validator cannot interpret it (e.g. `!=`, compound, or
/// other operators). The caller records `null` in `skipped` so an unenforced
/// requirement is visible rather than silently dropped.
bool? _evalCondition(String condition, Map artifact) {
  final parts = condition.split('==');
  if (parts.length != 2) return null;
  final field = parts[0].trim();
  final expected = parts[1].trim();
  return artifact[field]?.toString() == expected;
}

/// Parse a schema YAML string into a plain [Map] for [validateArtifact].
Map parseSchema(String yamlText) {
  final doc = loadYaml(yamlText);
  if (doc is Map) return doc;
  throw const FormatException('schema root is not a mapping');
}
