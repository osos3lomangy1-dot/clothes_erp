import 'package:equatable/equatable.dart';

class EmployeeEntity extends Equatable {
  final String id;
  final String displayName;
  final String username;
  final String role; // 'admin', 'cashier', 'manager'
  final bool isActive;
  final int salary; // in piasters (e.g. 500000 = 5000 EGP)
  final DateTime createdAt;
  final DateTime? updatedAt;

  const EmployeeEntity({
    required this.id,
    required this.displayName,
    required this.username,
    required this.role,
    this.isActive = true,
    this.salary = 0,
    required this.createdAt,
    this.updatedAt,
  });

  // Backward-compatible getters
  String get name => displayName;
  String get email => username;
  double get salaryPounds => salary / 100.0;

  EmployeeEntity copyWith({
    String? id,
    String? displayName,
    String? username,
    String? role,
    bool? isActive,
    int? salary,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmployeeEntity(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      salary: salary ?? this.salary,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'username': username,
        'role': role,
        'isActive': isActive,
        'salary': salary,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory EmployeeEntity.fromJson(Map<String, dynamic> json) => EmployeeEntity(
        id: json['id'] as String? ?? '',
        displayName: json['displayName'] as String? ?? json['name'] as String? ?? '',
        username: json['username'] as String? ?? json['email'] as String? ?? '',
        role: json['role'] as String? ?? 'cashier',
        isActive: json['isActive'] as bool? ?? true,
        salary: (json['salary'] is num)
            ? ((json['salary'] as num) > 1000
                ? (json['salary'] as num).toInt()
                : ((json['salary'] as num) * 100).toInt())
            : 0,
        createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : DateTime.now(),
        updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
      );

  @override
  List<Object?> get props => [id, displayName, username, role, isActive, salary, createdAt, updatedAt];
}
