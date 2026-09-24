part of '../graphql_builder.dart';

const _omitted = _Omitted();

final class _Omitted {
  const _Omitted();
}

/// A filter operator, optionally bound to an immutable value snapshot.
///
/// Use a concrete operator with [Filters.add]. A value can be supplied either
/// to its constructor or to `add`, but never both.
sealed class Filter {
  final InputDefinition<Object?> _input;
  final FilterOperator _operator;
  final _Argument? _bound;

  Filter._(this._input, this._operator, [Object? value = _omitted])
    : _bound = identical(value, _omitted)
          ? null
          : _makeArgument(_input, _operator, value) {
    // Validate capability even for an operator that has not been bound yet.
    _input.argumentName(_operator);
  }

  _Argument _resolve(Object? value) {
    if (_bound != null) {
      if (!identical(value, _omitted)) {
        throw ArgumentError('This filter already has a value.');
      }
      return _bound;
    }
    if (identical(value, _omitted)) {
      throw ArgumentError('Missing value for ${_input.name}.');
    }
    return _makeArgument(_input, _operator, value);
  }
}

/// Boolean comparison. Defaults to the `__Is` argument convention.
final class BooleanFilter extends Filter {
  BooleanFilter(FilterField<bool> field, [Object? value = _omitted])
    : super._(field.input, FilterOperator.boolean, value);
}

/// Strict greater-than comparison on an ordered field.
final class GreaterThanFilter<T> extends Filter {
  GreaterThanFilter(OrderedField<T> field, [Object? value = _omitted])
    : super._(field.input, FilterOperator.greaterThan, value);
}

/// Inclusive lower bound on an ordered field.
final class GreaterOrEqualFilter<T> extends Filter {
  GreaterOrEqualFilter(OrderedField<T> field, [Object? value = _omitted])
    : super._(field.input, FilterOperator.greaterOrEqual, value);
}

/// Strict less-than comparison on an ordered field.
final class LessThanFilter<T> extends Filter {
  LessThanFilter(OrderedField<T> field, [Object? value = _omitted])
    : super._(field.input, FilterOperator.lessThan, value);
}

/// Inclusive upper bound on an ordered field.
final class LessOrEqualFilter<T> extends Filter {
  LessOrEqualFilter(OrderedField<T> field, [Object? value = _omitted])
    : super._(field.input, FilterOperator.lessOrEqual, value);
}

/// Equality using the argument name declared by the field.
final class EqualFilter<T> extends Filter {
  EqualFilter(FilterField<T> field, [Object? value = _omitted])
    : super._(field.input, FilterOperator.equal, value);
}

/// Membership in a list. Each element is decoded by the field's codec.
final class InFilter<T> extends Filter {
  InFilter(FilterField<T> field, [Object? values = _omitted])
    : super._(field.input, FilterOperator.inList, values);
}

/// Exclusion from a list. Each element is decoded by the field's codec.
final class NotInFilter<T> extends Filter {
  NotInFilter(FilterField<T> field, [Object? values = _omitted])
    : super._(field.input, FilterOperator.notInList, values);
}

/// Case-insensitive pattern argument. Does not insert `%` or change the pattern.
final class LikeFilter extends Filter {
  LikeFilter(FilterField<String> field, [Object? value = _omitted])
    : super._(field.input, FilterOperator.like, value);
}

/// A bound null check. Requires a nullable codec and an enabled operator.
final class NullFilter<T> extends Filter {
  NullFilter(FilterField<T?> field)
    : super._(field.input, FilterOperator.isNull, true);
}

/// A bound non-null check. Requires a nullable codec and an enabled operator.
final class NotNullFilter<T> extends Filter {
  NotNullFilter(FilterField<T?> field)
    : super._(field.input, FilterOperator.isNotNull, true);
}

/// A mutable collection of arguments, copied when added to a [Node].
///
/// Both `add(BooleanFilter(field), true)` and `add(InFilter(field, [1, 2]))`
/// are supported. The separate value has type [Object] and is validated by
/// the field's codec; omitted and explicit `null` are distinct.
final class Filters {
  final List<_Argument> _arguments = [];

  /// Adds a bound filter or binds an operator to [value].
  ///
  /// Conflicting values are rejected without modifying this collection.
  void add(Filter filter, [Object? value = _omitted]) {
    _appendArguments(_arguments, [filter._resolve(value)]);
  }
}

_Argument _makeArgument(
  InputDefinition<Object?> input,
  FilterOperator op,
  Object? value,
) {
  final name = input.argumentName(op);
  final Object? encoded;
  switch (op) {
    case FilterOperator.inList:
    case FilterOperator.notInList:
      if (value is! List<Object?>) {
        throw ArgumentError('Expected a list for ${input.name}.');
      }
      encoded = value.map(input.encode).toList();
    case FilterOperator.isNull:
    case FilterOperator.isNotNull:
      encoded = true;
    default:
      encoded = input.encode(value);
  }
  return _Argument(name, encoded, input.scopes);
}

/// Ordering via an explicitly declared [InputDefinition.sortArgument].
///
/// The flat argument convention encodes ascending as `true`, descending as
/// `false`. Fields without a sort argument cannot be used here.
final class SortBy<T> {
  final _Argument _argument;

  SortBy(FilterField<T> field, SortDirection direction)
    : _argument = _sortArgument(field.input, direction);
}

_Argument _sortArgument(
  InputDefinition<Object?> input,
  SortDirection direction,
) {
  final name = input.sortArgument;
  if (name == null) {
    throw ArgumentError('Sorting is not enabled for ${input.name}.');
  }
  return _Argument(name, direction == SortDirection.ascending, input.scopes);
}

final class _Argument {
  final String name;
  final Object? value;
  final Set<ArgumentScope> scopes;

  _Argument(String name, Object? value, Set<ArgumentScope> scopes)
    : name = _name(name),
      value = _snapshot(value),
      scopes = Set.unmodifiable(scopes);
}

// Copy before applying changes so failed merges leave the target untouched.
void _appendArguments(List<_Argument> target, Iterable<_Argument> incoming) {
  final merged = {for (final arg in target) arg.name: arg};
  for (final arg in incoming) {
    final previous = merged[arg.name];
    if (previous != null) {
      if (_literal(previous.value) != _literal(arg.value)) {
        throw StateError('Conflicting argument: ${arg.name}.');
      }
      final scopes = previous.scopes.intersection(arg.scopes);
      if (scopes.isEmpty) {
        throw StateError('Argument ${arg.name} has incompatible scopes.');
      }
      merged[arg.name] = _Argument(arg.name, arg.value, scopes);
    } else {
      merged[arg.name] = arg;
    }
  }
  target
    ..clear()
    ..addAll(merged.values);
}
