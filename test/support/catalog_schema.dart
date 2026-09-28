import 'package:graphql_builder/graphql_builder.dart';

class Book {}

class Author {}

class CatalogSchema {
  final bookType = NodeType('Book');
  final authorType = NodeType('Author');
  final booksScope = ArgumentScope('catalog.books');
  final featuredScope = ArgumentScope('catalog.featured');
  final contributorsScope = ArgumentScope('book.contributors');

  late final books = QueryRoot(
    'books',
    type: bookType,
    scope: booksScope,
    pagination: PagePagination(),
  );
  late final featured = QueryRoot(
    'featuredBooks',
    type: bookType,
    scope: featuredScope,
  );
  late final contributors = Relation(
    'contributors',
    parent: bookType,
    child: authorType,
    scope: contributorsScope,
    pagination: PagePagination(),
  );
  late final editor = Relation(
    'editor',
    parent: bookType,
    child: authorType,
    scope: contributorsScope,
  );
  late final id = ScalarField<NumericId>(
    owner: bookType,
    input: InputDefinition<NumericId>(
      'id',
      codec: ValueCodecs.numericId,
      scopes: {booksScope, featuredScope},
      operators: {FilterOperator.equal, FilterOperator.inList},
    ),
  );
  late final title = ScalarField<String>(
    owner: bookType,
    input: InputDefinition<String>(
      'title',
      codec: ValueCodecs.string,
      scopes: {booksScope, featuredScope},
      operators: {FilterOperator.equal, FilterOperator.like},
      sortArgument: 'title__OrderBy',
    ),
  );
  late final available = ScalarField<bool>(
    owner: bookType,
    input: InputDefinition<bool>(
      'available',
      codec: ValueCodecs.boolean,
      scopes: {booksScope},
      operators: {FilterOperator.boolean, FilterOperator.equal},
    ),
  );
  late final price = ComparableField<num>(
    owner: bookType,
    input: InputDefinition<num>(
      'price',
      codec: ValueCodecs.number,
      scopes: {booksScope, featuredScope},
      operators: {
        FilterOperator.equal,
        FilterOperator.greaterThan,
        FilterOperator.greaterOrEqual,
        FilterOperator.lessThan,
        FilterOperator.lessOrEqual,
        FilterOperator.inList,
        FilterOperator.notInList,
      },
      sortArgument: 'price__OrderBy',
    ),
  );
  late final published = ComparableField<DateTime>(
    owner: bookType,
    input: InputDefinition<DateTime>(
      'published',
      codec: ValueCodecs.dateTime(format: (date) => date.toIso8601String()),
      scopes: {booksScope},
      operators: {FilterOperator.greaterOrEqual, FilterOperator.lessThan},
    ),
  );
  late final ownerIds = ArgumentField<NumericId>(
    InputDefinition<NumericId>(
      'owner_ids',
      codec: ValueCodecs.numericId,
      scopes: {booksScope},
      operators: {FilterOperator.inList},
    ),
  );
  late final optionalNumber = ArgumentField<int?>(
    InputDefinition<int?>(
      'edition',
      codec: ValueCodecs.integer.nullable(),
      scopes: {booksScope},
      operators: {
        FilterOperator.equal,
        FilterOperator.inList,
        FilterOperator.isNull,
        FilterOperator.isNotNull,
      },
    ),
  );
  late final authorId = Field('id', owner: authorType);
  late final authorName = Field('name', owner: authorType);
  late final authorActive = ScalarField<bool>(
    owner: authorType,
    input: InputDefinition<bool>(
      'active',
      codec: ValueCodecs.boolean,
      scopes: {contributorsScope},
      operators: {FilterOperator.boolean},
    ),
  );

  Node bookNode({String? alias}) => Node(bookType, root: books, alias: alias);
  Node authorNode({String? alias}) =>
      Node(authorType, relation: contributors, alias: alias);
  String render(Node node) => (Query()..add(node)).build().query;
}

/// Verifies subclassing through the package's public entry point.
class CatalogBookNode extends Node {
  CatalogBookNode(CatalogSchema schema)
    : super(schema.bookType, root: schema.books);
}
