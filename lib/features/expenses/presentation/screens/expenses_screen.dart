import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../cubits/expenses_cubit.dart';
import '../cubits/expenses_state.dart';
import '../../domain/entities/expense_entity.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTimeRange? _dateRange;

  static const List<String> expenseCategories = [
    'إيجار المحل',
    'كهرباء ومرافق',
    'مرتبات ويوميات',
    'بوفيه وضيافة',
    'صيانة ونظافة',
    'أكياس ومستلزمات تعبئة',
    'نقل وشحن بضاعة',
    'مصروفات أخرى',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  void _openAddExpenseDialog(BuildContext context) {
    final cubit = context.read<ExpensesCubit>();
    String selectedCategory = expenseCategories.first;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime expenseDate = DateTime.now();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_card_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Text('تسجيل مصروف جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      items: expenseCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedCategory = val);
                      },
                      decoration: InputDecoration(
                        labelText: 'بند المصروف *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'المبلغ بالج.م *',
                        hintText: 'مثال: 150.00',
                        suffixText: 'ج.م',
                        prefixIcon: const Icon(Icons.monetization_on_outlined, color: AppColors.primary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'يرجى إدخال المبلغ';
                        final num = double.tryParse(val.trim());
                        if (num == null || num <= 0) return 'المبلغ يجب أن يكون أكبر من الصفر';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      leading: const Icon(Icons.calendar_today_rounded, color: AppColors.primary),
                      title: const Text('تاريخ المصروف', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      subtitle: Text(
                        '${expenseDate.year}-${expenseDate.month.toString().padLeft(2, '0')}-${expenseDate.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: expenseDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => expenseDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'ملاحظات / بيان الصرف (اختياري)',
                        hintText: 'مثال: فاتورة كهرباء شهر مايو، صيانة تكييف المحل...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                final pounds = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final piasters = (pounds * 100).toInt();

                String userId = 'admin';
                try {
                  final auth = context.read<AuthCubit>().state;
                  if (auth is AuthAuthenticated) userId = auth.user.name;
                } catch (_) {}

                final ok = await cubit.addExpense(
                  category: selectedCategory,
                  amount: piasters,
                  note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                  expenseDate: expenseDate,
                  userId: userId,
                );

                if (ok && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                }
              },
              child: const Text('حفظ المصروف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ExpenseEntity expense) async {
    final cubit = context.read<ExpensesCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('تأكيد حذف المصروف', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف مصروف "${expense.category}" بمبلغ ${expense.formattedAmount}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف نهائي', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await cubit.deleteExpense(expense.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<ExpensesCubit>()
        ..loadExpenses(
          from: _dateRange?.start,
          to: _dateRange?.end,
        ),
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: AppColors.surface,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'سجل المصروفات والنثريات',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
                  ),
                  Text(
                    'تسجيل ومتابعة مصاريف التشغيل والإيجار والمرافق والمرتبات',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _openAddExpenseDialog(context),
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    label: const Text('تسجيل مصروف جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            body: BlocBuilder<ExpensesCubit, ExpensesState>(
              builder: (context, state) {
                return Column(
                  children: [
                    // Date & Filter bar
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.date_range_rounded, color: AppColors.primary, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        _dateRange != null
                                            ? 'الفترة: ${_dateRange!.start.toLocal().toString().split(' ')[0]} إلى ${_dateRange!.end.toLocal().toString().split(' ')[0]}'
                                            : 'جميع الفترات',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: const BorderSide(color: AppColors.primary),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  final picked = await showDateRangePicker(
                                    context: context,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                    initialDateRange: _dateRange,
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _dateRange = DateTimeRange(
                                        start: picked.start,
                                        end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
                                      );
                                    });
                                    if (context.mounted) {
                                      context.read<ExpensesCubit>().loadExpenses(
                                            from: _dateRange!.start,
                                            to: _dateRange!.end,
                                            category: state.selectedCategory,
                                          );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                                label: const Text('تغيير الفترة'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Category Chips
                          SizedBox(
                            height: 38,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: ChoiceChip(
                                    label: const Text('جميع البنود'),
                                    selected: state.selectedCategory == null,
                                    onSelected: (sel) {
                                      if (sel) {
                                        context.read<ExpensesCubit>().loadExpenses(
                                              from: _dateRange?.start,
                                              to: _dateRange?.end,
                                              category: null,
                                            );
                                      }
                                    },
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: state.selectedCategory == null ? Colors.white : AppColors.onSurface,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                ...expenseCategories.map((cat) {
                                  final isSel = state.selectedCategory == cat;
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: ChoiceChip(
                                      label: Text(cat),
                                      selected: isSel,
                                      onSelected: (sel) {
                                        context.read<ExpensesCubit>().loadExpenses(
                                              from: _dateRange?.start,
                                              to: _dateRange?.end,
                                              category: sel ? cat : null,
                                            );
                                      },
                                      selectedColor: AppColors.primary,
                                      labelStyle: TextStyle(
                                        color: isSel ? Colors.white : AppColors.onSurface,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Summary Banner
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.error.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.outbox_rounded, color: AppColors.error, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('إجمالي المصروفات للفترة', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${Money(state.totalAmount).toDisplay()} ج.م',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.error),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('عدد سندات الصرف', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${state.expenses.length} مصروف',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Expenses List
                    Expanded(
                      child: state.status == ExpensesStatus.loading
                          ? const Center(child: CircularProgressIndicator())
                          : state.expenses.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.money_off_csred_rounded, size: 64, color: Colors.grey.shade400),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'لا توجد مصروفات مسجلة خلال هذه الفترة',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () => _openAddExpenseDialog(context),
                                        icon: const Icon(Icons.add, color: Colors.white),
                                        label: const Text('تسجيل أول مصروف الآن', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  itemCount: state.expenses.length,
                                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final exp = state.expenses[index];
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: ListTile(
                                        leading: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.payments_outlined, color: AppColors.primary),
                                        ),
                                        title: Row(
                                          children: [
                                            Text(exp.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                            const SizedBox(width: 10),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '${exp.expenseDate.year}-${exp.expenseDate.month.toString().padLeft(2, '0')}-${exp.expenseDate.day.toString().padLeft(2, '0')}',
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                              ),
                                            ),
                                          ],
                                        ),
                                        subtitle: Text(
                                          exp.note != null && exp.note!.isNotEmpty
                                              ? exp.note!
                                              : 'المسجل: ${exp.userId}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              exp.formattedAmount,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: AppColors.error,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                                              tooltip: 'حذف المصروف',
                                              onPressed: () => _confirmDelete(context, exp),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                );
              },
            ),
            floatingActionButton: FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: () => _openAddExpenseDialog(context),
              child: const Icon(Icons.add, color: Colors.white),
            ),
          );
        },
      ),
    );
  }
}
