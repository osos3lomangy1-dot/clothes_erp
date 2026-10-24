import 'package:equatable/equatable.dart';

class EmployeeFormState extends Equatable {
  final String name;
  final String email;
  final String role;
  final bool isActive;
  final bool isSubmitting;
  final String? errorMessage;
  final bool isSuccess;

  const EmployeeFormState({
    this.name = '',
    this.email = '',
    this.role = 'cashier',
    this.isActive = true,
    this.isSubmitting = false,
    this.errorMessage,
    this.isSuccess = false,
  });

  EmployeeFormState copyWith({
    String? name,
    String? email,
    String? role,
    bool? isActive,
    bool? isSubmitting,
    String? errorMessage,
    bool? isSuccess,
  }) {
    return EmployeeFormState(
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
      isSuccess: isSuccess ?? this.isSuccess,
    );
  }

  @override
  List<Object?> get props => [name, email, role, isActive, isSubmitting, errorMessage, isSuccess];
}
