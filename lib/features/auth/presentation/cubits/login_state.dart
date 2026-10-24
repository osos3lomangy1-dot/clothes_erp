import 'package:equatable/equatable.dart';

class LoginFormState extends Equatable {
  final String email;
  final String password;
  final bool isSubmitting;
  final String? errorMessage;

  const LoginFormState({
    this.email = '',
    this.password = '',
    this.isSubmitting = false,
    this.errorMessage,
  });

  LoginFormState copyWith({
    String? email,
    String? password,
    bool? isSubmitting,
    String? errorMessage,
  }) {
    return LoginFormState(
      email: email ?? this.email,
      password: password ?? this.password,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [email, password, isSubmitting, errorMessage];
}
