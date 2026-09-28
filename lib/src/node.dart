part of '../graphql_builder.dart';

/// An immutable reusable selection, including its arguments and pagination.
///
/// Produced by [Node.freeze]. [Node.addAll] never silently discards filters.
final class Selection {
  final NodeType type;
  final List<_Field> _fields;
  final List<_Argument> _arguments;
  final Page? _page;

  Selection._(
    this.type,
    Iterable<_Field> fields,
    Iterable<_Argument> arguments,
    this._page,
  ) : _fields = _merge(fields),
      _arguments = List.unmodifiable(arguments);
}

/// A mutable builder for fields, nested nodes and scoped arguments.
///
/// Consumer packages may extend this class to expose their own named nodes.
/// Use one shared [NodeType] instance for each schema object type. [root] and
/// [relation] describe where a node is placed, independently of its type.
class Node {
  final NodeType type;
  final QueryRoot? root;
  final Relation? relation;
  final String? alias;
  final List<_Field> _fields = [];
  final List<_Argument> _arguments = [];
  Page? _page;

  /// Creates a selection from a root, relation or explicit node type.
  ///
  /// Passing a root or relation also binds this node to that location.
  Node(Object source, {QueryRoot? root, Relation? relation, this.alias})
    : type = _nodeTypeFrom(source),
      root = source is QueryRoot ? source : root,
      relation = source is Relation ? source : relation {
    if (alias != null) _name(alias!);
    if (source is QueryRoot && (root != null || relation != null)) {
      throw ArgumentError('A root source cannot have another binding.');
    }
    if (source is Relation && (root != null || relation != null)) {
      throw ArgumentError('A relation source cannot have another binding.');
    }
    if (this.root != null && !identical(this.root!.type, type)) {
      throw ArgumentError('Root and node types do not match.');
    }
    if (this.relation != null && !identical(this.relation!.child, type)) {
      throw ArgumentError('Relation and node child types do not match.');
    }
  }

  /// Creates a node using the type descriptor owned by [root].
  Node.fromRoot(QueryRoot root, {String? alias}) : this(root, alias: alias);

  /// Creates a node using the child type descriptor of [relation].
  Node.fromRelation(Relation relation, {String? alias})
    : this(relation, alias: alias);

  /// Adds a scalar selection, checking its owner when one was declared.
  void add(Field field) {
    if (field.owner != null && !identical(field.owner, type)) {
      throw ArgumentError('Field ${field.name} belongs to a different type.');
    }
    _appendFields(_fields, [_Field(field.name)]);
  }

  /// Copies the current contents of [filters].
  void addFilters(Filters filters) {
    _appendArguments(_arguments, filters._arguments);
  }

  /// Adds an immutable selection, preserving its filters and pagination.
  ///
  /// A conflict leaves this builder unchanged. Root/relation capabilities are
  /// checked when the node is attached to its final location.
  void addAll(Selection selection) {
    if (!identical(selection.type, type)) {
      throw ArgumentError('Selection belongs to a different type.');
    }
    final page = _mergePage(_page, selection._page);
    final fields = _merge([..._fields, ...selection._fields]);
    final arguments = [..._arguments];
    _appendArguments(arguments, selection._arguments);
    _fields
      ..clear()
      ..addAll(fields);
    _arguments
      ..clear()
      ..addAll(arguments);
    _page = page;
  }

  /// Takes a deep immutable snapshot. Empty selections are rejected.
  Selection freeze() => Selection._(type, _fields, _arguments, _page);

  /// Takes a snapshot of [child] under [via] or its constructor's relation.
  ///
  /// A relation is always required: the same child type can be attached through
  /// several different fields, so selecting one implicitly is ambiguous.
  void addNode(Node child, {Relation? via}) {
    final binding = via ?? child.relation;
    if (binding == null) {
      throw StateError('Specify a relation on the child node or pass via.');
    }
    if (!identical(binding.parent, type) ||
        !identical(binding.child, child.type)) {
      throw ArgumentError(
        'Relation ${binding.name} does not match these nodes.',
      );
    }
    final snapshot = child.freeze();
    final field = _Field(
      binding.name,
      alias: child.alias,
      arguments: _bindArguments(snapshot, binding.scope, binding.pagination),
      children: snapshot._fields,
    );
    _appendFields(_fields, [field]);
  }

  /// Adds zero-based pagination, interpreted by the final root/relation.
  ///
  /// The target must declare [PagePagination]. Repeating the same page is a
  /// no-op; conflicting pages are rejected.
  void paginate(Page page) {
    _page = _mergePage(_page, page);
  }

  /// Adds an explicitly supported sort argument.
  void addSort<T>(SortBy<T> sort) {
    _appendArguments(_arguments, [sort._argument]);
  }
}

NodeType _nodeTypeFrom(Object source) {
  if (source is NodeType) return source;
  if (source is QueryRoot) return source.type;
  if (source is Relation) return source.child;
  throw ArgumentError.value(
    source,
    'source',
    'Expected a node type, query root or relation',
  );
}

Page? _mergePage(Page? previous, Page? next) {
  if (previous != null &&
      next != null &&
      (previous.index != next.index || previous.size != next.size)) {
    throw StateError('Conflicting pagination.');
  }
  return next ?? previous;
}

Map<String, Object?> _bindArguments(
  Selection selection,
  ArgumentScope scope,
  PagePagination? pagination,
) {
  final result = <String, Object?>{};
  for (final arg in selection._arguments) {
    final allowedScopes = arg.scopes;
    if (allowedScopes != null && !allowedScopes.contains(scope)) {
      throw StateError('${arg.name} is not available in scope ${scope.name}.');
    }
    result[arg.name] = arg.value;
  }
  final page = selection._page;
  if (page != null) {
    if (pagination == null) {
      throw StateError('Pagination is not enabled in scope ${scope.name}.');
    }
    for (final entry in pagination.encode(page).entries) {
      if (result.containsKey(entry.key) &&
          _literal(result[entry.key]) != _literal(entry.value)) {
        throw StateError('Conflicting pagination argument: ${entry.key}.');
      }
      result[entry.key] = entry.value;
    }
  }
  return result;
}
