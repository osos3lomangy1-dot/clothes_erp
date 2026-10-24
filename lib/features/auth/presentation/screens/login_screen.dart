import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../cubits/auth_cubit.dart';
import '../cubits/auth_state.dart';
import '../cubits/login_form_cubit.dart';
import '../cubits/login_state.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<LoginFormCubit>(),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatelessWidget {
  const _LoginView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocListener<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Clothes ERP',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 40),
                BlocBuilder<LoginFormCubit, LoginFormState>(
                  buildWhen: (p, c) => p.email != c.email,
                  builder: (context, state) {
                    return TextField(
                      onChanged: (val) => context.read<LoginFormCubit>().onEmailChanged(val),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                BlocBuilder<LoginFormCubit, LoginFormState>(
                  buildWhen: (p, c) => p.password != c.password,
                  builder: (context, state) {
                    return TextField(
                      onChanged: (val) => context.read<LoginFormCubit>().onPasswordChanged(val),
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                BlocBuilder<LoginFormCubit, LoginFormState>(
                  builder: (context, state) {
                    return state.isSubmitting
                        ? const CircularProgressIndicator()
                        : SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: () => context.read<LoginFormCubit>().submit(),
                              child: const Text('Login'),
                            ),
                          );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
