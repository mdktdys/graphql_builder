/// Typed GraphQL queries, reusable selections and scoped filter operators.
///
/// The consumer declares its server schema through [NodeType], [QueryRoot],
/// [Relation], [Field] and [InputDefinition]. No application models or HTTP
/// client are included.
library;

import 'dart:convert';

part 'src/schema.dart';
part 'src/values.dart';
part 'src/filters.dart';
part 'src/node.dart';
part 'src/query.dart';
part 'src/serialization.dart';
