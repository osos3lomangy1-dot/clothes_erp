import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
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
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'إضافة موظف جديد',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: BlocConsumer<EmployeeFormCubit, EmployeeFormState>(
        listener: (context, state) {
          if (state.isSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.green,
                content: Text('تمت إضافة الموظف بنجاح'),
              ),
            );
            AppNavigator.pop(context);
          }
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.error,
                content: Text(state.errorMessage!),
              ),
            );
          }
        },
        builder: (context, state) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 550),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          onChanged: (value) => context
                              .read<EmployeeFormCubit>()
                              .onNameChanged(value),
                          decoration: InputDecoration(
                            labelText: 'الاسم بالكامل *',
                            hintText: 'مثال: أحمد محمود',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          onChanged: (value) => context
                              .read<EmployeeFormCubit>()
                              .onEmailChanged(value),
                          decoration: InputDecoration(
                            labelText: 'البريد الإلكتروني *',
                            hintText: 'name@store.com',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: state.role,
                          items: const [
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('مدير عام (Admin)'),
                            ),
                            DropdownMenuItem(
                              value: 'cashier',
                              child: Text('كاشير (Cashier)'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              context.read<EmployeeFormCubit>().onRoleChanged(
                                value,
                              );
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'الدور الوظيفي / الصلاحية *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: state.isSubmitting
                                ? null
                                : () => context
                                      .read<EmployeeFormCubit>()
                                      .submit(),
                            child: state.isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'حفظ بيانات الموظف',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
