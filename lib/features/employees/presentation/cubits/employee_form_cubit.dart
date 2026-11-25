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

  void onPinCodeChanged(String pinCode) {
    emit(state.copyWith(pinCode: pinCode.trim(), errorMessage: null));
  }

  void onStatusChanged(bool isActive) {
    emit(state.copyWith(isActive: isActive, errorMessage: null));
  }

  Future<void> submit() async {
    if (state.name.trim().isEmpty || state.email.trim().isEmpty) {
      emit(state.copyWith(errorMessage: 'يرجى تعبئة الاسم واسم المستخدم المطلوبين'));
      return;
    }
    if (state.pinCode.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(state.pinCode)) {
      emit(state.copyWith(errorMessage: 'رمز PIN السريع يجب أن يتكون من 4 أرقام'));
      return;
    }

    emit(state.copyWith(isSubmitting: true));

    final employee = EmployeeEntity(
      id: '',
      displayName: state.name.trim(),
      username: state.email.trim(),
      role: state.role,
      isActive: state.isActive,
      pinCode: state.pinCode.isNotEmpty ? state.pinCode : null,
      createdAt: DateTime.now(),
    );

    final result = await _addEmployeeUseCase(
      employee,
      pinCode: state.pinCode.isNotEmpty ? state.pinCode : null,
    );

    result.fold(
      (failure) => emit(state.copyWith(isSubmitting: false, errorMessage: failure.message)),
      (_) => emit(state.copyWith(isSubmitting: false, isSuccess: true)),
    );
  }
}
