import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/usecases/add_employee_usecase.dart';
import 'employee_form_state.dart';

@injectable
class EmployeeFormCubit extends Cubit<EmployeeFormState> {
  final AddEmployeeUseCase _addEmployeeUseCase;

  EmployeeFormCubit(this._addEmployeeUseCase) : super(const EmployeeFormState());

  void onNameChanged(String name) {
    emit(state.copyWith(name: name, errorMessage: null));
  }

  void onEmailChanged(String email) {
    emit(state.copyWith(email: email, errorMessage: null));
  }

  void onRoleChanged(String role) {
    emit(state.copyWith(role: role, errorMessage: null));
  }

  void onStatusChanged(bool isActive) {
    emit(state.copyWith(isActive: isActive, errorMessage: null));
  }

  Future<void> submit() async {
    if (state.name.isEmpty || state.email.isEmpty) {
      emit(state.copyWith(errorMessage: 'Please fill in all required fields'));
      return;
    }

    emit(state.copyWith(isSubmitting: true));

    final employee = EmployeeEntity(
      id: '', // Firestore will generate ID if empty
      name: state.name,
      email: state.email,
      role: state.role,
      isActive: state.isActive,
      createdAt: DateTime.now(),
    );

    final result = await _addEmployeeUseCase(employee);

    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, errorMessage: failure.message)),
      (_) => emit(state.copyWith(isSubmitting: false, isSuccess: true)),
    );
  }
}
