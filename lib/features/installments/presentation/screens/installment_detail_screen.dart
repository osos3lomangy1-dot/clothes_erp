import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../data/services/manager_pin_service.dart';
import '../../domain/entities/customer_installment_entity.dart';
import '../../domain/entities/installment_payment_entity.dart';
import '../../domain/entities/installment_schedule_entry.dart';
import '../../domain/facades/installments_facade.dart';
import '../../domain/services/installment_calculator.dart';
import '../cubits/installment_detail_cubit.dart';
import '../widgets/early_settlement_dialog.dart';
import '../widgets/promissory_note_delivery_dialog.dart';
import 'record_payment_screen.dart';

class InstallmentDetailScreen extends StatelessWidget {
  final String contractId;

  const InstallmentDetailScreen({super.key, required this.contractId});

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
    final enabled = await getIt<FeatureGate>().isEnabled(
      FeatureKeys.installments,
    );
    if (!enabled && mounted) {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ميزة التقسيط غير مفعلة')));
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
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.onSurface,
          ),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'تفاصيل عقد التقسيط',
          style: TextStyle(
            fontFamily: 'Cairo',
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
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state.status == InstallmentDetailStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == InstallmentDetailStatus.error ||
              state.contract == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'خطأ: ${state.errorMessage ?? "تعذر تحميل تفاصيل العقد"}',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
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
          final canPay =
              computedStatus == 'active' ||
              computedStatus == 'overdue' ||
              computedStatus == 'legal_case';

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header KPI & Customer Overview Card
                    _buildHeaderCard(
                      context,
                      cubit,
                      contract,
                      state.customerName,
                      computedStatus,
                      state.payments,
                      state.schedule,
                    ),
                    const SizedBox(height: 16),

                    // Actions Bar
                    _buildActionsBar(context, cubit, state, contract, canPay),
                    const SizedBox(height: 20),

                    // Schedule Table Section
                    _buildScheduleSection(context, state.allocations, contract),
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
    InstallmentDetailCubit cubit,
    CustomerInstallmentEntity contract,
    String? customerName,
    String computedStatus,
    List<InstallmentPaymentEntity> payments,
    List<InstallmentScheduleEntry> schedule,
  ) {
    final displayName =
        customerName ?? 'عميل #${contract.customerId.substring(0, 8)}';
    final startStr = DateFormat('yyyy/MM/dd').format(contract.startDate);
    final firstDueDate = schedule.isNotEmpty
        ? schedule.first.dueDate
        : InstallmentCalculator.addMonths(contract.startDate, 1);
    final firstDueStr = DateFormat('yyyy/MM/dd').format(firstDueDate);
    final endStr = DateFormat('yyyy/MM/dd').format(contract.endDate);

    // Total cash actually paid across down payment and installments (excluding waived interest)
    final totalWaivedPiasters = payments
        .where(
          (p) =>
              p.receiptNumber == 'INTEREST_WAIVER' ||
              p.paymentMethod == 'waiver',
        )
        .fold<int>(0, (sum, p) => sum + p.amountPiasters);
    final totalPaidPiasters = payments
        .where(
          (p) =>
              p.receiptNumber != 'INTEREST_WAIVER' &&
              p.paymentMethod != 'waiver',
        )
        .fold<int>(0, (sum, p) => sum + p.amountPiasters);
    final totalScheduledPiasters = schedule.fold<int>(
      0,
      (sum, e) => sum + e.amountPiasters,
    );
    final totalContractObligation =
        contract.downPaymentPiasters + totalScheduledPiasters;

    // Progress calculation (cash paid + waived settlement closes out 100%)
    final progress = totalContractObligation > 0
        ? ((totalPaidPiasters + totalWaivedPiasters) / totalContractObligation)
              .clamp(0.0, 1.0)
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
                child: Icon(
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
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'عقد تقسيط رقم: #${contract.id.substring(0, 8).toUpperCase()}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
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
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      totalWaivedPiasters > 0
                          ? '${Money(totalPaidPiasters).toDisplay()} ج.م مسدد + ${Money(totalWaivedPiasters).toDisplay()} ج.م إعفاء سداد مبكر'
                          : '${Money(totalPaidPiasters).toDisplay()} ج.م مسدد من إجمالي ${Money(totalContractObligation).toDisplay()} ج.م',
                      style: TextStyle(
                        fontFamily: 'Cairo',
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
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Promissory Note status banner
          _buildPromissoryNoteBanner(context, cubit, contract),
          const SizedBox(height: 20),

          // 4 Metric Stat Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 850;
              final card1 = _buildMetricCard(
                title: 'إجمالي العقد',
                value: '${Money(contract.totalPiasters).toDisplay()} ج.م',
                icon: Icons.receipt_long_rounded,
                iconColor: AppColors.onSurfaceVariant,
              );
              final card2 = _buildMetricCard(
                title: 'الدفعة المقدمة',
                value: '${Money(contract.downPaymentPiasters).toDisplay()} ج.م',
                icon: Icons.payments_outlined,
                iconColor: AppColors.onSurfaceVariant,
              );
              final card3 = _buildMetricCard(
                title: 'المدفوع حتى الآن',
                value: '${Money(totalPaidPiasters).toDisplay()} ج.م',
                icon: Icons.check_circle_outline_rounded,
                iconColor: AppColors.success,
                valueColor: AppColors.success,
              );
              final card4 = _buildMetricCard(
                title: 'المتبقي',
                value: '${Money(contract.remainingPiasters).toDisplay()} ج.م',
                icon: Icons.pending_actions_rounded,
                iconColor: AppColors.warning,
                valueColor: AppColors.warning,
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
                _buildMetaItem(
                  Icons.calendar_today_rounded,
                  'تاريخ الشراء (المقدم)',
                  startStr,
                ),
                _buildMetaItem(
                  Icons.event_note_rounded,
                  'تاريخ أول قسط',
                  firstDueStr,
                ),
                _buildMetaItem(
                  Icons.event_available_rounded,
                  'تاريخ آخر قسط',
                  endStr,
                ),
                _buildMetaItem(
                  Icons.schedule_rounded,
                  'المدة',
                  '${contract.durationMonths} شهور',
                ),
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
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: valueColor ?? AppColors.onSurface,
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
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
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
    InstallmentDetailState state,
    CustomerInstallmentEntity contract,
    bool canPay,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        if (canPay && contract.status != 'legal_case')
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.payment_rounded, size: 20),
            label: const Text(
              'تسجيل دفعة جديدة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            onPressed: () async {
              final saved = await showRecordPaymentDialog(
                context,
                contractId: contract.id,
              );
              if (saved == true && context.mounted) {
                await cubit.refresh();
                if (!context.mounted) return;
                final updated = cubit.state.contract;
                if (updated != null &&
                    updated.remainingPiasters <= 0 &&
                    !updated.promissoryNoteDelivered &&
                    updated.hasPromissoryNote) {
                  final result = await showPromissoryNoteDeliveryDialog(
                    context,
                    customerName: cubit.state.customerName,
                  );
                  if (result != null && context.mounted) {
                    await cubit.markPromissoryNoteDelivered(
                      result != PromissoryNoteDeliveryResult.inSafe,
                      hasNote: result != PromissoryNoteDeliveryResult.noReceipt,
                    );
                  }
                }
              }
            },
          ),
        if (canPay && contract.status != 'legal_case')
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.onSurface,
              side: const BorderSide(color: AppColors.outlineVariant),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: state.isSettling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bolt_rounded, size: 20),
            label: const Text(
              'سداد مبكر / تسوية العقد',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            onPressed: state.isSettling
                ? null
                : () => _openEarlySettlementDialog(
                    context,
                    cubit,
                    state,
                    contract,
                  ),
          ),
        if (contract.status == 'legal_case') ...[
          // Option 1: ⚖️ تحصيل وتسوية قضائية (تم التخليص)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.gavel_rounded, size: 20),
            label: const Text(
              '⚖️ تحصيل وتسوية قضائية (تم التخليص)',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            onPressed: () => _openJudicialSettlementDialog(
              context,
              cubit,
              state,
              contract,
            ),
          ),

          // Option 2: ⛔ إثبات تهرب / إعدام دين
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.block_rounded, size: 20),
            label: const Text(
              '⛔ إثبات تهرب / إعدام دين',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            onPressed: () => _confirmBadDebtWriteOff(context, cubit, contract),
          ),

          // Option 3: ↩️ إلغاء الإجراء القانوني (إعادة لنشط)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.onSurface,
              side: const BorderSide(color: AppColors.outlineVariant),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.undo_rounded, size: 20),
            label: const Text(
              '↩️ إلغاء الإجراء القانوني (إعادة لنشط)',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            onPressed: () => _confirmToggleLegalCase(context, cubit, false),
          ),
        ] else if (contract.status != 'cancelled' &&
            contract.status != 'completed' &&
            contract.status != 'written_off' &&
            contract.status != 'cancelled_bad_debt') ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error.withValues(alpha: 0.8),
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.gavel_rounded, size: 20),
            label: const Text(
              'تحويل لإجراء قانوني',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            onPressed: () => _confirmToggleLegalCase(context, cubit, true),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error.withValues(alpha: 0.8),
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.cancel_outlined, size: 20),
            label: const Text(
              'إلغاء العقد',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            onPressed: () => _confirmCancelContract(context, cubit),
          ),
        ],
      ],
    );
  }

  Future<void> _openEarlySettlementDialog(
    BuildContext context,
    InstallmentDetailCubit cubit,
    InstallmentDetailState state,
    CustomerInstallmentEntity contract,
  ) async {
    final facade = getIt<InstallmentsFacade>();
    final plansResult = await facade.listPlans();
    final activePlans = plansResult
        .getOrElse(() => [])
        .where((p) => p.isActive)
        .toList();

    final isPinRequired = getIt.isRegistered<ManagerPinService>()
        ? await getIt<ManagerPinService>().isPinRequired()
        : (await getIt<FeatureGate>().getMeta('installments.pin.require')) !=
              '0';

    if (!context.mounted) return;

    final submission = await showDialog<EarlySettlementSubmission>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EarlySettlementDialog(
        contract: contract,
        totalContractInterestPiasters: state.totalContractInterestPiasters,
        paidTowardsScheduleCashPiasters: state.paidTowardsScheduleCashPiasters,
        activePlans: activePlans,
        isPinRequired: isPinRequired,
      ),
    );

    if (submission == null || !context.mounted) return;

    final ok = await cubit.settleEarly(
      waivedInterestPiasters: submission.waivedInterestPiasters,
      paymentMethod: submission.paymentMethod,
      pin: submission.pin,
      notes: submission.notes,
      settledAt: submission.settledAt,
    );

    if (ok && context.mounted) {
      final result = await showPromissoryNoteDeliveryDialog(
        context,
        customerName: state.customerName,
      );
      if (result != null && context.mounted) {
        await cubit.markPromissoryNoteDelivered(
          result != PromissoryNoteDeliveryResult.inSafe,
          hasNote: result != PromissoryNoteDeliveryResult.noReceipt,
        );
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.teal.shade700,
          content: Text(
            'تم إغلاق العقد بالتسوية المبكرة بنجاح — سداد: ${Money(submission.settlementAmountPiasters).toDisplay()} ج.م | إعفاء فائدة: ${Money(submission.waivedInterestPiasters).toDisplay()} ج.م',
          ),
        ),
      );
    }
  }

  void _confirmCancelContract(
    BuildContext context,
    InstallmentDetailCubit cubit,
  ) async {
    final featureGate = getIt<FeatureGate>();
    final isAdmin = await featureGate.isCurrentUserAdmin();
    if (!context.mounted) return;

    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('غير مصرح: إلغاء عقود التقسيط متاح للمدير فقط'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final isPinRequired = getIt.isRegistered<ManagerPinService>()
        ? await getIt<ManagerPinService>().isPinRequired()
        : (await featureGate.getMeta('installments.pin.require')) != '0';
    if (!context.mounted) return;

    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'تأكيد إلغاء العقد',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'هل أنت متأكد من رغبتك في إلغاء هذا العقد؟ لن يمكن تسجيل دفعات جديدة عليه بعد الإلغاء.',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
            if (isPinRequired) ...[
              const SizedBox(height: 16),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'الرقم السري للمدير (PIN)',
                  labelStyle: const TextStyle(fontFamily: 'Cairo'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(
              'رجوع',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: Colors.grey.shade700,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final pin = isPinRequired ? pinController.text.trim() : '';
              if (isPinRequired && pin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('الرجاء إدخال الرقم السري للمدير'),
                  ),
                );
                return;
              }
              Navigator.of(dialogCtx).pop();
              final success = await cubit.cancelContract(pin);
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم إلغاء العقد بنجاح'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: Text(
              'تأكيد الإلغاء',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection(
    BuildContext context,
    List<InstallmentScheduleAllocation> allocations,
    CustomerInstallmentEntity contract,
  ) {
    final isContractCompleted =
        contract.status == 'completed' || contract.remainingPiasters <= 0;
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

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
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.table_chart_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'جدول الأقساط والاستحقاقات',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'أول قسط يبدأ الشهر التالي للشراء • أي زيادة عن القسط تُرحَّل تلقائياً لآخر قسط',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${allocations.length} أقساط مجدولة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (allocations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'لا يوجد جدول متاح لهذا العقد',
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
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
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFFF8F9FC),
                  ),
                  headingTextStyle: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.onSurface,
                  ),
                  dataTextStyle: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: AppColors.onSurface,
                  ),
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 68,
                  columnSpacing: 20,
                  horizontalMargin: 16,
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('تاريخ الاستحقاق')),
                    DataColumn(label: Text('قيمة القسط')),
                    DataColumn(label: Text('المدفوع / المرحّل')),
                    DataColumn(label: Text('المتبقي')),
                    DataColumn(label: Text('تاريخ السداد الفعلي')),
                    DataColumn(label: Text('الحالة')),
                  ],
                  rows: allocations.asMap().entries.map((mapEntry) {
                    final index = mapEntry.key;
                    final alloc = mapEntry.value;
                    final entry = alloc.entry;

                    final bool isPaid = isContractCompleted || alloc.isPaid;
                    final bool isExcessOnlyPartial =
                        !isPaid &&
                        alloc.paidFromExcessPiasters > 0 &&
                        alloc.paidRegularPiasters == 0;
                    final bool isPartiallyPaid =
                        !isPaid && alloc.isPartiallyPaid;
                    final dueDateOnly = DateTime(
                      entry.dueDate.year,
                      entry.dueDate.month,
                      entry.dueDate.day,
                    );
                    final bool isOverdue =
                        !isPaid && todayDateOnly.isAfter(dueDateOnly);

                    final String statusLabel;
                    final Color statusColor;
                    final Color statusBg;
                    final IconData statusIcon;

                    if (isPaid && alloc.isPaidOnlyFromExcess) {
                      statusLabel = 'مدفوع (ترحيل زيادة)';
                      statusColor = AppColors.success;
                      statusBg = const Color(0xFFF1F5F9);
                      statusIcon = Icons.fast_rewind_rounded;
                    } else if (isPaid) {
                      statusLabel = 'مدفوع';
                      statusColor = AppColors.success;
                      statusBg = const Color(0xFFECFDF5);
                      statusIcon = Icons.check_circle_rounded;
                    } else if (isContractCompleted) {
                      statusLabel = 'مكتمل (تمت التسوية)';
                      statusColor = AppColors.success;
                      statusBg = const Color(0xFFECFDF5);
                      statusIcon = Icons.task_alt_rounded;
                    } else if (isOverdue) {
                      statusLabel = isPartiallyPaid ? 'متأخر (جزئي)' : 'متأخر';
                      statusColor = AppColors.error;
                      statusBg = const Color(0xFFFEF2F2);
                      statusIcon = Icons.warning_amber_rounded;
                    } else if (isExcessOnlyPartial) {
                      statusLabel = 'مرحّل له زيادة';
                      statusColor = const Color(0xFF334155);
                      statusBg = const Color(0xFFF1F5F9);
                      statusIcon = Icons.savings_outlined;
                    } else if (isPartiallyPaid) {
                      statusLabel = 'مدفوع جزئياً';
                      statusColor = const Color(0xFFD97706);
                      statusBg = const Color(0xFFFFFBEB);
                      statusIcon = Icons.hourglass_bottom_rounded;
                    } else {
                      statusLabel = 'مستحق';
                      statusColor = const Color(0xFF334155);
                      statusBg = const Color(0xFFF1F5F9);
                      statusIcon = Icons.schedule_rounded;
                    }

                    // Actual payment date cell
                    Widget paidDateWidget;
                    if (alloc.paidAt == null) {
                      paidDateWidget = Text(
                        '—',
                        style: TextStyle(color: Colors.grey.shade400),
                      );
                    } else {
                      final paidDateStr = DateFormat(
                        'yyyy/MM/dd',
                      ).format(alloc.paidAt!);
                      final diffDays = alloc.daysFromDueDate ?? 0;
                      String timingText;
                      Color timingColor;
                      if (isExcessOnlyPartial || alloc.isPaidOnlyFromExcess) {
                        timingText = 'ترحيل زيادة';
                        timingColor = Colors.purple.shade700;
                      } else if (diffDays < 0) {
                        timingText = 'قبل الموعد (${diffDays.abs()} ي)';
                        timingColor = Colors.teal.shade700;
                      } else if (diffDays == 0) {
                        timingText = 'في الموعد';
                        timingColor = AppColors.success;
                      } else {
                        timingText = 'بعد الموعد ($diffDays ي)';
                        timingColor = AppColors.error;
                      }
                      paidDateWidget = Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            paidDateStr,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            timingText,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: timingColor,
                            ),
                          ),
                        ],
                      );
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
                              color: isPaid
                                  ? AppColors.successContainer
                                  : const Color(0xFFF3F4F6),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${entry.installmentNumber}',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: isPaid
                                    ? AppColors.success
                                    : Colors.grey.shade800,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.event_outlined,
                                size: 15,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat('yyyy/MM/dd').format(entry.dueDate),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(
                            '${Money(entry.amountPiasters).toDisplay()} ج.م',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DataCell(
                          alloc.totalPaidPiasters <= 0
                              ? Text(
                                  '0.00 ج.م',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${Money(alloc.totalPaidPiasters).toDisplay()} ج.م',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: alloc.hasExcessCarryOver
                                            ? Colors.purple.shade700
                                            : AppColors.success,
                                      ),
                                    ),
                                    if (alloc.hasExcessCarryOver)
                                      Text(
                                        'منها زيادة مرحّلة: ${Money(alloc.paidFromExcessPiasters).toDisplay()} ج.م',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          color: Colors.purple.shade700,
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                        DataCell(
                          Text(
                            '${Money(isContractCompleted ? 0 : alloc.remainingPiasters).toDisplay()} ج.م',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color:
                                  (isContractCompleted ||
                                      alloc.remainingPiasters == 0)
                                  ? AppColors.success
                                  : AppColors.onSurface,
                            ),
                          ),
                        ),
                        DataCell(paidDateWidget),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 14, color: statusColor),
                                const SizedBox(width: 4),
                                Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
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
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppColors.success,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'سجل الدفعات والمتحصلات',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${payments.length} دفعات مسجلة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.bold,
                  ),
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
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: payments.length,
              separatorBuilder: (_, index) =>
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
              itemBuilder: (context, index) {
                final payment = payments[index];
                final dateStr = DateFormat(
                  'yyyy/MM/dd • HH:mm',
                ).format(payment.paidAt);
                final isDownPayment = payment.receiptNumber == 'DOWN_PAYMENT';
                final isWaiver =
                    payment.receiptNumber == 'INTEREST_WAIVER' ||
                    payment.paymentMethod == 'waiver';
                final isEarlySettlement =
                    payment.receiptNumber == 'EARLY_SETTLEMENT';
                final payMethodAr = isWaiver
                    ? 'إعفاء فائدة (لا يدخل الدرج)'
                    : payment.paymentMethod == 'cash'
                    ? 'نقدي'
                    : payment.paymentMethod == 'card'
                    ? 'بطاقة / فيزا'
                    : payment.paymentMethod;

                final Color iconBg = isWaiver
                    ? Colors.purple.shade50
                    : isEarlySettlement
                    ? Colors.teal.shade50
                    : isDownPayment
                    ? const Color(0xFFE0F2FE)
                    : const Color(0xFFDCFCE7);
                final Color iconColor = isWaiver
                    ? Colors.purple.shade700
                    : isEarlySettlement
                    ? Colors.teal.shade700
                    : isDownPayment
                    ? const Color(0xFF0369A1)
                    : AppColors.success;
                final IconData iconData = isWaiver
                    ? Icons.local_offer_rounded
                    : isEarlySettlement
                    ? Icons.bolt_rounded
                    : isDownPayment
                    ? Icons.account_balance_wallet_rounded
                    : Icons.check_circle_rounded;
                final String titleText = isWaiver
                    ? 'إعفاء فائدة سداد مبكر'
                    : isEarlySettlement
                    ? 'سداد مبكر / تسوية نهائية: ${Money(payment.amountPiasters).toDisplay()} ج.م'
                    : isDownPayment
                    ? 'دفعة مقدمة'
                    : 'دفعة قسط: ${Money(payment.amountPiasters).toDisplay()} ج.م';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(iconData, color: iconColor, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titleText,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.onSurface,
                              ),
                            ),
                            if (payment.notes != null &&
                                payment.notes!.trim().isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                payment.notes!,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 8,
                              children: [
                                Text(
                                  'الطريقة: $payMethodAr',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  '•',
                                  style: TextStyle(color: Colors.grey.shade400),
                                ),
                                Text(
                                  'بواسطة: ${payment.recordedBy}',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  '•',
                                  style: TextStyle(color: Colors.grey.shade400),
                                ),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: iconColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          isWaiver
                              ? '-${Money(payment.amountPiasters).toDisplay()} ج.م (إعفاء)'
                              : '${Money(payment.amountPiasters).toDisplay()} ج.م',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: iconColor,
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
        color = const Color(0xFF334155);
        bg = const Color(0xFFF1F5F9);
        label = 'عقد نشط';
        icon = Icons.verified_rounded;
        break;
      case 'overdue':
        color = AppColors.error;
        bg = const Color(0xFFFEF2F2);
        label = 'متأخر في السداد';
        icon = Icons.error_rounded;
        break;
      case 'legal_case':
        color = const Color(0xFFC2410C);
        bg = const Color(0xFFFFFBEB);
        label = 'إجراء قانوني (قضايا)';
        icon = Icons.gavel_rounded;
        break;
      case 'completed':
        color = AppColors.success;
        bg = const Color(0xFFECFDF5);
        label = 'عقد مكتمل';
        icon = Icons.task_alt_rounded;
        break;
      case 'written_off':
      case 'cancelled_bad_debt':
        color = AppColors.error;
        bg = const Color(0xFFFEF2F2);
        label = 'دين معدوم (تهرب)';
        icon = Icons.cancel_rounded;
        break;
      case 'cancelled':
        color = Colors.grey.shade700;
        bg = const Color(0xFFF1F5F9);
        label = 'عقد ملغي';
        icon = Icons.block_rounded;
        break;
      default:
        color = Colors.grey.shade700;
        bg = const Color(0xFFF1F5F9);
        label = status;
        icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromissoryNoteBanner(
    BuildContext context,
    InstallmentDetailCubit cubit,
    CustomerInstallmentEntity contract,
  ) {
    if (!contract.hasPromissoryNote) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.do_not_disturb_on_outlined,
              color: AppColors.onSurfaceVariant,
              size: 18,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'لا يوجد إيصال / وصل أمانة مسجل لهذا العقد',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (contract.promissoryNoteDelivered) {
      final deliveredDate = contract.promissoryNoteDeliveredAt != null
          ? DateFormat('yyyy/MM/dd').format(contract.promissoryNoteDeliveredAt!)
          : null;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_rounded,
              color: AppColors.success,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                deliveredDate != null
                    ? 'تم تسليم وصل الأمانة للعميل بتاريخ $deliveredDate'
                    : 'تم تسليم وصل الأمانة للعميل',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            color: AppColors.onSurfaceVariant,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'وصل الأمانة في الخزينة (لم يُسلَّم للعميل بعد)',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ),
          InkWell(
            onTap: () => _confirmDeliverPromissoryNote(context, cubit),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_rounded,
                    color: AppColors.onSurface,
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'تسليم الوصل للعميل',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeliverPromissoryNote(
    BuildContext context,
    InstallmentDetailCubit cubit,
  ) async {
    final result = await showPromissoryNoteDeliveryDialog(
      context,
      customerName: cubit.state.customerName,
    );

    if (result != null && context.mounted) {
      final success = await cubit.markPromissoryNoteDelivered(
        result != PromissoryNoteDeliveryResult.inSafe,
        hasNote: result != PromissoryNoteDeliveryResult.noReceipt,
      );
      if (success && context.mounted) {
        final message = result == PromissoryNoteDeliveryResult.noReceipt
            ? 'تم توثيق: لا يوجد إيصال أمانة لهذا العميل'
            : result == PromissoryNoteDeliveryResult.delivered
            ? 'تم توثيق تسليم وصل الأمانة للعميل بنجاح'
            : 'تم الإبقاء على وصل الأمانة في الخزينة';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: result == PromissoryNoteDeliveryResult.inSafe
                ? Colors.blueGrey
                : Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _confirmToggleLegalCase(
    BuildContext context,
    InstallmentDetailCubit cubit,
    bool isLegalCase,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              isLegalCase ? Icons.gavel_rounded : Icons.undo_rounded,
              color: isLegalCase ? Colors.amber.shade800 : AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              isLegalCase
                  ? 'تحويل العقد لإجراء قانوني'
                  : 'إلغاء الإجراء القانوني',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          isLegalCase
              ? 'هل أنت متأكد من تحويل هذا العقد إلى "إجراء قانوني"؟\nسيتم نقله من قائمة المتأخرات العادية إلى قسم الإجراءات القانونية.'
              : 'هل تريد إعادة العقد إلى الحالة النشطة الطبيعية؟',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isLegalCase
                  ? Colors.amber.shade800
                  : AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(isLegalCase ? 'تأكيد التحويل' : 'تأكيد الإعادة'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await cubit.updateLegalStatus(isLegalCase);
      if (!context.mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isLegalCase
                  ? 'تم تحويل العقد للإجراءات القانونية بنجاح'
                  : 'تمت إعادة العقد للحالة النشطة بنجاح',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cubit.state.errorMessage ??
                  'تعذر تغيير حالة العقد، يرجى المحاولة ثانية',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _openJudicialSettlementDialog(
    BuildContext context,
    InstallmentDetailCubit cubit,
    InstallmentDetailState state,
    CustomerInstallmentEntity contract,
  ) async {
    final featureGate = getIt<FeatureGate>();
    final isPinRequired = getIt.isRegistered<ManagerPinService>()
        ? await getIt<ManagerPinService>().isPinRequired()
        : (await featureGate.getMeta('installments.pin.require')) != '0';

    final remainingPounds = (contract.remainingPiasters / 100).toStringAsFixed(2);
    final amountCtrl = TextEditingController(text: remainingPounds);
    final notesCtrl = TextEditingController(text: 'تحصيل وتسوية قضائية (تم التخليص بالقسم/المحكمة)');
    final pinCtrl = TextEditingController();
    String paymentMethod = 'cash';

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.gavel_rounded, color: AppColors.success, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'تحصيل وتسوية قضائية (تم التخليص)',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'العميل: ${state.customerName ?? "—"}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إجمالي المتبقي بالقضية: ${Money(contract.remainingPiasters).toDisplay()} ج.م',
                          style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ المحصل فعلياً (ج.م) *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payments_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('طريقة التحصيل:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('نقدي (خزينة المحل)'),
                        selected: paymentMethod == 'cash',
                        onSelected: (val) {
                          if (val) setDialogState(() => paymentMethod = 'cash');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('بطاقة / تحويل بنكي'),
                        selected: paymentMethod == 'card',
                        onSelected: (val) {
                          if (val) setDialogState(() => paymentMethod = 'card');
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات محضر الصلح / القضية',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  if (isPinRequired) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: pinCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'الرقم السري للمدير *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_rounded),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: const Text('إثبات التحصيل والتسوية', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                final text = amountCtrl.text.trim();
                final val = double.tryParse(text);
                if (val == null || val < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')),
                  );
                  return;
                }
                Navigator.of(dialogCtx).pop(true);
              },
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      final collectedPounds = double.tryParse(amountCtrl.text.trim()) ?? 0;
      final collectedPiasters = (collectedPounds * 100).round();
      final waivedPiasters = (contract.remainingPiasters - collectedPiasters).clamp(0, contract.remainingPiasters);

      final ok = await cubit.settleEarly(
        waivedInterestPiasters: waivedPiasters,
        paymentMethod: paymentMethod,
        pin: pinCtrl.text.trim(),
        notes: notesCtrl.text.trim(),
        settledAt: DateTime.now(),
      );

      if (ok && context.mounted) {
        final result = await showPromissoryNoteDeliveryDialog(
          context,
          customerName: state.customerName,
        );
        if (result != null && context.mounted) {
          await cubit.markPromissoryNoteDelivered(
            result != PromissoryNoteDeliveryResult.inSafe,
            hasNote: result != PromissoryNoteDeliveryResult.noReceipt,
          );
        }

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Text(
              'تم إثبات التحصيل والتسوية القضائية وإقفال العقد بنجاح — محصل: ${Money(collectedPiasters).toDisplay()} ج.م',
            ),
          ),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text(cubit.state.errorMessage ?? 'تعذر إتمام التسوية القضائية'),
          ),
        );
      }
    }
  }

  Future<void> _confirmBadDebtWriteOff(
    BuildContext context,
    InstallmentDetailCubit cubit,
    CustomerInstallmentEntity contract,
  ) async {
    final featureGate = getIt<FeatureGate>();
    final isAdmin = await featureGate.isCurrentUserAdmin();
    if (!context.mounted) return;

    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('غير مصرح: إعدام الديون متاح للمدير فقط'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final isPinRequired = getIt.isRegistered<ManagerPinService>()
        ? await getIt<ManagerPinService>().isPinRequired()
        : (await featureGate.getMeta('installments.pin.require')) != '0';

    final reasonCtrl = TextEditingController(text: 'تهرب من السداد / تعذر التحصيل القضائي');
    final pinCtrl = TextEditingController();

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.block_rounded, color: AppColors.error, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'إثبات تهرب / إعدام دين العقد',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تحذير هام:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.error),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• سيتم إعدام الرصيد المتبقي (${Money(contract.remainingPiasters).toDisplay()} ج.م) كخسارة.\n'
                      '• سيتم إدراج العميل تلقائياً في "القائمة المحظورة" في النظام.\n'
                      '• تُقفل حالة العقد نهائياً كـ "دين معدوم (تهرب)".',
                      style: const TextStyle(fontSize: 12.5, height: 1.5, color: Color(0xFF7F1D1D)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'سبب إعدام الدين *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.report_problem_outlined),
                ),
              ),
              if (isPinRequired) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'الرقم السري للمدير *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_rounded),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('تراجع'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('تأكيد إعدام الدين والحظر', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await cubit.writeOffBadDebt(
        reason: reasonCtrl.text.trim(),
        pin: pinCtrl.text.trim(),
      );
      if (!context.mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إثبات التهرب وإعدام الدين وإدراج العميل في القائمة المحظورة'),
            backgroundColor: AppColors.error,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cubit.state.errorMessage ?? 'تعذر إتمام عملية إعدام الدين'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
