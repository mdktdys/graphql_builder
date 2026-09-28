part of '../graphql_builder.dart';

/// Identifies a selectable object type in a consumer's GraphQL schema.
///
/// Descriptors use identity equality. Declare one shared instance for every
/// object type and reuse it in fields, roots, relations and nodes.
final class NodeType {
  /// A diagnostic label. It is never serialized into a query.
  final String name;

  /// Creates a reusable descriptor for an object type.
  ///
  /// An omitted label is only used for diagnostics. Explicit labels are
  /// validated as GraphQL names.
  NodeType([String? name]) : name = name == null ? 'unnamed type' : _name(name);
}

/// Identifies a root or relation on which arguments may be used.
///
/// The label is descriptive and may contain dots. Scope compatibility is based
/// on descriptor identity rather than the label.
final class ArgumentScope {
  /// A diagnostic label. Scope compatibility uses identity, not this text.
  final String name;

  /// Creates a reusable argument scope with an optional diagnostic label.
  ArgumentScope([String? name]) : name = name ?? 'unnamed scope' {
    if (name != null && name.trim().isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'A scope label must not be empty',
      );
    }
  }
}

/// Declares a selectable field on the query root.
final class QueryRoot {
  /// The GraphQL field name.
  final String name;

  /// The object type selected by this root.
  final NodeType type;

  /// The identity of the arguments accepted by this root.
  ///
  /// A unique scope is created when none is passed to the constructor.
  final ArgumentScope scope;

  /// The pagination convention accepted by this root, if any.
  final PagePagination? pagination;

  /// Creates a root field descriptor.
  QueryRoot(
    String name, {
    NodeType? type,
    ArgumentScope? scope,
    this.pagination,
  }) : name = _name(name),
       type = type ?? NodeType(),
       scope = scope ?? ArgumentScope('root:$name');

  /// Creates another root selecting the same object type with its own scope.
  QueryRoot.withTypeOf(
    String name,
    QueryRoot other, {
    ArgumentScope? scope,
    PagePagination? pagination,
  }) : this(name, type: other.type, scope: scope, pagination: pagination);
}

/// Declares an object-valued field connecting two schema object types.
final class Relation {
  /// The GraphQL field name on [parent].
  final String name;

  /// The object type on which this relation can be selected.
  final NodeType parent;

  /// The object type selected through this relation.
  final NodeType child;

  /// The identity of the arguments accepted by this relation.
  ///
  /// A unique scope is created when none is passed to the constructor.
  final ArgumentScope scope;

  /// The pagination convention accepted by this relation, if any.
  final PagePagination? pagination;

  /// Creates a relation descriptor.
  Relation(
    String name, {
    required this.parent,
    required this.child,
    ArgumentScope? scope,
    this.pagination,
  }) : name = _name(name),
       scope = scope ?? ArgumentScope('relation:$name');

  /// Creates a relation using the object types owned by two roots.
  Relation.betweenRoots(
    String name, {
    required QueryRoot parent,
    required QueryRoot child,
    ArgumentScope? scope,
    PagePagination? pagination,
  }) : this(
         name,
         parent: parent.type,
         child: child.type,
         scope: scope,
         pagination: pagination,
       );
}

/// A selectable scalar field belonging to an object type.
///
/// Use [ScalarField] when the same field can be filtered, or [ComparableField]
/// when the server also supports range filters for it.
class Field {
  /// The GraphQL field name.
  final String name;

  /// The object type on which this field can be selected.
  final NodeType owner;

  /// Creates a selectable field without filtering or sorting capabilities.
  Field(String name, {required Object owner})
    : name = _name(name),
      owner = _fieldOwner(owner);
}

NodeType _fieldOwner(Object owner) {
  if (owner is NodeType) return owner;
  if (owner is QueryRoot) return owner.type;
  throw ArgumentError.value(
    owner,
    'owner',
    'Expected a node type or query root',
  );
}

/// A schema member usable by filter operators.
abstract interface class FilterField<T> {
  /// The server's argument names, supported operators and value conversion.
  InputDefinition<T> get input;
}

/// A filterable member that can be used with range operators.
///
/// Each individual range operator must also be enabled by [input].
abstract interface class OrderedField<T> implements FilterField<T> {}

/// A selectable scalar field with explicitly declared filtering capabilities.
class ScalarField<T> extends Field implements FilterField<T> {
  @override
  final InputDefinition<T> input;

  /// Creates a scalar whose selection name defaults to [InputDefinition.name].
  ScalarField({required super.owner, required this.input, String? name})
    : super(name ?? input.name);
}

/// A selectable, filterable scalar that may support range comparisons.
final class ComparableField<T> extends ScalarField<T>
    implements OrderedField<T> {
  /// Creates a comparable scalar whose selection name defaults to its input.
  ComparableField({required super.owner, required super.input, super.name});
}

/// A filterable argument which cannot be added to a node's selection.
final class ArgumentField<T> implements FilterField<T> {
  @override
  final InputDefinition<T> input;

  /// Creates a filter-only schema member.
  ArgumentField(this.input);
}

/// Operators supported by this builder's flat-argument filtering convention.
///
/// GraphQL itself does not define filter operators. Consumers explicitly enable
/// the operators supported by their server and may override their wire names.
enum FilterOperator {
  /// Equality, using the input name unchanged by default.
  equal,

  /// Boolean equality, using the `__Is` suffix by default.
  boolean,

  /// A strict lower bound, using the `__Gt` suffix by default.
  greaterThan,

  /// An inclusive lower bound, using the `__Gte` suffix by default.
  greaterOrEqual,

  /// A strict upper bound, using the `__Lt` suffix by default.
  lessThan,

  /// An inclusive upper bound, using the `__Lte` suffix by default.
  lessOrEqual,

  /// Membership in a list, using the `__In` suffix by default.
  inList,

  /// Exclusion from a list, using the `__NotIn` suffix by default.
  notInList,

  /// A server-defined pattern match, using the `__ILike` suffix by default.
  like,

  /// Null testing, using the `__Null` suffix by default.
  isNull,

  /// Non-null testing, using the `__NotNull` suffix by default.
  isNotNull,
}

/// Immutable metadata describing one filterable server input.
final class InputDefinition<T> {
  /// The default field name and prefix used for generated argument names.
  final String name;

  /// Converts caller values into GraphQL literal values.
  final ValueCodec<T> codec;

  /// The nonempty set of root and relation scopes accepting this input.
  final Set<ArgumentScope> scopes;

  /// The operators explicitly supported by this server input.
  final Set<FilterOperator> operators;

  /// Full wire names overriding the default names for individual operators.
  final Map<FilterOperator, String> argumentNames;

  /// The full boolean sort argument name, or null when sorting is unsupported.
  final String? sortArgument;

  /// Creates and freezes a server input definition.
  ///
  /// An empty [operators] set is valid for an input used only for sorting.
  /// Override keys must refer to enabled operators.
  InputDefinition(
    String name, {
    required this.codec,
    required Set<ArgumentScope> scopes,
    required Set<FilterOperator> operators,
    Map<FilterOperator, String> argumentNames = const {},
    String? sortArgument,
  }) : name = _name(name),
       scopes = Set<ArgumentScope>.unmodifiable(scopes),
       operators = Set<FilterOperator>.unmodifiable(operators),
       argumentNames = Map<FilterOperator, String>.unmodifiable(argumentNames),
       sortArgument = sortArgument == null ? null : _name(sortArgument) {
    if (this.scopes.isEmpty) {
      throw ArgumentError.value(
        scopes,
        'scopes',
        'At least one scope is required',
      );
    }
    for (final entry in this.argumentNames.entries) {
      _name(entry.value);
      if (!this.operators.contains(entry.key)) {
        throw ArgumentError(
          'An argument name override requires an enabled operator: ${entry.key}',
        );
      }
    }
  }

  /// Validates, converts and deeply freezes an input value.
  ///
  /// Validation stays bound to this definition's codec even when its generic
  /// type is widened to `Object?` by a collection of heterogeneous filters.
  Object? encode(Object? value) => _snapshot(codec.encode(value));

  /// Returns the validated wire argument name for a supported operator.
  ///
  /// Null tests additionally require a codec created with [ValueCodec.nullable].
  String argumentName(FilterOperator op) {
    if (!operators.contains(op)) {
      throw ArgumentError('Operator $op is not supported by input $name');
    }
    if ((op == FilterOperator.isNull || op == FilterOperator.isNotNull) &&
        !codec.acceptsNull) {
      throw ArgumentError('Input $name does not support null tests');
    }
    final override = argumentNames[op];
    if (override != null) return override;
    final suffix = switch (op) {
      FilterOperator.equal => '',
      FilterOperator.boolean => '__Is',
      FilterOperator.greaterThan => '__Gt',
      FilterOperator.greaterOrEqual => '__Gte',
      FilterOperator.lessThan => '__Lt',
      FilterOperator.lessOrEqual => '__Lte',
      FilterOperator.inList => '__In',
      FilterOperator.notInList => '__NotIn',
      FilterOperator.like => '__ILike',
      FilterOperator.isNull => '__Null',
      FilterOperator.isNotNull => '__NotNull',
    };
    return '$name$suffix';
  }
}

/// A zero-based page request independent of the server's argument convention.
final class Page {
  /// The zero-based page index.
  final int index;

  /// A positive page size, or null to use the server's default.
  final int? size;

  /// Creates a validated page request.
  Page({this.index = 0, this.size}) {
    if (index < 0) {
      throw ArgumentError.value(
        index,
        'index',
        'A page index must be nonnegative',
      );
    }
    if (size != null && size! <= 0) {
      throw ArgumentError.value(size, 'size', 'A page size must be positive');
    }
  }
}

/// Declares the argument names and page offset accepted by a root or relation.
final class PagePagination {
  /// The argument carrying the page index.
  final String pageArgument;

  /// The argument carrying the requested page size.
  final String perPageArgument;

  /// The server's first page number, added to the zero-based requested index.
  final int firstPage;

  /// Creates a pagination convention with distinct, valid argument names.
  PagePagination({
    String pageArgument = 'page',
    String perPageArgument = 'perPage',
    this.firstPage = 0,
  }) : pageArgument = _name(pageArgument),
       perPageArgument = _name(perPageArgument) {
    if (this.pageArgument == this.perPageArgument) {
      throw ArgumentError('Page and page-size argument names must be distinct');
    }
    if (firstPage < 0) {
      throw ArgumentError.value(
        firstPage,
        'firstPage',
        'The first page number must be nonnegative',
      );
    }
  }

  /// Converts a page into immutable GraphQL arguments for this convention.
  Map<String, Object?> encode(Page page) => Map<String, Object?>.unmodifiable({
    pageArgument: page.index + firstPage,
    if (page.size != null) perPageArgument: page.size,
  });
}

/// The boolean sorting convention supported by [SortBy].
enum SortDirection {
  /// Produces `true` for the declared sorting argument.
  ascending,

  /// Produces `false` for the declared sorting argument.
  descending,
}
