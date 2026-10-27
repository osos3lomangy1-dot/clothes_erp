import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
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
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.storefront, size: 80, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Clothes ERP', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Clothing Store Management System', style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
              const SizedBox(height: 48),
              BlocBuilder<LoginFormCubit, LoginFormState>(
                buildWhen: (p, c) => p.email != c.email,
                builder: (context, state) {
                  return TextField(
                    onChanged: (val) => context.read<LoginFormCubit>().onEmailChanged(val),
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      filled: true,
                      fillColor: Colors.white,
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
                      prefixIcon: Icon(Icons.lock_outlined),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              BlocBuilder<LoginFormCubit, LoginFormState>(
                builder: (context, state) {
                  return SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: state.isSubmitting ? null : () => context.read<LoginFormCubit>().submit(),
                      child: state.isSubmitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Login', style: TextStyle(fontSize: 16)),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text('© 2026 Clothing Store ERP', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
