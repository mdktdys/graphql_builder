import 'package:graphql_builder/graphql_builder.dart';

final QueryRoot _objectRoot = QueryRoot('employee');
final QueryRoot _listRoot = QueryRoot('employees');

final ScalarField<int> _id = ScalarField<int>(
  name: 'id',
  operators: {
    FilterOperator.equal
  },
);

final class EmployeeBuilder {
  String byId(int employeeId) {
    final employee = Node(_listRoot)
      ..add(_id)
      ..addFilters(Filters()..add(EqualFilter(_id), employeeId));

    final GraphRequest request = (Query()..add(employee)).build(); 
    return request.query;
  }
}

void main() {
  print(EmployeeBuilder().byId(42));
}
