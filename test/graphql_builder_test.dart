import 'dart:convert';
import 'package:graphql_builder/graphql_builder.dart';
import 'package:test/test.dart';
import 'support/catalog_schema.dart';

Matcher get rejects => throwsA(anyOf(isA<ArgumentError>(), isA<StateError>()));

/// Ignore formatting while preserving whitespace inside quoted literals.
String compact(String query) {
  final output = StringBuffer();
  var inString = false;
  var escaped = false;
  for (final rune in query.runes) {
    final character = String.fromCharCode(rune);
    if (inString) {
      output.write(character);
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '"') {
        inString = false;
      }
    } else if (character == '"') {
      inString = true;
      output.write(character);
    } else if (!RegExp(r'\s').hasMatch(character)) {
      output.write(character);
    }
  }
  return output.toString();
}

void main() {
  late CatalogSchema s;
  setUp(() => s = CatalogSchema());

  group('declaration API', () {
    test('mixed bound and unbound filters work with public Node subclass', () {
      final filters = Filters()
        ..add(BooleanFilter(s.available), true)
        ..add(GreaterThanFilter(s.price), 600)
        ..add(InFilter(s.ownerIds, [1, 2, 3, 4]));
      final books = CatalogBookNode(s)
        ..add(s.id)
        ..add(s.price)
        ..addNode(s.authorNode()..add(s.authorId))
        ..addFilters(filters);
      final result = compact(s.render(books));
      expect(result, contains('available__Is:true'));
      expect(result, contains('price__Gt:600'));
      expect(result, contains('owner_ids__In:[1,2,3,4]'));
      expect(result, contains('{idpricecontributors{id}}'));
    });

    test('all value operators support bound and unbound syntax', () {
      final bound = Filters()
        ..add(EqualFilter(s.title, 'Dart'))
        ..add(BooleanFilter(s.available, false))
        ..add(GreaterThanFilter(s.price, 1))
        ..add(GreaterOrEqualFilter(s.price, 2))
        ..add(LessThanFilter(s.price, 10))
        ..add(LessOrEqualFilter(s.price, 9))
        ..add(InFilter(s.price, [2, 3]))
        ..add(NotInFilter(s.price, [4, 5]))
        ..add(LikeFilter(s.title, 'Da%'));
      final unbound = Filters()
        ..add(EqualFilter(s.title), 'Dart')
        ..add(BooleanFilter(s.available), false)
        ..add(GreaterThanFilter(s.price), 1)
        ..add(GreaterOrEqualFilter(s.price), 2)
        ..add(LessThanFilter(s.price), 10)
        ..add(LessOrEqualFilter(s.price), 9)
        ..add(InFilter(s.price), [2, 3])
        ..add(NotInFilter(s.price), [4, 5])
        ..add(LikeFilter(s.title), 'Da%');
      String render(Filters f) => s.render(
        s.bookNode()
          ..add(s.id)
          ..addFilters(f),
      );
      expect(render(bound), render(unbound));
      expect(compact(render(bound)), contains('price__NotIn:[4,5]'));
    });

    test('missing and extra values leave filters unchanged', () {
      final f = Filters()..add(BooleanFilter(s.available), true);
      expect(() => f.add(EqualFilter(s.title)), rejects);
      expect(() => f.add(EqualFilter(s.title, 'A'), 'B'), rejects);
      final query = compact(
        s.render(
          s.bookNode()
            ..add(s.id)
            ..addFilters(f),
        ),
      );
      expect(query, isNot(contains('title')));
      expect(query, contains('available__Is:true'));
    });

    test('explicit null differs from an omitted value', () {
      final f = Filters()..add(EqualFilter(s.optionalNumber), null);
      expect(
        compact(
          s.render(
            s.bookNode()
              ..add(s.id)
              ..addFilters(f),
          ),
        ),
        contains('edition:null'),
      );
      expect(() => Filters()..add(EqualFilter(s.optionalNumber)), rejects);
      expect(() => Filters()..add(EqualFilter(s.title), null), rejects);
    });

    test('null operators are bound and reject an extra value', () {
      final f = Filters()
        ..add(NullFilter(s.optionalNumber))
        ..add(NotNullFilter(s.optionalNumber));
      final query = compact(
        s.render(
          s.bookNode()
            ..add(s.id)
            ..addFilters(f),
        ),
      );
      expect(query, contains('edition__Null:true'));
      expect(query, contains('edition__NotNull:true'));
      expect(() => Filters()..add(NullFilter(s.optionalNumber), true), rejects);
    });
  });

  group('literal codecs', () {
    test('strings cannot inject query syntax', () {
      const value = 'quoted "title"\\path\nnext\trow } injected { a';
      final node = s.bookNode()
        ..add(s.title)
        ..addFilters(Filters()..add(EqualFilter(s.title), value));
      expect(s.render(node), contains(jsonEncode(value)));
    });

    test('numeric IDs retain arbitrary precision', () {
      const large = '900719925474099312345678901234567890';
      final f = Filters()
        ..add(InFilter(s.ownerIds), [1, large, NumericId('23')]);
      expect(
        compact(
          s.render(
            s.bookNode()
              ..add(s.id)
              ..addFilters(f),
          ),
        ),
        contains('owner_ids__In:[1,$large,23]'),
      );
    });

    test('dates require explicit formatting', () {
      final date = DateTime.utc(2026, 9, 24, 10, 20, 30);
      final f = Filters()..add(GreaterOrEqualFilter(s.published), date);
      expect(
        s.render(
          s.bookNode()
            ..add(s.id)
            ..addFilters(f),
        ),
        contains(jsonEncode(date.toIso8601String())),
      );
      expect(() => GreaterOrEqualFilter(s.published, '2026-09-24'), rejects);
    });

    test('nullable lists retain null and zero', () {
      final f = Filters()..add(InFilter(s.optionalNumber), [null, 0, 12]);
      expect(
        compact(
          s.render(
            s.bookNode()
              ..add(s.id)
              ..addFilters(f),
          ),
        ),
        contains('edition__In:[null,0,12]'),
      );
    });

    test('invalid types, non-finite numbers and invalid lists fail', () {
      expect(() => BooleanFilter(s.available, 'true'), rejects);
      expect(() => GreaterThanFilter(s.price, '10'), rejects);
      expect(() => EqualFilter(s.title, 10), rejects);
      expect(() => EqualFilter(s.optionalNumber, 1.5), rejects);
      expect(() => InFilter(s.ownerIds, {1, 2}), rejects);
      expect(() => InFilter(s.ownerIds, [1, null]), rejects);
      expect(() => InFilter(s.ownerIds, [-1]), rejects);
      expect(() => GreaterThanFilter(s.price, double.nan), rejects);
      expect(() => GreaterThanFilter(s.price, double.infinity), rejects);
    });

    test('numeric and enum wrappers validate literals', () {
      for (final value in ['', '-1', '1.0', '1e3', '12a', '1 2']) {
        expect(() => NumericId(value), rejects, reason: value);
      }
      for (final value in [
        '',
        '1READY',
        'NOT-READY',
        'null',
        'true',
        'false',
      ]) {
        expect(() => EnumValue(value), rejects, reason: value);
      }
    });

    test(
      'custom object codecs support literals and snapshot nested values',
      () {
        final options = ArgumentField<Map<String, Object?>>(
          InputDefinition<Map<String, Object?>>(
            'options',
            codec: ValueCodec<Map<String, Object?>>(
              decode: (value) {
                if (value is! Map<String, Object?>) {
                  throw ArgumentError.value(value);
                }
                return value;
              },
              encode: (value) => value,
            ),
            scopes: {s.booksScope},
            operators: {FilterOperator.equal},
          ),
        );
        final nested = <Object?>[EnumValue('READY'), NumericId('12'), null];
        final value = <String, Object?>{'tags': nested, 'enabled': true};
        final node = s.bookNode()
          ..add(s.id)
          ..addFilters(Filters()..add(EqualFilter(options), value));
        nested.add('changed');
        value['enabled'] = false;
        final query = compact(s.render(node));
        expect(query, contains('options:{'));
        expect(query, contains('tags:[READY,12,null]'));
        expect(query, contains('enabled:true'));
        expect(query, isNot(contains('changed')));
      },
    );

    test('custom codecs reject unsupported values and invalid object keys', () {
      ArgumentField<Object?> custom(Object? result) => ArgumentField<Object?>(
        InputDefinition<Object?>(
          'custom',
          codec: ValueCodec<Object?>(
            decode: (value) => value,
            encode: (_) => result,
          ),
          scopes: {s.booksScope},
          operators: {FilterOperator.equal},
        ),
      );
      expect(() => EqualFilter(custom(Object()), 'value'), rejects);
      expect(() => EqualFilter(custom({'not-valid': 1}), 'value'), rejects);
    });

    test('cyclic custom lists and objects fail without recursion overflow', () {
      final custom = ArgumentField<Object?>(
        InputDefinition<Object?>(
          'custom',
          codec: ValueCodec<Object?>(
            decode: (value) => value,
            encode: (value) => value,
          ),
          scopes: {s.booksScope},
          operators: {FilterOperator.equal},
        ),
      );
      final list = <Object?>[];
      list.add(list);
      final map = <String, Object?>{};
      map['self'] = map;
      expect(() => EqualFilter(custom, list), rejects);
      expect(() => EqualFilter(custom, map), rejects);
    });

    test('strings reject unpaired surrogates but accept Unicode pairs', () {
      expect(() => EqualFilter(s.title, String.fromCharCode(0xD800)), rejects);
      expect(() => EqualFilter(s.title, String.fromCharCode(0xDC00)), rejects);
      const title = 'Тест 📚';
      final node = s.bookNode()
        ..add(s.id)
        ..addFilters(Filters()..add(EqualFilter(s.title), title));
      expect(s.render(node), contains(jsonEncode(title)));
    });
  });

  group('schema capabilities and scopes', () {
    test('wire names and sort capability are explicitly declared', () {
      final field = ComparableField<Book, num>(
        owner: s.bookType,
        name: 'price',
        input: InputDefinition<num>(
          'amount',
          codec: ValueCodecs.number,
          scopes: {s.booksScope},
          operators: {FilterOperator.greaterThan},
          argumentNames: {FilterOperator.greaterThan: 'minimumAmount'},
          sortArgument: 'amountDescending',
        ),
      );
      final node = s.bookNode()
        ..add(field)
        ..addFilters(Filters()..add(GreaterThanFilter(field), 4))
        ..addSort(SortBy(field, SortDirection.descending));
      final query = compact(s.render(node));
      expect(query, contains('minimumAmount:4'));
      expect(query, contains('amountDescending:false'));
      expect(query, contains('{price}'));
      expect(query, isNot(contains('amount__Gt')));
    });

    test('undeclared operators and sorting are rejected', () {
      expect(() => EqualFilter(s.ownerIds, 1), rejects);
      expect(() => NotInFilter(s.id, [1]), rejects);
      expect(() => SortBy(s.available, SortDirection.ascending), rejects);
      final equalityOnly = ComparableField<Book, num>(
        owner: s.bookType,
        input: InputDefinition<num>(
          'amount',
          codec: ValueCodecs.number,
          scopes: {s.booksScope},
          operators: {FilterOperator.equal},
        ),
      );
      expect(() => GreaterThanFilter(equalityOnly, 4), rejects);
    });

    test('field and selection type identity cannot be forged by a name', () {
      final lookalike = NodeType<Book>('Book');
      final alien = Field<Book>('id', owner: lookalike);
      final selection = (Node<Book>(lookalike)..add(alien)).freeze();
      final node = s.bookNode()..add(s.title);
      final before = s.render(node);
      expect(() => node.add(alien), rejects);
      expect(() => node.addAll(selection), rejects);
      expect(s.render(node), before);
    });

    test('scopes use identity rather than labels', () {
      final field = ArgumentField<String>(
        InputDefinition<String>(
          'search',
          codec: ValueCodecs.string,
          scopes: {ArgumentScope('catalog.books')},
          operators: {FilterOperator.equal},
        ),
      );
      expect(
        () => Query()
          ..add(
            s.bookNode()
              ..add(s.id)
              ..addFilters(Filters()..add(EqualFilter(field), 'a')),
          ),
        rejects,
      );
    });

    test('root and relation filters cannot cross scopes', () {
      expect(
        () => Query()
          ..add(
            s.bookNode()
              ..add(s.id)
              ..addFilters(Filters()..add(BooleanFilter(s.authorActive), true)),
          ),
        rejects,
      );
      expect(
        () => s.bookNode()
          ..addNode(
            s.authorNode()
              ..add(s.authorId)
              ..addFilters(Filters()..add(BooleanFilter(s.available), true)),
          ),
        rejects,
      );
      expect(
        () => Query()
          ..add(
            Node<Book>(s.bookType, root: s.featured)
              ..add(s.id)
              ..addFilters(Filters()..add(BooleanFilter(s.available), true)),
          ),
        rejects,
      );
    });

    test('equal arguments retain the intersection of supported scopes', () {
      ArgumentField<String> search(Set<ArgumentScope> scopes) =>
          ArgumentField<String>(
            InputDefinition<String>(
              'search',
              codec: ValueCodecs.string,
              scopes: scopes,
              operators: {FilterOperator.equal},
            ),
          );
      final filters = Filters()
        ..add(EqualFilter(search({s.booksScope, s.featuredScope})), 'dart')
        ..add(EqualFilter(search({s.booksScope})), 'dart');
      final query = compact(
        s.render(
          s.bookNode()
            ..add(s.id)
            ..addFilters(filters),
        ),
      );
      expect('search:'.allMatches(query), hasLength(1));
      expect(
        () => Query()
          ..add(
            Node<Book>(s.bookType, root: s.featured)
              ..add(s.id)
              ..addFilters(filters),
          ),
        rejects,
      );
    });

    test('schema capability collections are copied defensively', () {
      final scopes = {s.booksScope};
      final operators = {FilterOperator.equal};
      final names = {FilterOperator.equal: 'search'};
      final input = InputDefinition<String>(
        'term',
        codec: ValueCodecs.string,
        scopes: scopes,
        operators: operators,
        argumentNames: names,
      );
      scopes.clear();
      operators.clear();
      names[FilterOperator.equal] = 'changed';
      final node = s.bookNode()
        ..add(s.id)
        ..addFilters(
          Filters()..add(EqualFilter(ArgumentField<String>(input)), 'dart'),
        );
      expect(compact(s.render(node)), contains('search:"dart"'));
    });
  });

  group('relations and snapshots', () {
    test('a child selection can be reused through explicit relations', () {
      final child = Node<Author>(s.authorType)..add(s.authorId);
      final books = s.bookNode()
        ..addNode(child, via: s.contributors)
        ..addNode(child, via: s.editor);
      final query = compact(s.render(books));
      expect(query, contains('contributors{id}'));
      expect(query, contains('editor{id}'));
    });

    test('via overrides the constructor relation', () {
      final books = s.bookNode()
        ..addNode(s.authorNode()..add(s.authorId), via: s.editor);
      final query = compact(s.render(books));
      expect(query, contains('editor{id}'));
      expect(query, isNot(contains('contributors')));
    });

    test('relations are required and parent/child identities are checked', () {
      final node = s.bookNode()..add(s.id);
      final before = s.render(node);
      final child = Node<Author>(s.authorType)..add(s.authorId);
      final wrongParent = Relation<Book, Author>(
        'contributors',
        parent: NodeType<Book>('Book'),
        child: s.authorType,
        scope: s.contributorsScope,
      );
      final wrongChild = Relation<Book, Author>(
        'contributors',
        parent: s.bookType,
        child: NodeType<Author>('Author'),
        scope: s.contributorsScope,
      );
      expect(() => node.addNode(child), rejects);
      expect(() => node.addNode(child, via: wrongParent), rejects);
      expect(() => node.addNode(child, via: wrongChild), rejects);
      expect(s.render(node), before);
    });

    test('query only accepts roots bound to the same type identity', () {
      expect(() => Query()..add(Node<Book>(s.bookType)..add(s.id)), rejects);
      expect(() => Query()..add(s.authorNode()..add(s.authorId)), rejects);
      expect(
        () => Query()..add(Node<Book>(NodeType<Book>('Book'), root: s.books)),
        rejects,
      );
    });

    test('addNode and Query.add capture deep snapshots', () {
      final child = s.authorNode()
        ..add(s.authorId)
        ..addFilters(Filters()..add(BooleanFilter(s.authorActive), true));
      final books = s.bookNode()..addNode(child);
      final query = Query()..add(books);
      final before = query.build().query;
      child.add(s.authorName);
      books.add(s.title);
      expect(query.build().query, before);
      expect(s.render(books), isNot(contains('name')));
      expect(s.render(books), contains('title'));
    });

    test('adding filters copies caller lists and filter collections', () {
      final ids = <int>[1, 2];
      final f = Filters()..add(InFilter(s.ownerIds), ids);
      final node = s.bookNode()
        ..add(s.id)
        ..addFilters(f);
      ids.add(3);
      f.add(BooleanFilter(s.available), false);
      final query = compact(s.render(node));
      expect(query, contains('owner_ids__In:[1,2]'));
      expect(query, isNot(contains('available__Is')));
    });

    test('freeze captures fields, arguments, nested nodes and pagination', () {
      final child = s.authorNode()..add(s.authorId);
      final source = s.bookNode()
        ..add(s.id)
        ..addNode(child)
        ..addFilters(Filters()..add(BooleanFilter(s.available), true))
        ..paginate(Page(index: 2, size: 10));
      final copy = s.bookNode()..addAll(source.freeze());
      final before = s.render(copy);
      child.add(s.authorName);
      source.add(s.title);
      expect(s.render(copy), before);
      final query = compact(before);
      expect(query, contains('available__Is:true'));
      expect(query, contains('page:2'));
      expect(query, contains('perPage:10'));
      expect(query, contains('contributors{id}'));
      expect(query, isNot(contains('title')));
      expect(query, isNot(contains('name')));
    });
  });

  group('merges and atomic changes', () {
    test('repeated fields and relations merge recursively', () {
      final node = s.bookNode()
        ..add(s.id)
        ..add(s.id)
        ..addNode(s.authorNode()..add(s.authorId))
        ..addNode(s.authorNode()..add(s.authorName));
      final query = compact(s.render(node));
      expect(query, contains('{idcontributors{idname}}'));
      expect('contributors'.allMatches(query), hasLength(1));
    });

    test('aliases allow differing arguments on the same relation', () {
      Node<Author> authors(String alias, bool active) =>
          s.authorNode(alias: alias)
            ..add(s.authorId)
            ..addFilters(Filters()..add(BooleanFilter(s.authorActive), active));
      final query = compact(
        s.render(
          s.bookNode()
            ..addNode(authors('activeAuthors', true))
            ..addNode(authors('inactiveAuthors', false)),
        ),
      );
      expect(
        query,
        contains('activeAuthors:contributors(active__Is:true){id}'),
      );
      expect(
        query,
        contains('inactiveAuthors:contributors(active__Is:false){id}'),
      );
    });

    test('conflicting filter additions preserve the earlier value', () {
      final f = Filters()..add(BooleanFilter(s.available), true);
      expect(() => f.add(BooleanFilter(s.available), false), rejects);
      expect(
        compact(
          s.render(
            s.bookNode()
              ..add(s.id)
              ..addFilters(f),
          ),
        ),
        contains('available__Is:true'),
      );
    });

    test('addFilters rejects a whole conflicting batch atomically', () {
      final node = s.bookNode()
        ..add(s.id)
        ..addFilters(Filters()..add(BooleanFilter(s.available), true));
      final before = s.render(node);
      final conflicting = Filters()
        ..add(EqualFilter(s.title), 'new')
        ..add(BooleanFilter(s.available), false);
      expect(() => node.addFilters(conflicting), rejects);
      expect(s.render(node), before);
    });

    test('addAll rejects conflicts without adding partial fields', () {
      final target = s.bookNode()
        ..add(s.id)
        ..addFilters(Filters()..add(EqualFilter(s.price), 1));
      final source = s.bookNode()
        ..add(s.title)
        ..addFilters(Filters()..add(EqualFilter(s.price), 2));
      final before = s.render(target);
      expect(() => target.addAll(source.freeze()), rejects);
      expect(s.render(target), before);
    });

    test('a relation merge conflict leaves all prior selections unchanged', () {
      Node<Author> author(bool active, Field<Author> field) => s.authorNode()
        ..add(field)
        ..addFilters(Filters()..add(BooleanFilter(s.authorActive), active));
      final node = s.bookNode()..addNode(author(true, s.authorId));
      final before = s.render(node);
      expect(() => node.addNode(author(false, s.authorName)), rejects);
      expect(s.render(node), before);
    });

    test('the same alias cannot target different relation fields', () {
      final node = s.bookNode()
        ..addNode(s.authorNode(alias: 'person')..add(s.authorId));
      final before = s.render(node);
      expect(
        () => node.addNode(
          s.authorNode(alias: 'person')..add(s.authorName),
          via: s.editor,
        ),
        rejects,
      );
      expect(s.render(node), before);
    });

    test(
      'query merges matching roots and rejects root conflicts atomically',
      () {
        final query = Query()
          ..add(s.bookNode()..add(s.id))
          ..add(s.bookNode()..add(s.title));
        expect(compact(query.build().query), contains('books{idtitle}'));
        final before = query.build().query;
        final conflict = Node<Book>(
          s.bookType,
          root: s.featured,
          alias: 'books',
        )..add(s.price);
        expect(() => query.add(conflict), rejects);
        expect(query.build().query, before);
      },
    );
  });

  group('pagination, sorting and payload', () {
    test('pagination honors argument names and first-page offset', () {
      final root = QueryRoot<Book>(
        'catalog',
        type: s.bookType,
        scope: s.booksScope,
        pagination: PagePagination(
          pageArgument: 'pageIndex',
          perPageArgument: 'limit',
          firstPage: 1,
        ),
      );
      final node = Node<Book>(s.bookType, root: root)
        ..add(s.id)
        ..paginate(Page(index: 2, size: 20));
      final query = compact(s.render(node));
      expect(query, contains('pageIndex:3'));
      expect(query, contains('limit:20'));
      expect(query, isNot(contains('perPage')));
    });

    test('nested pagination uses page zero and permits an omitted size', () {
      final child = s.authorNode()
        ..add(s.authorId)
        ..paginate(Page());
      final query = compact(s.render(s.bookNode()..addNode(child)));
      expect(query, contains('contributors(page:0){id}'));
      expect(query, isNot(contains('perPage')));
    });

    test('invalid pages and undeclared pagination are rejected', () {
      expect(() => Page(index: -1), rejects);
      expect(() => Page(size: 0), rejects);
      expect(() => Page(size: -2), rejects);
      expect(
        () => Query()
          ..add(
            Node<Book>(s.bookType, root: s.featured)
              ..add(s.id)
              ..paginate(Page()),
          ),
        rejects,
      );
      final child = s.authorNode()
        ..add(s.authorId)
        ..paginate(Page());
      expect(() => s.bookNode()..addNode(child, via: s.editor), rejects);
    });

    test('sort direction becomes a boolean', () {
      final node = s.bookNode()
        ..add(s.id)
        ..addSort(SortBy(s.title, SortDirection.ascending))
        ..addSort(SortBy(s.price, SortDirection.descending));
      final query = compact(s.render(node));
      expect(query, contains('title__OrderBy:true'));
      expect(query, contains('price__OrderBy:false'));
    });

    test(
      'named requests expose an immutable variables map and JSON payload',
      () {
        final request = (Query(
          name: 'CatalogPage',
        )..add(s.bookNode()..add(s.id))).build();
        expect(compact(request.query), startsWith('queryCatalogPage{'));
        expect(request.operationName, 'CatalogPage');
        expect(request.variables, isEmpty);
        expect(
          () => request.variables['unexpected'] = 1,
          throwsUnsupportedError,
        );
        expect(request.toJson(), {
          'query': request.query,
          'variables': <String, Object?>{},
          'operationName': 'CatalogPage',
        });
        expect(jsonDecode(request.toJsonString()), request.toJson());
      },
    );

    test('anonymous request omits operationName', () {
      final request = (Query()..add(s.bookNode()..add(s.id))).build();
      expect(request.operationName, isNull);
      expect(request.toJson().keys, unorderedEquals(['query', 'variables']));
    });

    test('schema names and required scopes are validated', () {
      for (final invalid in ['', '1books', 'book-name', 'books) { hidden']) {
        expect(() => NodeType<Book>(invalid), rejects);
        expect(() => Query(name: invalid), rejects);
        expect(() => Field<Book>(invalid, owner: s.bookType), rejects);
        expect(() => s.bookNode(alias: invalid), rejects);
      }
      expect(() => ArgumentScope(''), rejects);
      expect(
        () => InputDefinition<String>(
          'search',
          codec: ValueCodecs.string,
          scopes: {},
          operators: {FilterOperator.equal},
        ),
        rejects,
      );
    });

    test('identifier validation rejects a trailing newline', () {
      expect(() => NodeType<Book>('Book\n'), rejects);
      expect(() => Query(name: 'Catalog\n'), rejects);
      expect(() => EnumValue('READY\n'), rejects);
      expect(() => NumericId('12\n'), rejects);
    });

    test('wire overrides and pagination argument names are validated', () {
      expect(
        () => InputDefinition<String>(
          'search',
          codec: ValueCodecs.string,
          scopes: {s.booksScope},
          operators: {FilterOperator.equal},
          argumentNames: {FilterOperator.equal: 'invalid-name'},
        ),
        rejects,
      );
      expect(
        () => InputDefinition<String>(
          'search',
          codec: ValueCodecs.string,
          scopes: {s.booksScope},
          operators: {FilterOperator.equal},
          sortArgument: 'bad\n',
        ),
        rejects,
      );
      expect(() => PagePagination(pageArgument: 'bad-name'), rejects);
      expect(() => PagePagination(perPageArgument: 'bad\n'), rejects);
    });
  });
}
