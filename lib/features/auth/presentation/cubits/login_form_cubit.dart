import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'login_state.dart';
import 'auth_cubit.dart';

@injectable
class LoginFormCubit extends Cubit<LoginFormState> {
  final AuthCubit _authCubit;

  LoginFormCubit(this._authCubit) : super(const LoginFormState());

  void onEmailChanged(String email) {
    emit(state.copyWith(email: email, errorMessage: null));
  }

  void onPasswordChanged(String password) {
    emit(state.copyWith(password: password, errorMessage: null));
  }

  Future<void> submit() async {
    if (state.email.isEmpty || state.password.isEmpty) {
      emit(state.copyWith(errorMessage: 'Please fill in all fields'));
      return;
    }

    emit(state.copyWith(isSubmitting: true));
    await _authCubit.login(state.email, state.password);
    emit(state.copyWith(isSubmitting: false));
  }
}
