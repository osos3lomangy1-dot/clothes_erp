import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/employee_entity.dart';
import '../cubits/employee_cubit.dart';
import '../cubits/employee_state.dart';
import '../widgets/cashier_profile_dialog.dart';

class EmployeeListScreen extends StatelessWidget {
  const EmployeeListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<EmployeeCubit>()..loadEmployees(),
      child: const EmployeeListView(),
    );
  }
}

class EmployeeListView extends StatefulWidget {
  const EmployeeListView({super.key});

  @override
  State<EmployeeListView> createState() => _EmployeeListViewState();
}

class _EmployeeListViewState extends State<EmployeeListView> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openEmployeeDialog(BuildContext context, {EmployeeEntity? employee}) {
    final cubit = context.read<EmployeeCubit>();
    final isEdit = employee != null;

    final nameCtrl = TextEditingController(text: employee?.displayName ?? '');
    final usernameCtrl = TextEditingController(text: employee?.username ?? '');
    final salaryCtrl = TextEditingController(
      text: employee != null && employee.salary > 0 ? '${employee.salary / 100}' : '',
    );
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String role = employee?.role ?? 'cashier';
    bool isActive = employee?.isActive ?? true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                isEdit ? Icons.edit_note_rounded : Icons.person_add_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isEdit ? 'تعديل بيانات الموظف' : 'إضافة موظف جديد',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'الاسم الكامل *',
                        hintText: 'مثال: أحمد عبد الله',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'يرجى إدخال اسم الموظف' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: usernameCtrl,
                      decoration: InputDecoration(
                        labelText: 'اسم المستخدم / كود الدخول *',
                        hintText: 'مثال: ahmed_pos أو البريد',
                        prefixIcon: const Icon(Icons.alternate_email_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'يرجى إدخال اسم المستخدم' : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: InputDecoration(
                        labelText: 'الدور / الصلاحيات *',
                        prefixIcon: const Icon(Icons.security_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'cashier',
                          child: Text('كاشير (إصدار فواتير وسداد فقط)'),
                        ),
                        DropdownMenuItem(
                          value: 'manager',
                          child: Text('مدير فرع (إدارة المخازن والمبيعات)'),
                        ),
                        DropdownMenuItem(
                          value: 'admin',
                          child: Text('مسؤول عام (صلاحيات كاملة للمتجر)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => role = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: salaryCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'الراتب الشهري الأساسي (ج.م)',
                        hintText: 'مثال: 5000',
                        suffixText: 'ج.م',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: isEdit ? 'كلمة المرور الجديدة (اتركها فارغة للإبقاء)' : 'كلمة المرور *',
                        hintText: 'أدخل 6 أرقام أو حروف على الأقل',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (val) {
                        if (!isEdit && (val == null || val.trim().isEmpty)) {
                          return 'يرجى تعيين كلمة مرور للموظف الجديد';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      title: const Text('حالة الحساب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(
                        isActive ? 'الحساب مفعّل ويستطيع تسجيل الدخول' : 'الحساب معطّل مؤقتاً',
                        style: TextStyle(fontSize: 12, color: isActive ? Colors.green.shade800 : Colors.red),
                      ),
                      value: isActive,
                      onChanged: (val) => setDialogState(() => isActive = val),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                final pounds = double.tryParse(salaryCtrl.text.trim()) ?? 0.0;
                final piasters = (pounds * 100).toInt();

                bool ok = false;
                if (isEdit) {
                  final toUpdate = employee.copyWith(
                    displayName: nameCtrl.text.trim(),
                    username: usernameCtrl.text.trim(),
                    role: role,
                    salary: piasters,
                    isActive: isActive,
                  );
                  ok = await cubit.updateEmployee(toUpdate);
                } else {
                  final toAdd = EmployeeEntity(
                    id: '',
                    displayName: nameCtrl.text.trim(),
                    username: usernameCtrl.text.trim(),
                    role: role,
                    salary: piasters,
                    isActive: isActive,
                    createdAt: DateTime.now(),
                  );
                  ok = await cubit.addEmployee(toAdd, password: passwordCtrl.text.trim());
                }

                if (ok && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEdit ? 'تم تحديث بيانات الموظف بنجاح' : 'تمت إضافة الموظف بنجاح'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              child: Text(
                isEdit ? 'حفظ التعديلات' : 'إضافة الموظف',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, EmployeeEntity employee) async {
    final cubit = context.read<EmployeeCubit>();
    final confirmed = await showDialog<bool>(
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
        content: Text('هل أنت متأكد من حذف حساب الموظف "${employee.displayName}" (${employee.username})؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف نهائي', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await cubit.deleteEmployee(employee.id);
    }
  }

  String _roleName(String role) {
    switch (role) {
      case 'admin':
        return 'مسؤول عام';
      case 'manager':
        return 'مدير فرع';
      case 'cashier':
      default:
        return 'كاشير';
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.purple.shade700;
      case 'manager':
        return Colors.teal.shade700;
      case 'cashier':
      default:
        return Colors.blue.shade700;
    }
  }

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
              'إدارة حسابات الكاشير، المديرين، الرواتب وصلاحيات النظام',
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
              onPressed: () => _openEmployeeDialog(context),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم الكامل أو اسم المستخدم...',
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                context.read<EmployeeCubit>().search('');
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => context.read<EmployeeCubit>().search(val),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Employees List
          Expanded(
            child: BlocBuilder<EmployeeCubit, EmployeeState>(
              builder: (context, state) {
                if (state is EmployeeLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is EmployeeLoaded) {
                  final employees = state.employees;

                  if (employees.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            state.searchQuery.isNotEmpty
                                ? 'لم يتم العثور على موظف يطابق "${state.searchQuery}"'
                                : 'لا يوجد موظفون مسجلون في النظام حتى الآن',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          if (state.searchQuery.isEmpty)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _openEmployeeDialog(context),
                              icon: const Icon(Icons.add, color: Colors.white),
                              label: const Text('إضافة أول موظف الآن', style: TextStyle(color: Colors.white)),
                            ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: employees.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final employee = employees[index];
                      final roleColor = _roleColor(employee.role);

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: roleColor.withValues(alpha: 0.12),
                                child: Text(
                                  employee.displayName.isNotEmpty ? employee.displayName[0] : 'م',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: roleColor),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          employee.displayName,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: roleColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                                          ),
                                          child: Text(
                                            _roleName(employee.role),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: roleColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 14,
                                      runSpacing: 4,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.alternate_email_rounded, size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                              employee.username,
                                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        if (employee.salary > 0)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.payments_outlined, size: 14, color: Colors.green),
                                              const SizedBox(width: 4),
                                              Text(
                                                'الراتب: ${Money(employee.salary).toDisplay()} ج.م / شهر',
                                                style: TextStyle(
                                                  color: Colors.green.shade800,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: employee.isActive ? Colors.green.shade50 : Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: employee.isActive ? Colors.green.shade300 : Colors.red.shade300,
                                      ),
                                    ),
                                    child: Text(
                                      employee.isActive ? 'نشط' : 'معطل',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: employee.isActive ? Colors.green.shade800 : Colors.red.shade800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Switch(
                                    value: employee.isActive,
                                    onChanged: (value) {
                                      context.read<EmployeeCubit>().updateStatus(employee.id, value);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.teal),
                                    tooltip: 'كشف الراتب، البونص والمستحقات المالية',
                                    onPressed: () => CashierProfileDialog.show(context, employeeId: employee.id),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                                    tooltip: 'تعديل بيانات الموظف',
                                    onPressed: () => _openEmployeeDialog(context, employee: employee),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                                    tooltip: 'حذف الموظف',
                                    onPressed: () => _confirmDelete(context, employee),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }
                if (state is EmployeeError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('خطأ: ${state.message}', style: const TextStyle(color: AppColors.error)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => context.read<EmployeeCubit>().loadEmployees(),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}
