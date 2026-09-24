part of '../graphql_builder.dart';

/// An immutable compiled request, independent of any HTTP client.
///
/// Version 0.1 emits inline argument literals. [variables] is empty, matching
/// clients that already accept a query string. Server errors and response
/// decoding are responsibilities of the consuming application.
final class GraphRequest {
  final String query;
  final String? operationName;
  final Map<String, Object?> variables = const {};

  GraphRequest._(this.query, this.operationName);

  /// Produces a fresh JSON envelope ready for an application transport.
  Map<String, Object?> toJson() => {
    'query': query,
    'variables': variables,
    if (operationName != null) 'operationName': operationName,
  };

  /// Serializes the envelope as JSON text, for existing raw-body transports.
  String toJsonString() => jsonEncode(toJson());
}

/// Combines snapshots of root nodes into one GraphQL query document.
final class Query {
  final String? name;
  final List<_Field> _roots = [];

  Query({this.name}) {
    if (name != null) _name(name!);
  }

  /// Takes a snapshot of a root node and validates its argument scope.
  void add<S>(Node<S> node) {
    if (node.relation != null) {
      throw StateError('A relation-bound node cannot be added as a root.');
    }
    final root = node.root;
    if (root == null) throw StateError('The node has no query root.');
    final snapshot = node.freeze();
    final field = _Field(
      root.name,
      alias: node.alias,
      arguments: _bindArguments(snapshot, root.scope, root.pagination),
      children: snapshot._fields,
    );
    _appendFields(_roots, [field]);
  }

  /// Merges repeated selections and rejects empty or conflicting queries.
  GraphRequest build() {
    final operation = name == null ? 'query' : 'query $name';
    final fields = _merge(_roots);
    return GraphRequest._('$operation {\n${_renderFields(fields, 1)}\n}', name);
  }
}
