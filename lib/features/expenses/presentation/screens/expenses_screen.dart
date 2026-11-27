import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/excel_service.dart';
import '../../../../core/utils/keyboard_focus_helper.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/standard_date_filter_chips.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../auth/services/cashier_permissions_service.dart';
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
  String _activeDateFilter = 'month';
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  void _applyDateFilter(
    BuildContext context,
    String filter, {
    DateTimeRange? custom,
    String? category,
  }) {
    final now = DateTime.now();
    DateTimeRange? range;
    if (filter == 'today') {
      range = DateTimeRange(
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
    } else if (filter == 'week') {
      final start = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
      range = DateTimeRange(
        start: start,
        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
    } else if (filter == 'month') {
      range = DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
    } else if (filter == 'custom' && custom != null) {
      range = DateTimeRange(
        start: custom.start,
        end: DateTime(custom.end.year, custom.end.month, custom.end.day, 23, 59, 59),
      );
    }

    setState(() {
      _activeDateFilter = filter;
      _dateRange = range;
    });
    context.read<ExpensesCubit>().loadExpenses(
          from: range?.start,
          to: range?.end,
          category: category,
        );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool _canAddExpense(BuildContext context) {
    try {
      final auth = context.read<AuthCubit>().state;
      if (auth is AuthAuthenticated && auth.user.role.toLowerCase() == 'cashier') {
        return CashierPermissionsService.current.allowCashExpenses;
      }
    } catch (_) {}
    return true;
  }

  void _handleEsc(BuildContext context) {
    if (_searchCtrl.text.isNotEmpty || _searchQuery.isNotEmpty) {
      _searchCtrl.clear();
      setState(() => _searchQuery = '');
      return;
    }
    if (Navigator.canPop(context)) {
      Navigator.of(context).maybePop();
    }
  }

  void _openAddExpenseDialog(BuildContext context, List<String> currentCategories) {
    final cubit = context.read<ExpensesCubit>();
    String selectedCategory = currentCategories.isNotEmpty ? currentCategories.first : 'مصروفات أخرى';
    bool isCustomCategory = false;
    final customCategoryCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime expenseDate = DateTime.now();
    final formKey = GlobalKey<FormState>();

    const String addCustomKey = '__add_custom_category__';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submitExpense() async {
            if (formKey.currentState?.validate() != true) return;
            final pounds = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
            final piasters = (pounds * 100).toInt();

            final finalCategory = isCustomCategory
                ? customCategoryCtrl.text.trim()
                : selectedCategory;

            String userId = 'admin';
            try {
              final auth = context.read<AuthCubit>().state;
              if (auth is AuthAuthenticated) userId = auth.user.name;
            } catch (_) {}

            final ok = await cubit.addExpense(
              category: finalCategory,
              amount: piasters,
              note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
              expenseDate: expenseDate,
              userId: userId,
            );

            if (ok && dialogCtx.mounted) {
              Navigator.pop(dialogCtx);
            }
          }

          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  submitExpense,
              const SingleActivator(LogicalKeyboardKey.f12): submitExpense,
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.pop(dialogCtx),
            },
            child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
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
                      initialValue: isCustomCategory ? addCustomKey : selectedCategory,
                      isExpanded: true,
                      items: [
                        ...currentCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                        DropdownMenuItem(
                          value: addCustomKey,
                          child: Row(
                            children: [
                              Icon(Icons.add_circle_outline, color: AppColors.primary, size: 18),
                              SizedBox(width: 6),
                              Text(
                                '+ إضافة بند مصروف جديد...',
                                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val == addCustomKey) {
                          setDialogState(() {
                            isCustomCategory = true;
                          });
                        } else if (val != null) {
                          setDialogState(() {
                            isCustomCategory = false;
                            selectedCategory = val;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'بند المصروف *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    if (isCustomCategory) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: customCategoryCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'اسم بند المصروف الجديد *',
                          hintText: 'مثال: دعاية وتسويق، إكراميات، شحن سريع...',
                          prefixIcon: Icon(Icons.category_rounded, color: AppColors.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (val) {
                          if (isCustomCategory && (val == null || val.trim().isEmpty)) {
                            return 'يرجى كتابة اسم بند المصروف الجديد';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: amountCtrl,
                      autofocus: !isCustomCategory,
                      textInputAction: TextInputAction.next,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'المبلغ بالج.م *',
                        hintText: 'مثال: 150.00',
                        suffixText: 'ج.م',
                        prefixIcon: Icon(Icons.monetization_on_outlined, color: AppColors.primary),
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
                      leading: Icon(Icons.calendar_today_rounded, color: AppColors.primary),
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
              key: const Key('save_expense_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: submitExpense,
              child: const Text('حفظ المصروف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _exportExpensesToExcel(BuildContext context, ExpensesState state) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final excelService = ExcelService();
      final path = await excelService.exportExpenses(
        from: _dateRange?.start,
        to: _dateRange?.end,
        category: state.selectedCategory,
      );
      if (path != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('تم تصدير ملف إكسيل المصروفات بنجاح:\n$path'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('خطأ أثناء التصدير: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
      child: BlocBuilder<ExpensesCubit, ExpensesState>(
        builder: (context, state) {
          final canAdd = _canAddExpense(context);
          final q = _searchQuery.trim().toLowerCase();
          final visibleExpenses = q.isEmpty
              ? state.expenses
              : state.expenses.where((exp) {
                  return exp.category.toLowerCase().contains(q) ||
                      (exp.note?.toLowerCase().contains(q) ?? false) ||
                      exp.userId.toLowerCase().contains(q) ||
                      exp.formattedAmount.toLowerCase().contains(q);
                }).toList();

          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.f2): () =>
                  _searchFocusNode.requestFocus(),
              const SingleActivator(LogicalKeyboardKey.f3): () {
                if (_canAddExpense(context)) {
                  _openAddExpenseDialog(context, state.categories);
                }
              },
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  _handleEsc(context),
            },
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, event) => handleNumpadAddShortcut(event, () {
                if (_canAddExpense(context)) {
                  _openAddExpenseDialog(context, state.categories);
                }
              }),
              child: Scaffold(
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
                    'تسجيل ومتابعة مصاريف التشغيل والإيجار والمرافق والبنود المرنة',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade800,
                      side: BorderSide(color: Colors.green.shade400),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _exportExpensesToExcel(context, state),
                    icon: const Icon(Icons.table_view_rounded, size: 18, color: Colors.green),
                    label: const Text('تصدير إكسيل', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  child: ElevatedButton.icon(
                    key: const Key('add_expense_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: canAdd
                        ? () => _openAddExpenseDialog(context, state.categories)
                        : null,
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    label: const Text('تسجيل مصروف جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                // Date & Filter bar
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final searchField = TextField(
                            key: const Key('expenses_search_field'),
                            controller: _searchCtrl,
                            focusNode: _searchFocusNode,
                            onChanged: (val) =>
                                setState(() => _searchQuery = val),
                            decoration: InputDecoration(
                              hintText:
                                  'ابحث في المصروفات بالبند أو البيان أو المبلغ... (F2)',
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              isDense: true,
                              filled: true,
                              fillColor: AppColors.surfaceContainer,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppColors.outlineVariant,
                                ),
                              ),
                            ),
                          );

                          final dateChips = StandardDateFilterChips(
                            activeFilter: _activeDateFilter,
                            customRange: _dateRange,
                            onFilterChanged: (v) => _applyDateFilter(
                              context,
                              v,
                              category: state.selectedCategory,
                            ),
                            onCustomRangePicked: (picked) => _applyDateFilter(
                              context,
                              'custom',
                              custom: picked,
                              category: state.selectedCategory,
                            ),
                          );

                          if (constraints.maxWidth >= 880) {
                            return Row(
                              children: [
                                Expanded(child: searchField),
                                const SizedBox(width: 12),
                                dateChips,
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              searchField,
                              const SizedBox(height: 10),
                              dateChips,
                            ],
                          );
                        },
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
                            ...state.categories.map((cat) {
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
                                child: Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 24),
                              ),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('عدد سندات الصرف', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${visibleExpenses.length} مصروف',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary),
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
                      : visibleExpenses.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.money_off_csred_rounded, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'لا توجد مصروفات مطابقة للبحث'
                                        : 'لا توجد مصروفات مسجلة خلال هذه الفترة',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              itemCount: visibleExpenses.length,
                              separatorBuilder: (_, index) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final exp = visibleExpenses[index];
                                return Material(
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: Colors.grey.shade200),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: ListTile(
                                    leading: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(Icons.payments_outlined, color: AppColors.primary),
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
            ),
            ),
            ),
          );
        },
      ),
    );
  }
}
