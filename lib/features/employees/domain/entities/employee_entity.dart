import 'package:equatable/equatable.dart';

class EmployeeEntity extends Equatable {
  final String id;
  final String name;
  final String email;
  final String role;
  final bool isActive;
  final DateTime createdAt;
  final double salary;

  const EmployeeEntity({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    required this.createdAt,
    this.salary = 0.0,
  });

  @override
  List<Object?> get props => [id, name, email, role, isActive, createdAt, salary];
}
