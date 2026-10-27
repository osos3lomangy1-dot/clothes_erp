import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../cubits/employee_form_cubit.dart';
import '../cubits/employee_form_state.dart';

class EmployeeFormScreen extends StatelessWidget {
  const EmployeeFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<EmployeeFormCubit>(),
      child: const EmployeeFormView(),
    );
  }
}

class EmployeeFormView extends StatelessWidget {
  const EmployeeFormView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Employee'),
      ),
      body: BlocConsumer<EmployeeFormCubit, EmployeeFormState>(
        listener: (context, state) {
          if (state.isSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Employee added successfully')),
            );
            AppNavigator.pop(context);
          }
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!)),
            );
          }
        },
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  onChanged: (value) =>
                      context.read<EmployeeFormCubit>().onNameChanged(value),
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                TextField(
                  onChanged: (value) =>
                      context.read<EmployeeFormCubit>().onEmailChanged(value),
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                DropdownButtonFormField<String>(
                  initialValue: state.role,
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      context.read<EmployeeFormCubit>().onRoleChanged(value);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Role'),
                ),
                const SizedBox(height: 24),
                if (state.isSubmitting)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed: () => context.read<EmployeeFormCubit>().submit(),
                    child: const Text('Add Employee'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
