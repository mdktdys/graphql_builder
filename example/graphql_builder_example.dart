import 'package:graphql_builder/graphql_builder.dart';

// This is an illustrative schema, not a request to a running service.
void main() {
  final author = AuthorNode()
    ..add(AuthorFields.id)
    ..add(AuthorFields.name);

  final commonFields =
      (BookNode()
            ..add(BookFields.id)
            ..add(BookFields.title)
            ..addNode(author))
          .freeze();

  final filters = Filters()
    ..add(BooleanFilter(BookFields.available), true)
    ..add(GreaterThanFilter(BookFields.price), 600)
    ..add(InFilter(BookFields.authorIds, [1, 2, 3, 4]));

  final books = BookNode()
    ..addAll(commonFields)
    ..add(BookFields.price)
    ..addFilters(filters)
    ..addSort(SortBy(BookFields.price, SortDirection.ascending))
    ..paginate(Page(index: 0, size: 20));

  final query = Query(name: 'AvailableBooks')..add(books);
  final request = query.build();

  // Pass request.toJson() to your authenticated HTTP transport, or pass
  // request.query to an existing method that creates the GraphQL JSON body.
  print(request.toJsonString());
}

abstract final class BookShape {}

abstract final class AuthorShape {}

abstract final class BookSchema {
  static final type = NodeType<BookShape>('Book');
  static final listScope = ArgumentScope('Book.list');
  static final list = QueryRoot<BookShape>(
    'books',
    type: type,
    scope: listScope,
    pagination: PagePagination(),
  );
  static final author = Relation<BookShape, AuthorShape>(
    'author',
    parent: type,
    child: AuthorSchema.type,
    scope: ArgumentScope('Book.author'),
  );
}

abstract final class AuthorSchema {
  static final type = NodeType<AuthorShape>('Author');
}

abstract final class BookFields {
  static final id = Field<BookShape>('id', owner: BookSchema.type);
  static final title = Field<BookShape>('title', owner: BookSchema.type);
  static final available = ScalarField<BookShape, bool>(
    owner: BookSchema.type,
    input: InputDefinition<bool>(
      'available',
      codec: ValueCodecs.boolean,
      scopes: {BookSchema.listScope},
      operators: {FilterOperator.boolean},
    ),
  );
  static final price = ComparableField<BookShape, num>(
    owner: BookSchema.type,
    input: InputDefinition<num>(
      'price',
      codec: ValueCodecs.number,
      scopes: {BookSchema.listScope},
      operators: {FilterOperator.greaterThan},
      sortArgument: 'price__OrderBy',
    ),
  );

  // The input is filter-only; it is not a selectable field in this schema.
  static final authorIds = ArgumentField<NumericId>(
    InputDefinition<NumericId>(
      'author_id',
      codec: ValueCodecs.numericId,
      scopes: {BookSchema.listScope},
      operators: {FilterOperator.inList},
    ),
  );
}

abstract final class AuthorFields {
  static final id = Field<AuthorShape>('id', owner: AuthorSchema.type);
  static final name = Field<AuthorShape>('name', owner: AuthorSchema.type);
}

final class BookNode extends Node<BookShape> {
  BookNode() : super(BookSchema.type, root: BookSchema.list);
}

final class AuthorNode extends Node<AuthorShape> {
  AuthorNode() : super(AuthorSchema.type, relation: BookSchema.author);
}
