import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import './employee_form_screen.dart';
import '../cubits/employee_cubit.dart';
import '../cubits/employee_state.dart';

class EmployeeListScreen extends StatelessWidget {
  const EmployeeListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<EmployeeCubit>(),
      child: const EmployeeListView(),
    );
  }
}

class EmployeeListView extends StatelessWidget {
  const EmployeeListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'فريق العمل والموظفون',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
            ),
            Text(
              'إدارة حسابات الكاشير والمديرين وصلاحيات النظام',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
              label: const Text('إضافة موظف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const EmployeeFormScreen()),
              ),
            ),
          ),
        ],
      ),
      body: BlocBuilder<EmployeeCubit, EmployeeState>(
        builder: (context, state) {
          if (state is EmployeeLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is EmployeeLoaded) {
            if (state.employees.isEmpty) {
              return const Center(
                child: Text(
                  'لا يوجد موظفون مسجلون في النظام حتى الآن',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.employees.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final employee = state.employees[index];
                final isAdmin = employee.role == 'admin';

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isAdmin ? Colors.purple.shade100 : Colors.blue.shade100,
                      child: Icon(
                        isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                        color: isAdmin ? AppColors.primary : Colors.blue.shade800,
                      ),
                    ),
                    title: Text(employee.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Row(
                      children: [
                        Text(employee.email, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isAdmin ? Colors.purple.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isAdmin ? 'مدير عام' : 'كاشير',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isAdmin ? AppColors.primary : Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          employee.isActive ? 'نشط' : 'معطل',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: employee.isActive ? Colors.green.shade800 : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: employee.isActive,
                          onChanged: (value) {
                            context.read<EmployeeCubit>().updateStatus(employee.id, value);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                          tooltip: 'حذف الموظف',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: AppColors.error),
                                    SizedBox(width: 8),
                                    Text('تأكيد حذف الموظف', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: Text('هل أنت متأكد من حذف حساب الموظف "${employee.name}"؟'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogContext),
                                    child: const Text('إلغاء'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                                    onPressed: () {
                                      context.read<EmployeeCubit>().deleteEmployee(employee.id);
                                      Navigator.pop(dialogContext);
                                    },
                                    child: const Text('حذف نهائي', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }
          if (state is EmployeeError) {
            return Center(child: Text('خطأ: ${state.message}'));
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const EmployeeFormScreen()),
        ),
        child: const Icon(Icons.person_add_rounded, color: Colors.white),
      ),
    );
  }
}
