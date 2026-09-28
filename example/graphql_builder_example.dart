import 'package:graphql_builder/graphql_builder.dart';

final class EmployeeNode extends Node {
  EmployeeNode.one() : super.fromRoot(employeeRoot);
  EmployeeNode.list() : super.fromRoot(employeesRoot);

  static final QueryRoot employeesRoot = QueryRoot('employees');
  static final QueryRoot employeeRoot = QueryRoot.withTypeOf(
    'employee',
    employeesRoot,
  );

  static final ScalarField<int> id = ScalarField<int>(
    owner: employeesRoot,
    input: InputDefinition<int>(
      'id',
      codec: ValueCodecs.integer,
      scopes: {employeesRoot.scope, employeeRoot.scope},
      operators: {FilterOperator.equal},
    ),
  );
}

void main() {
  final employee = EmployeeNode.one()
    ..add(EmployeeNode.id)
    ..addFilters(Filters()..add(EqualFilter(EmployeeNode.id), 3));

  print((Query()..add(employee)).build().query);
}
