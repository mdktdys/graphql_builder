part of '../graphql_builder.dart';

final class _Field {
  final String name;
  final String? alias;
  final Map<String, Object?> arguments;
  final List<_Field>? children;

  _Field(
    String name, {
    String? alias,
    Map<String, Object?> arguments = const {},
    Iterable<_Field>? children,
  }) : name = _name(name),
       alias = alias == null ? null : _name(alias),
       arguments = Map.unmodifiable({
         for (final entry in arguments.entries)
           _name(entry.key): _snapshot(entry.value),
       }),
       children = children == null ? null : _merge(children);

  String get responseKey => alias ?? name;
}

List<_Field> _merge(Iterable<_Field> fields) {
  final byKey = <String, _Field>{};
  for (final field in fields) {
    final previous = byKey[field.responseKey];
    if (previous == null) {
      byKey[field.responseKey] = field;
      continue;
    }
    if (previous.name != field.name ||
        _literal(previous.arguments) != _literal(field.arguments) ||
        (previous.children == null) != (field.children == null)) {
      throw StateError(
        'Conflicting field ${field.responseKey}; use distinct aliases.',
      );
    }
    if (field.children != null) {
      byKey[field.responseKey] = _Field(
        field.name,
        alias: field.alias,
        arguments: field.arguments,
        children: [...previous.children!, ...field.children!],
      );
    }
  }
  if (byKey.isEmpty) throw StateError('A selection cannot be empty.');
  return List.unmodifiable(byKey.values);
}

void _appendFields(List<_Field> target, Iterable<_Field> incoming) {
  final merged = _merge([...target, ...incoming]);
  target
    ..clear()
    ..addAll(merged);
}

String _renderFields(List<_Field> fields, int depth) {
  final indent = '  ' * depth;
  return fields
      .map((field) {
        final alias = field.alias == null ? '' : '${field.alias}: ';
        final arguments = field.arguments.isEmpty
            ? ''
            : '(${field.arguments.entries.map((e) => '${e.key}: ${_literal(e.value)}').join(', ')})';
        final head = '$indent$alias${field.name}$arguments';
        return field.children == null
            ? head
            : '$head {\n${_renderFields(field.children!, depth + 1)}\n$indent}';
      })
      .join('\n');
}

final _graphqlName = RegExp(r'[_A-Za-z][_0-9A-Za-z]*');

String _name(String name) {
  final match = _graphqlName.matchAsPrefix(name);
  if (match == null || match.end != name.length) {
    throw ArgumentError.value(name, 'name', 'Invalid GraphQL name');
  }
  return name;
}

Object? _snapshot(Object? value) =>
    _snapshotValue(value, Set<Object>.identity());

Object? _snapshotValue(Object? value, Set<Object> visiting) {
  if (value == null ||
      value is bool ||
      value is NumericId ||
      value is EnumValue) {
    return value;
  }
  if (value is String) {
    _checkUnicode(value);
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw ArgumentError('Non-finite numbers are not GraphQL literals.');
    }
    return value;
  }
  if (value is List<Object?>) {
    if (!visiting.add(value)) {
      throw ArgumentError('Cyclic lists cannot be serialized.');
    }
    try {
      return List<Object?>.unmodifiable(
        value.map((item) => _snapshotValue(item, visiting)),
      );
    } finally {
      visiting.remove(value);
    }
  }
  if (value is Map<Object?, Object?>) {
    if (!visiting.add(value)) {
      throw ArgumentError('Cyclic input objects cannot be serialized.');
    }
    try {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw ArgumentError('Input object keys must be strings.');
        }
        result[_name(key)] = _snapshotValue(entry.value, visiting);
      }
      return Map<String, Object?>.unmodifiable(result);
    } finally {
      visiting.remove(value);
    }
  }
  throw ArgumentError(
    'Unsupported literal value: ${value.runtimeType}. Use a ValueCodec.',
  );
}

// JSON escaping is suitable for GraphQL quoted strings, provided that their
// UTF-16 content represents valid Unicode scalar values.
void _checkUnicode(String value) {
  final units = value.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (i + 1 >= units.length ||
          units[i + 1] < 0xdc00 ||
          units[i + 1] > 0xdfff) {
        throw ArgumentError('String contains an unpaired UTF-16 surrogate.');
      }
      i++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw ArgumentError('String contains an unpaired UTF-16 surrogate.');
    }
  }
}

String _literal(Object? value) {
  if (value is NumericId) return value.value;
  if (value is EnumValue) return value.name;
  if (value is List<Object?>) return '[${value.map(_literal).join(', ')}]';
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '$key: ${_literal(value[key])}').join(', ')}}';
  }
  return jsonEncode(value);
}
