import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../domain/entities/customer_installment_entity.dart';
import '../../domain/entities/installment_payment_entity.dart';
import '../../domain/entities/installment_schedule_entry.dart';
import '../../domain/facades/installments_facade.dart';
import '../cubits/installment_detail_cubit.dart';
import 'record_payment_screen.dart';

class InstallmentDetailScreen extends StatelessWidget {
  final String contractId;

  const InstallmentDetailScreen({
    super.key,
    required this.contractId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => InstallmentDetailCubit(
        contractId: contractId,
        facade: getIt<InstallmentsFacade>(),
        customerRepo: getIt<CustomerRepository>(),
      ),
      child: const _InstallmentDetailView(),
    );
  }
}

class _InstallmentDetailView extends StatefulWidget {
  const _InstallmentDetailView();

  @override
  State<_InstallmentDetailView> createState() => _InstallmentDetailViewState();
}

class _InstallmentDetailViewState extends State<_InstallmentDetailView> {
  @override
  void initState() {
    super.initState();
    _guardFeature();
  }

  Future<void> _guardFeature() async {
    final enabled = await getIt<FeatureGate>().isEnabled(FeatureKeys.installments);
    if (!enabled && mounted) {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ميزة التقسيط غير مفعلة')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InstallmentDetailCubit>();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'تفاصيل عقد التقسيط',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            tooltip: 'تحديث',
            onPressed: () => cubit.refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlocConsumer<InstallmentDetailCubit, InstallmentDetailState>(
        listener: (context, state) {
          if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!), backgroundColor: Colors.red),
            );
          }
        },
        builder: (context, state) {
          if (state.status == InstallmentDetailStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == InstallmentDetailStatus.error || state.contract == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'خطأ: ${state.errorMessage ?? "تعذر تحميل تفاصيل العقد"}',
                    style: GoogleFonts.cairo(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => cubit.load(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }

          final contract = state.contract!;
          final now = DateTime.now();
          final computedStatus = contract.statusAt(now);
          final canPay = computedStatus == 'active' || computedStatus == 'overdue';

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header KPI & Customer Overview Card
                    _buildHeaderCard(context, contract, state.customerName, computedStatus, state.payments, state.schedule),
                    const SizedBox(height: 16),

                    // Actions Bar
                    _buildActionsBar(context, cubit, contract, canPay),
                    const SizedBox(height: 20),

                    // Schedule Table Section
                    _buildScheduleSection(context, state.schedule, state.payments, contract),
                    const SizedBox(height: 20),

                    // Payments Log Section
                    _buildPaymentsLogSection(context, state.payments),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    CustomerInstallmentEntity contract,
    String? customerName,
    String computedStatus,
    List<InstallmentPaymentEntity> payments,
    List<InstallmentScheduleEntry> schedule,
  ) {
    final displayName = customerName ?? 'عميل #${contract.customerId.substring(0, 8)}';
    final startStr = DateFormat('yyyy/MM/dd').format(contract.startDate);
    final endStr = DateFormat('yyyy/MM/dd').format(contract.endDate);

    // Total cash actually paid across down payment and installments
    final totalPaidPiasters = payments.fold<int>(0, (sum, p) => sum + p.amountPiasters);
    final totalScheduledPiasters = schedule.fold<int>(0, (sum, e) => sum + e.amountPiasters);
    final totalContractObligation = contract.downPaymentPiasters + totalScheduledPiasters;
    
    // Progress calculation
    final progress = totalContractObligation > 0
        ? (totalPaidPiasters / totalContractObligation).clamp(0.0, 1.0)
        : 0.0;
    final percentDisplay = (progress * 100).toInt();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Customer & Status Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'عقد تقسيط رقم: #${contract.id.substring(0, 8).toUpperCase()}',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              _buildBadge(computedStatus),
            ],
          ),
          const SizedBox(height: 20),

          // Progress Bar with summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF3F4F6)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'نسبة السداد: $percentDisplay%',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      '${Money(totalPaidPiasters).toDisplay()} ج.م مسدد من إجمالي ${Money(totalContractObligation).toDisplay()} ج.م',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4 Metric Stat Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 850;
              final card1 = _buildMetricCard(
                title: 'إجمالي العقد',
                value: '${Money(contract.totalPiasters).toDisplay()} ج.م',
                icon: Icons.receipt_long_rounded,
                iconColor: AppColors.primary,
                bgColor: const Color(0xFFF6F3FF),
              );
              final card2 = _buildMetricCard(
                title: 'الدفعة المقدمة',
                value: '${Money(contract.downPaymentPiasters).toDisplay()} ج.م',
                icon: Icons.payments_outlined,
                iconColor: const Color(0xFF0284C7),
                bgColor: const Color(0xFFF0F9FF),
              );
              final card3 = _buildMetricCard(
                title: 'المدفوع حتى الآن',
                value: '${Money(totalPaidPiasters).toDisplay()} ج.م',
                icon: Icons.check_circle_outline_rounded,
                iconColor: AppColors.success,
                bgColor: AppColors.successContainer.withValues(alpha: 0.5),
              );
              final card4 = _buildMetricCard(
                title: 'المتبقي',
                value: '${Money(contract.remainingPiasters).toDisplay()} ج.م',
                icon: Icons.pending_actions_rounded,
                iconColor: AppColors.warning,
                bgColor: AppColors.warningContainer.withValues(alpha: 0.5),
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: card1),
                    const SizedBox(width: 12),
                    Expanded(child: card2),
                    const SizedBox(width: 12),
                    Expanded(child: card3),
                    const SizedBox(width: 12),
                    Expanded(child: card4),
                  ],
                );
              } else {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: card1),
                        const SizedBox(width: 12),
                        Expanded(child: card2),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: card3),
                        const SizedBox(width: 12),
                        Expanded(child: card4),
                      ],
                    ),
                  ],
                );
              }
            },
          ),
          const SizedBox(height: 20),

          // Metadata Chips Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              spacing: 24,
              runSpacing: 10,
              alignment: WrapAlignment.start,
              children: [
                _buildMetaItem(Icons.calendar_today_rounded, 'تاريخ البدء', startStr),
                _buildMetaItem(Icons.event_available_rounded, 'تاريخ الاستحقاق', endStr),
                _buildMetaItem(Icons.schedule_rounded, 'المدة', '${contract.durationMonths} شهور'),
                _buildMetaItem(
                  Icons.timelapse_rounded,
                  'القسط الشهري التقديري',
                  '${Money(contract.monthlyAmountPiasters).toDisplay()} ج.م',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600),
        ),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildActionsBar(
    BuildContext context,
    InstallmentDetailCubit cubit,
    CustomerInstallmentEntity contract,
    bool canPay,
  ) {
    return Row(
      children: [
        if (canPay)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.payment_rounded, size: 20),
            label: Text(
              'تسجيل دفعة جديدة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RecordPaymentScreen(contractId: contract.id),
                ),
              ).then((_) => cubit.refresh());
            },
          ),
        if (canPay) const SizedBox(width: 12),
        if (contract.status != 'cancelled' && contract.status != 'completed')
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.cancel_outlined, size: 20),
            label: Text(
              'إلغاء العقد',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: () => _confirmCancelContract(context, cubit),
          ),
      ],
    );
  }

  void _confirmCancelContract(BuildContext context, InstallmentDetailCubit cubit) async {
    final featureGate = getIt<FeatureGate>();
    final isAdmin = await featureGate.isCurrentUserAdmin();
    if (!context.mounted) return;

    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('غير مصرح: إلغاء عقود التقسيط متاح للمدير فقط'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'تأكيد إلغاء العقد',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من رغبتك في إلغاء هذا العقد؟ لن يمكن تسجيل دفعات جديدة عليه بعد الإلغاء.',
              style: GoogleFonts.cairo(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'الرقم السري للمدير (PIN)',
                labelStyle: GoogleFonts.cairo(),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('رجوع', style: GoogleFonts.cairo(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final pin = pinController.text.trim();
              if (pin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء إدخال الرقم السري للمدير')),
                );
                return;
              }
              Navigator.of(dialogCtx).pop();
              final success = await cubit.cancelContract(pin);
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم إلغاء العقد بنجاح'), backgroundColor: Colors.green),
                );
              }
            },
            child: Text('تأكيد الإلغاء', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection(
    BuildContext context,
    List<InstallmentScheduleEntry> schedule,
    List<InstallmentPaymentEntity> payments,
    CustomerInstallmentEntity contract,
  ) {
    // Total scheduled installments obligation
    final totalSchedulePiasters = schedule.fold<int>(0, (s, e) => s + e.amountPiasters);
    // Paid towards the schedule: difference between total scheduled and remaining balance
    final paidTowardsSchedule = totalSchedulePiasters - contract.remainingPiasters;
    final isContractCompleted = contract.status == 'completed' || contract.remainingPiasters <= 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.table_chart_rounded, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'جدول الأقساط والاستحقاقات',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${schedule.length} أقساط مجدولة',
                  style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (schedule.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'لا يوجد جدول متاح لهذا العقد',
                  style: GoogleFonts.cairo(color: Colors.grey),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8F9FC)),
                    headingTextStyle: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.onSurface,
                    ),
                    dataTextStyle: GoogleFonts.cairo(fontSize: 13, color: AppColors.onSurface),
                    columnSpacing: 24,
                    horizontalMargin: 16,
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('تاريخ الاستحقاق')),
                      DataColumn(label: Text('المبلغ')),
                      DataColumn(label: Text('أصل المبلغ')),
                      DataColumn(label: Text('الفائدة')),
                      DataColumn(label: Text('الحالة')),
                    ],
                    rows: schedule.asMap().entries.map((mapEntry) {
                      final index = mapEntry.key;
                      final entry = mapEntry.value;

                      // Accurate cumulative payment check
                      int cumulativePrior = 0;
                      for (int j = 0; j < index; j++) {
                        cumulativePrior += schedule[j].amountPiasters;
                      }
                      final cumulativeRequired = cumulativePrior + entry.amountPiasters;

                      final bool isPaid = isContractCompleted || (paidTowardsSchedule >= cumulativeRequired);
                      final bool isPartiallyPaid = !isPaid && (paidTowardsSchedule > cumulativePrior);
                      final now = DateTime.now();
                      final isOverdue = !isPaid && !isPartiallyPaid && now.isAfter(entry.dueDate);

                      final String statusLabel;
                      final Color statusColor;
                      final Color statusBg;
                      final IconData statusIcon;

                      if (isPaid) {
                        statusLabel = 'مدفوع';
                        statusColor = AppColors.success;
                        statusBg = AppColors.successContainer;
                        statusIcon = Icons.check_circle_rounded;
                      } else if (isPartiallyPaid) {
                        statusLabel = 'مدفوع جزئياً';
                        statusColor = const Color(0xFFD97706);
                        statusBg = const Color(0xFFFEF3C7);
                        statusIcon = Icons.hourglass_bottom_rounded;
                      } else if (isOverdue) {
                        statusLabel = 'متأخر';
                        statusColor = AppColors.error;
                        statusBg = AppColors.errorContainer;
                        statusIcon = Icons.warning_amber_rounded;
                      } else {
                        statusLabel = 'مستحق';
                        statusColor = const Color(0xFF2563EB);
                        statusBg = const Color(0xFFEFF6FF);
                        statusIcon = Icons.schedule_rounded;
                      }

                      return DataRow(
                        color: WidgetStateProperty.resolveWith<Color?>((states) {
                          if (index.isOdd) return const Color(0xFFFAFAFC);
                          return Colors.white;
                        }),
                        cells: [
                          DataCell(
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isPaid ? AppColors.successContainer : const Color(0xFFF3F4F6),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${entry.installmentNumber}',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isPaid ? AppColors.success : Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.event_outlined, size: 15, color: Colors.grey),
                                const SizedBox(width: 6),
                                Text(DateFormat('yyyy/MM/dd').format(entry.dueDate)),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              '${Money(entry.amountPiasters).toDisplay()} ج.م',
                              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                            ),
                          ),
                          DataCell(Text('${Money(entry.principalComponentPiasters).toDisplay()} ج.م')),
                          DataCell(Text('${Money(entry.interestComponentPiasters).toDisplay()} ج.م')),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, size: 14, color: statusColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusLabel,
                                    style: GoogleFonts.cairo(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildPaymentsLogSection(
    BuildContext context,
    List<InstallmentPaymentEntity> payments,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: AppColors.success, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'سجل الدفعات والمتحصلات',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${payments.length} دفعات مسجلة',
                  style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'لم يتم تسجيل أي دفعات حتى الآن',
                  style: GoogleFonts.cairo(color: Colors.grey),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: payments.length,
              separatorBuilder: (_, index) => const Divider(height: 1, color: Color(0xFFF3F4F6)),
              itemBuilder: (context, index) {
                final payment = payments[index];
                final dateStr = DateFormat('yyyy/MM/dd • HH:mm').format(payment.paidAt);
                final isDownPayment = payment.receiptNumber == 'DOWN_PAYMENT';
                final payMethodAr = payment.paymentMethod == 'cash'
                    ? 'نقدي'
                    : payment.paymentMethod == 'card'
                        ? 'بطاقة / فيزا'
                        : payment.paymentMethod;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDownPayment ? const Color(0xFFE0F2FE) : const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isDownPayment ? Icons.account_balance_wallet_rounded : Icons.check_circle_rounded,
                          color: isDownPayment ? const Color(0xFF0369A1) : AppColors.success,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isDownPayment ? 'دفعة مقدمة' : 'دفعة قسط: ${Money(payment.amountPiasters).toDisplay()} ج.م',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 8,
                              children: [
                                Text(
                                  'طريقة الدفع: $payMethodAr',
                                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                Text('•', style: TextStyle(color: Colors.grey.shade400)),
                                Text(
                                  'بواسطة: ${payment.recordedBy}',
                                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                Text('•', style: TextStyle(color: Colors.grey.shade400)),
                                Text(
                                  dateStr,
                                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDownPayment ? const Color(0xFFF0F9FF) : const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDownPayment ? const Color(0xFFBAE6FD) : const Color(0xFFBBF7D0),
                          ),
                        ),
                        child: Text(
                          '${Money(payment.amountPiasters).toDisplay()} ج.م',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isDownPayment ? const Color(0xFF0369A1) : AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBadge(String status) {
    Color color;
    Color bg;
    String label;
    IconData icon;

    switch (status) {
      case 'active':
        color = const Color(0xFF1D4ED8);
        bg = const Color(0xFFEFF6FF);
        label = 'عقد نشط';
        icon = Icons.verified_rounded;
        break;
      case 'overdue':
        color = AppColors.error;
        bg = AppColors.errorContainer;
        label = 'متأخر في السداد';
        icon = Icons.error_rounded;
        break;
      case 'completed':
        color = AppColors.success;
        bg = AppColors.successContainer;
        label = 'عقد مكتمل';
        icon = Icons.task_alt_rounded;
        break;
      case 'cancelled':
        color = Colors.grey.shade800;
        bg = Colors.grey.shade200;
        label = 'عقد ملغي';
        icon = Icons.block_rounded;
        break;
      default:
        color = Colors.grey.shade700;
        bg = Colors.grey.shade100;
        label = status;
        icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.cairo(color: color, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
