part of '../graphql_builder.dart';

/// Validates caller input and converts typed values into GraphQL literals.
///
/// The encoder may return null, booleans, finite numbers, strings, [NumericId],
/// [EnumValue], lists, or maps with valid GraphQL names as string keys. Values
/// returned by custom encoders are validated and frozen by [InputDefinition].
final class ValueCodec<T> {
  final T Function(Object?) _decode;
  final Object? Function(Object?) _encode;

  /// Whether null is accepted as an input, including within list filters.
  final bool acceptsNull;

  /// Creates a non-nullable codec with explicit validation and serialization.
  ///
  /// [decode] must validate its input and throw for unsupported values. Use
  /// [nullable] to opt into null input and null-test operators.
  ValueCodec({
    required T Function(Object?) decode,
    required Object? Function(T) encode,
  }) : _decode = decode,
       _encode = ((Object? value) => encode(decode(value))),
       acceptsNull = false;

  ValueCodec._({
    required T Function(Object?) decode,
    required Object? Function(Object?) encode,
  }) : _decode = decode,
       _encode = encode,
       acceptsNull = true;

  /// Validates and converts caller input into the codec's Dart value type.
  T read(Object? value) {
    _checkNull(value);
    return _decode(value);
  }

  /// Validates caller input and returns its encoded literal representation.
  ///
  /// The encoder captures its original typed decoder, so widening a codec's
  /// generic type cannot bypass validation before the typed encoder is called.
  Object? encode(Object? value) {
    _checkNull(value);
    return _encode(value);
  }

  /// Returns a codec that also accepts null and enables null-test operators.
  ValueCodec<T?> nullable() => ValueCodec<T?>._(
    decode: (value) => value == null ? null : read(value),
    encode: (value) => value == null ? null : encode(value),
  );

  void _checkNull(Object? value) {
    if (value == null && !acceptsNull) {
      throw ArgumentError('Null requires a nullable value codec');
    }
  }
}

/// Reusable codecs for common scalar inputs.
abstract final class ValueCodecs {
  /// Accepts only boolean values.
  static final ValueCodec<bool> boolean = ValueCodec<bool>(
    decode: (value) {
      if (value is bool) return value;
      throw ArgumentError.value(value, 'value', 'Expected a boolean');
    },
    encode: (value) => value,
  );

  /// Accepts finite integer and floating-point values.
  static final ValueCodec<num> number = ValueCodec<num>(
    decode: (value) {
      if (value is num && value.isFinite) return value;
      throw ArgumentError.value(value, 'value', 'Expected a finite number');
    },
    encode: (value) => value,
  );

  /// Accepts only Dart integers, without parsing strings or truncating doubles.
  static final ValueCodec<int> integer = ValueCodec<int>(
    decode: (value) {
      if (value is int) return value;
      throw ArgumentError.value(value, 'value', 'Expected an integer');
    },
    encode: (value) => value,
  );

  /// Accepts only strings; GraphQL escaping is performed during serialization.
  static final ValueCodec<String> string = ValueCodec<String>(
    decode: (value) {
      if (value is String) return value;
      throw ArgumentError.value(value, 'value', 'Expected a string');
    },
    encode: (value) => value,
  );

  /// Accepts [NumericId], nonnegative integers, or strings of ASCII digits.
  ///
  /// This models APIs expecting unquoted numeric IDs. Use [string] for general
  /// GraphQL IDs, including alphanumeric identifiers.
  static final ValueCodec<NumericId> numericId = ValueCodec<NumericId>(
    decode: (value) {
      if (value is NumericId) return value;
      if (value is String) return NumericId(value);
      if (value is int && value >= 0) return NumericId(value.toString());
      throw ArgumentError.value(value, 'value', 'Expected a numeric ID');
    },
    encode: (value) => value,
  );

  /// Accepts [DateTime] and formats it as a GraphQL string literal.
  ///
  /// Formatting is explicit because servers use different date/time scalar
  /// formats and timezone conventions.
  static ValueCodec<DateTime> dateTime({
    required String Function(DateTime) format,
  }) => ValueCodec<DateTime>(
    decode: (value) {
      if (value is DateTime) return value;
      throw ArgumentError.value(value, 'value', 'Expected a DateTime');
    },
    encode: format,
  );
}

/// An unquoted, nonnegative numeric identifier of arbitrary decimal length.
///
/// Leading zeros are rejected, except for `0`, so the resulting GraphQL integer
/// literal is valid. No conversion to a Dart integer is required.
final class NumericId {
  /// The canonical digits used in the GraphQL literal.
  final String value;

  /// Creates an identifier from a nonempty sequence of ASCII digits.
  NumericId(String value) : value = _validateNumericId(value);

  @override
  String toString() => value;
}

String _validateNumericId(String value) {
  final match = RegExp(r'^(0|[1-9][0-9]*)$').firstMatch(value);
  if (match == null || match.end != value.length) {
    throw ArgumentError.value(
      value,
      'value',
      'Expected ASCII digits without leading zeros',
    );
  }
  return value;
}

/// A validated, unquoted GraphQL enum literal.
final class EnumValue {
  /// The enum member name.
  final String name;

  /// Creates an enum literal, rejecting GraphQL's boolean and null keywords.
  EnumValue(String name) : name = _name(name) {
    if (name == 'null' || name == 'true' || name == 'false') {
      throw ArgumentError.value(name, 'name', 'Reserved GraphQL literal');
    }
  }

  @override
  String toString() => name;
}
