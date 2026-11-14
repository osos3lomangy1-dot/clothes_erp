import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'تفاصيل عقد التقسيط',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            tooltip: 'تحديث',
            onPressed: () => cubit.refresh(),
          ),
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
                  Text('خطأ: ${state.errorMessage ?? "تعذر تحميل تفاصيل العقد"}'),
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Card
                _buildHeaderCard(context, contract, state.customerName, computedStatus),
                const SizedBox(height: 16),

                // Actions Bar
                _buildActionsBar(context, cubit, contract, canPay),
                const SizedBox(height: 20),

                // Schedule Table Section
                _buildScheduleSection(context, state.schedule, state.payments, contract),
                const SizedBox(height: 20),

                // Payments Log Section
                _buildPaymentsLogSection(context, state.payments),
              ],
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
  ) {
    final displayName = customerName ?? 'عميل #${contract.customerId.substring(0, 8)}';
    final startStr = DateFormat('yyyy/MM/dd').format(contract.startDate);
    final endStr = DateFormat('yyyy/MM/dd').format(contract.endDate);
    final paidPiasters = contract.totalPiasters - contract.remainingPiasters;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
              _buildBadge(computedStatus),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatItem('إجمالي العقد', '${Money(contract.totalPiasters).toDisplay()} ج.م'),
              _buildStatItem('الدفعة المقدمة', '${Money(contract.downPaymentPiasters).toDisplay()} ج.م'),
              _buildStatItem('المدفوع حتى الآن', '${Money(paidPiasters).toDisplay()} ج.م'),
              _buildStatItem('المتبقي', '${Money(contract.remainingPiasters).toDisplay()} ج.م', isPrimary: true),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatItem('تاريخ البدء', startStr),
              _buildStatItem('تاريخ الاستحقاق', endStr),
              _buildStatItem('المدة', '${contract.durationMonths} شهور'),
              _buildStatItem('القسط الشهري التقديري', '${Money(contract.monthlyAmountPiasters).toDisplay()} ج.م'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {bool isPrimary = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isPrimary ? AppColors.primary : AppColors.onSurface,
            ),
          ),
        ],
      ),
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
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.payment_rounded),
              label: const Text('تسجيل دفعة جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecordPaymentScreen(contractId: contract.id),
                  ),
                ).then((_) => cubit.refresh());
              },
            ),
          ),
        if (canPay) const SizedBox(width: 12),
        if (contract.status != 'cancelled' && contract.status != 'completed')
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('إلغاء العقد'),
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
        title: const Text('تأكيد إلغاء العقد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('هل أنت متأكد من رغبتك في إلغاء هذا العقد؟ لن يمكن تسجيل دفعات جديدة عليه بعد الإلغاء.'),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'الرقم السري للمدير (PIN)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('رجوع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
            child: const Text('تأكيد الإلغاء'),
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
    // Total payments excluding down payment (or cumulative paid piasters)
    final totalPaidPiasters = contract.totalPiasters - contract.remainingPiasters - contract.downPaymentPiasters;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'جدول الأقساط والاستحقاقات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          if (schedule.isEmpty)
            const Text('لا يوجد جدول متاح لهذا العقد')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('تاريخ الاستحقاق')),
                  DataColumn(label: Text('المبلغ')),
                  DataColumn(label: Text('أصل المبلغ')),
                  DataColumn(label: Text('الفائدة')),
                  DataColumn(label: Text('الحالة')),
                ],
                rows: schedule.map((entry) {
                  // Determine status for this installment based on cumulative payments
                  final now = DateTime.now();
                  final dueDate = entry.dueDate;
                  // If entry index cumulative amount <= totalPaidPiasters -> Paid
                  final isPaid = (entry.installmentNumber * entry.amountPiasters) <= totalPaidPiasters;
                  final isOverdue = !isPaid && now.isAfter(dueDate);

                  final statusLabel = isPaid
                      ? 'مدفوع'
                      : isOverdue
                          ? 'متأخر'
                          : 'مستحق';
                  final statusColor = isPaid
                      ? Colors.green
                      : isOverdue
                          ? Colors.red
                          : Colors.orange;

                  return DataRow(cells: [
                    DataCell(Text('${entry.installmentNumber}')),
                    DataCell(Text(DateFormat('yyyy/MM/dd').format(dueDate))),
                    DataCell(Text('${Money(entry.amountPiasters).toDisplay()} ج.م')),
                    DataCell(Text('${Money(entry.principalComponentPiasters).toDisplay()} ج.م')),
                    DataCell(Text('${Money(entry.interestComponentPiasters).toDisplay()} ج.م')),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                  ]);
                }).toList(),
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
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'سجل الدفعات والمتحصلات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '${payments.length} دفعات مسجلة',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (payments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('لم يتم تسجيل أي دفعات حتى الآن', style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: payments.length,
              separatorBuilder: (_, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final payment = payments[index];
                final dateStr = DateFormat('yyyy/MM/dd • HH:mm').format(payment.paidAt);
                final isDownPayment = payment.receiptNumber == 'DOWN_PAYMENT';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDownPayment ? Colors.blue.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isDownPayment ? Icons.account_balance_wallet_rounded : Icons.check_circle_outline_rounded,
                      color: isDownPayment ? Colors.blue.shade800 : Colors.green.shade800,
                    ),
                  ),
                  title: Text(
                    isDownPayment ? 'دفعة مقدمة' : 'دفعة قسط: ${Money(payment.amountPiasters).toDisplay()} ج.م',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'طريقة الدفع: ${payment.paymentMethod} • بواسطة: ${payment.recordedBy} • $dateStr',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  trailing: Text(
                    '${Money(payment.amountPiasters).toDisplay()} ج.م',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDownPayment ? Colors.blue.shade800 : Colors.green.shade800,
                    ),
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

    switch (status) {
      case 'active':
        color = Colors.blue.shade800;
        bg = Colors.blue.shade50;
        label = 'عقد نشط';
        break;
      case 'overdue':
        color = Colors.red.shade800;
        bg = Colors.red.shade50;
        label = 'متأخر في السداد';
        break;
      case 'completed':
        color = Colors.green.shade800;
        bg = Colors.green.shade50;
        label = 'عقد مكتمل';
        break;
      case 'cancelled':
        color = Colors.grey.shade800;
        bg = Colors.grey.shade200;
        label = 'عقد ملغي';
        break;
      default:
        color = Colors.grey.shade700;
        bg = Colors.grey.shade100;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

