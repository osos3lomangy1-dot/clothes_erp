import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../domain/entities/employee_payroll_summary.dart';
import '../cubits/cashier_payroll_cubit.dart';
import '../cubits/cashier_payroll_state.dart';

class CashierPayrollCard extends StatelessWidget {
  final String employeeId;
  final bool showActions;

  const CashierPayrollCard({
    super.key,
    required this.employeeId,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CashierPayrollCubit, CashierPayrollState>(
      builder: (context, state) {
        if (state is CashierPayrollLoading) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('جارِ تحميل بيانات ومستحقات الكاشير...'),
                ],
              ),
            ),
          );
        }

        if (state is CashierPayrollError) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'تعذر تحميل بيانات الكاشير: ${state.message}',
                    style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => context.read<CashierPayrollCubit>().loadSummary(employeeId),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }

        if (state is CashierPayrollLoaded) {
          final summary = state.summary;

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header: Cashier profile banner & Month switcher
                _buildHeader(context, summary, state.isOperating),
                const Divider(height: 1),

                // Metrics Grid
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Row 1: Salary Status & Basic Salary
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.payments_rounded,
                              iconBg: Colors.blue.shade50,
                              iconColor: Colors.blue.shade700,
                              title: 'الراتب الأساسي',
                              value: summary.basicSalary > 0
                                  ? '${Money(summary.basicSalary).toDisplay()} ج.م'
                                  : 'غير محدد',
                              subtitle: 'الراتب الشهري المتفق عليه',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSalaryStatusTile(summary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Row 2: Bonus & Advances
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.stars_rounded,
                              iconBg: Colors.amber.shade50,
                              iconColor: Colors.amber.shade800,
                              title: 'البونص والمكافآت',
                              value: summary.bonusThisMonth > 0
                                  ? '+${Money(summary.bonusThisMonth).toDisplay()} ج.م'
                                  : '0.00 ج.م',
                              subtitle: summary.bonusThisMonth > 0
                                  ? 'يوجد بونص مستحق لهذا الشهر 🎉'
                                  : 'لا يوجد بونص مسجل لهذا الشهر',
                              valueColor: summary.bonusThisMonth > 0
                                  ? Colors.green.shade700
                                  : AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.money_off_rounded,
                              iconBg: Colors.red.shade50,
                              iconColor: Colors.red.shade700,
                              title: 'السلف والخصومات',
                              value: summary.advancesThisMonth > 0
                                  ? '-${Money(summary.advancesThisMonth).toDisplay()} ج.م'
                                  : '0.00 ج.م',
                              subtitle: summary.advancesThisMonth > 0
                                  ? 'إجمالي السلفيات المسحوبة'
                                  : 'لا توجد سلفيات مسجلة',
                              valueColor: summary.advancesThisMonth > 0
                                  ? Colors.red.shade700
                                  : AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Row 3: Net Due & Shift Status
                      Row(
                        children: [
                          Expanded(
                            child: _buildNetDueTile(summary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildShiftTile(summary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Bottom Action buttons (if enabled)
                if (showActions) ...[
                  const Divider(height: 1),
                  _buildActionButtons(context, summary),
                ],
              ],
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildHeader(BuildContext context, EmployeePayrollSummary summary, bool isOperating) {
    final emp = summary.employee;
    final cubit = context.read<CashierPayrollCubit>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.primary,
            child: Text(
              emp.displayName.isNotEmpty ? emp.displayName[0] : 'ك',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        emp.displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        emp.role == 'cashier' ? 'كاشير' : (emp.role == 'manager' ? 'مدير' : 'مسؤول'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.alternate_email_rounded, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      emp.username,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: emp.isActive ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      emp.isActive ? 'الحساب نشط' : 'الحساب معطل',
                      style: TextStyle(
                        fontSize: 11,
                        color: emp.isActive ? Colors.green.shade700 : Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Month Switcher
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  tooltip: 'الشهر السابق',
                  onPressed: isOperating ? null : () => cubit.changeMonth(-1),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    summary.monthArabicName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  tooltip: 'الشهر التالي',
                  onPressed: isOperating ? null : () => cubit.changeMonth(1),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: valueColor ?? AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalaryStatusTile(EmployeePayrollSummary summary) {
    Color statusBg;
    Color statusColor;
    String statusText;
    String subtitle;
    IconData icon;

    switch (summary.salaryStatus) {
      case PayrollSalaryStatus.fullyPaid:
        statusBg = Colors.green.shade50;
        statusColor = Colors.green.shade700;
        statusText = 'تم استلام الراتب بالكامل ✅';
        subtitle = 'تم صرف ${Money(summary.salaryPaidThisMonth).toDisplay()} ج.م';
        icon = Icons.check_circle_rounded;
        break;
      case PayrollSalaryStatus.partiallyPaid:
        statusBg = Colors.orange.shade50;
        statusColor = Colors.orange.shade800;
        statusText = 'مستلم جزئياً ⚠️';
        subtitle = 'المتبقي: ${Money(summary.remainingSalary).toDisplay()} ج.م (صُرف ${Money(summary.salaryPaidThisMonth).toDisplay()})';
        icon = Icons.hourglass_bottom_rounded;
        break;
      case PayrollSalaryStatus.notPaid:
        statusBg = Colors.amber.shade50;
        statusColor = Colors.amber.shade900;
        statusText = 'لم يُصرف راتب الشهر بعد ⏳';
        subtitle = 'المستحق الأساسي: ${Money(summary.basicSalary).toDisplay()} ج.م';
        icon = Icons.pending_rounded;
        break;
      case PayrollSalaryStatus.notSet:
        statusBg = Colors.grey.shade100;
        statusColor = Colors.grey.shade700;
        statusText = 'الراتب غير محدد';
        subtitle = 'يمكن للمدير إدخال الراتب من شاشة الموظفين';
        icon = Icons.help_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'حالة الراتب (الشهر الحالي)',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: statusColor.withValues(alpha: 0.85)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetDueTile(EmployeePayrollSummary summary) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.price_check_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'صافي المستحق حالياً',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${Money(summary.netDue).toDisplay()} ج.م',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'المتبقي من الراتب + البونص - السلف',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftTile(EmployeePayrollSummary summary) {
    final hasShift = summary.hasActiveShift;

    String shiftTime = '';
    if (summary.shiftOpenedAt != null) {
      final t = summary.shiftOpenedAt!;
      shiftTime = 'منذ ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasShift ? Colors.teal.shade50 : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasShift ? Colors.teal.shade300 : Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: hasShift ? Colors.teal.shade100 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              hasShift ? Icons.lock_open_rounded : Icons.lock_clock_rounded,
              color: hasShift ? Colors.teal.shade800 : Colors.grey.shade600,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الوردية الحالية',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  hasShift ? 'وردية مفتوحة 🟢' : 'الوردية مغلقة ⚪',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: hasShift ? Colors.teal.shade800 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasShift
                      ? '$shiftTime (عهدة: ${Money(summary.shiftOpeningBalance ?? 0).toDisplay()} ج.م)'
                      : 'لا توجد وردية مفتوحة للكاشير حالياً',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, EmployeePayrollSummary summary) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          // View Ledger / Statement
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: Text('كشف حساب الشهر (${summary.transactions.length})'),
            onPressed: () => _showTransactionsDialog(context, summary),
          ),

          // Pay Salary
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.payments_rounded, size: 18),
            label: const Text('صرف راتب / دفعة'),
            onPressed: () => _showRecordDialog(
              context,
              summary: summary,
              type: 'salary',
              title: 'صرف راتب الموظف',
              suggestedAmount: summary.remainingSalary > 0
                  ? summary.remainingSalary
                  : summary.basicSalary,
            ),
          ),

          // Add Bonus
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.stars_rounded, size: 18),
            label: const Text('إضافة بونص / مكافأة'),
            onPressed: () => _showRecordDialog(
              context,
              summary: summary,
              type: 'bonus',
              title: 'تسجيل بونص ومكافأة تشجيعية',
              suggestedAmount: 50000, // 500 EGP
            ),
          ),

          // Add Advance / Deduction
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.money_off_rounded, size: 18),
            label: const Text('تسجيل سلفة'),
            onPressed: () => _showRecordDialog(
              context,
              summary: summary,
              type: 'advance',
              title: 'تسجيل سلفة نقدية على الراتب',
              suggestedAmount: 20000, // 200 EGP
            ),
          ),
        ],
      ),
    );
  }

  void _showTransactionsDialog(BuildContext context, EmployeePayrollSummary summary) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'كشف حساب: ${summary.employee.displayName} (${summary.monthArabicName})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550, maxHeight: 400),
          child: summary.transactions.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'لا توجد عمليات صرف أو مكافآت مسجلة لهذا الشهر حتى الآن.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: summary.transactions.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final tx = summary.transactions[i];
                    final isBonus = tx.category.contains('بونص') || tx.category.contains('مكاف');
                    final isAdvance = tx.category.contains('سلف') || tx.category.contains('خصم');

                    Color color = Colors.teal;
                    IconData icon = Icons.payments_rounded;
                    String sign = '';

                    if (isBonus) {
                      color = Colors.amber.shade800;
                      icon = Icons.stars_rounded;
                      sign = '+';
                    } else if (isAdvance) {
                      color = Colors.red;
                      icon = Icons.money_off_rounded;
                      sign = '-';
                    }

                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(icon, color: color, size: 18),
                      ),
                      title: Row(
                        children: [
                          Text(
                            tx.category,
                            style: TextStyle(fontWeight: FontWeight.bold, color: color),
                          ),
                          const Spacer(),
                          Text(
                            '$sign${Money(tx.amount).toDisplay()} ج.م',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (tx.note != null && tx.note!.isNotEmpty)
                            Text(tx.note!, style: const TextStyle(fontSize: 12)),
                          Text(
                            'التاريخ: ${tx.expenseDate.year}-${tx.expenseDate.month.toString().padLeft(2, '0')}-${tx.expenseDate.day.toString().padLeft(2, '0')}',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showRecordDialog(
    BuildContext context, {
    required EmployeePayrollSummary summary,
    required String type,
    required String title,
    required int suggestedAmount,
  }) {
    final cubit = context.read<CashierPayrollCubit>();
    final amountCtrl = TextEditingController(
      text: suggestedAmount > 0 ? '${suggestedAmount / 100}' : '',
    );
    final noteCtrl = TextEditingController();
    DateTime txDate = DateTime.now();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_rounded, size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'الموظف: ${summary.employee.displayName}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ بالج.م *',
                      suffixText: 'ج.م',
                      prefixIcon: const Icon(Icons.attach_money_rounded, color: AppColors.primary),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال المبلغ';
                      final num = double.tryParse(val.trim());
                      if (num == null || num <= 0) return 'المبلغ يجب أن يكون أكبر من الصفر';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    leading: const Icon(Icons.calendar_today_rounded, color: AppColors.primary),
                    title: const Text('تاريخ المعاملة', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    subtitle: Text(
                      '${txDate.year}-${txDate.month.toString().padLeft(2, '0')}-${txDate.day.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: txDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => txDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظات إضافية (اختياري)',
                      hintText: 'مثال: مكافأة تحقيق تارجت، سلفة طارئة...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
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
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                final pounds = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final piasters = (pounds * 100).toInt();

                String currentUserId = 'admin';
                try {
                  final auth = context.read<AuthCubit>().state;
                  if (auth is AuthAuthenticated) currentUserId = auth.user.id;
                } catch (_) {}

                final ok = await cubit.recordTransaction(
                  employeeId: summary.employee.id,
                  type: type,
                  amount: piasters,
                  note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                  date: txDate,
                  currentUserId: currentUserId,
                );

                if (ok && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تسجيل المعاملة المالية وتحديث البيانات بنجاح'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              child: const Text('حفظ المعاملة'),
            ),
          ],
        ),
      ),
    );
  }
}
