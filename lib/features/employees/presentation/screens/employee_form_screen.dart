import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../cubits/employee_form_cubit.dart';
import '../cubits/employee_form_state.dart';

/// Opens a polished modal dialog to add a new employee.
Future<void> showEmployeeFormDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) => getIt<EmployeeFormCubit>(),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: const EmployeeFormView(isDialog: true),
        ),
      ),
    ),
  );
}

class EmployeeFormScreen extends StatelessWidget {
  const EmployeeFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<EmployeeFormCubit>(),
      child: const EmployeeFormView(isDialog: false),
    );
  }
}

class EmployeeFormView extends StatelessWidget {
  final bool isDialog;

  const EmployeeFormView({super.key, this.isDialog = false});

  @override
  Widget build(BuildContext context) {
    final formBody = BlocConsumer<EmployeeFormCubit, EmployeeFormState>(
      listener: (context, state) {
        if (state.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('تمت إضافة الموظف بنجاح'),
            ),
          );
          if (isDialog) {
            Navigator.of(context).pop();
          } else {
            AppNavigator.pop(context);
          }
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
        final fields = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              onChanged: (value) =>
                  context.read<EmployeeFormCubit>().onNameChanged(value),
              decoration: const InputDecoration(
                labelText: 'الاسم بالكامل *',
                hintText: 'مثال: أحمد محمود',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) =>
                  context.read<EmployeeFormCubit>().onEmailChanged(value),
              decoration: const InputDecoration(
                labelText: 'البريد الإلكتروني *',
                hintText: 'name@store.com',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: state.role,
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('مدير عام')),
                DropdownMenuItem(value: 'cashier', child: Text('كاشير')),
              ],
              onChanged: (value) {
                if (value != null) {
                  context.read<EmployeeFormCubit>().onRoleChanged(value);
                }
              },
              decoration: const InputDecoration(
                labelText: 'الدور الوظيفي / الصلاحية *',
              ),
            ),
            const SizedBox(height: 24),
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
                    : () => context.read<EmployeeFormCubit>().submit(),
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
        );

        if (isDialog) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_add_rounded, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'إضافة موظف جديد',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16.5,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(padding: const EdgeInsets.all(20), child: fields),
            ],
          );
        }

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
                child: Padding(padding: const EdgeInsets.all(24.0), child: fields),
              ),
            ),
          ),
        );
      },
    );

    if (isDialog) return formBody;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'إضافة موظف جديد',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.onSurface,
          ),
        ),
      ),
      body: formBody,
    );
  }
}
