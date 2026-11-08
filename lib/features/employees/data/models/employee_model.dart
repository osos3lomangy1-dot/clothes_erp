import '../../domain/entities/employee_entity.dart';
import '../../../../core/database/app_database.dart';

class EmployeeModel extends EmployeeEntity {
  const EmployeeModel({
    required super.id,
    required super.displayName,
    required super.username,
    required super.role,
    super.isActive = true,
    super.salary = 0,
    required super.createdAt,
    super.updatedAt,
  });

  factory EmployeeModel.fromEntity(EmployeeEntity entity) {
    return EmployeeModel(
      id: entity.id,
      displayName: entity.displayName,
      username: entity.username,
      role: entity.role,
      isActive: entity.isActive,
      salary: entity.salary,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
    );
  }

  factory EmployeeModel.fromDrift(User user) {
    return EmployeeModel(
      id: user.id,
      displayName: user.displayName,
      username: user.username,
      role: user.role,
      isActive: user.isActive,
      salary: user.salary,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
    );
  }

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    final entity = EmployeeEntity.fromJson(json);
    return EmployeeModel.fromEntity(entity);
  }
}
