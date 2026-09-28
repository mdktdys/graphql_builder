import 'package:graphql_builder/graphql_builder.dart';

final class Employee {
  final int id;
  const Employee({required this.id});
}

final class EmployeeNode extends Node<Employee> {
  static final nodeType = NodeType<Employee>();
  static final QueryRoot<Employee> employeesRoot = QueryRoot<Employee>(
    type: nodeType,
    'employees',
  );

  static final id = ScalarField<Employee, int>(
    owner: nodeType,
    input: InputDefinition<int>(
      'id',
      codec: ValueCodecs.integer,
      scopes: {
        employeesRoot.scope
      },
      operators: {
        FilterOperator.equal
      },
    ),
  );

  EmployeeNode() : super(nodeType, root: employeesRoot);
}

void main() {
  final employee = EmployeeNode()
    ..add(EmployeeNode.id)
    ..addFilters(Filters()..add(EqualFilter(EmployeeNode.id), 42));

  print((Query()..add(employee)).build().query);
}
