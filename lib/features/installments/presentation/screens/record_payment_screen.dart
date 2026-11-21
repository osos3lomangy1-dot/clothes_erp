import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../domain/facades/installments_facade.dart';
import '../cubits/record_payment_cubit.dart';
import '../widgets/promissory_note_delivery_dialog.dart';

/// Opens a polished modal dialog to record an installment payment while
/// keeping the customer's schedule visible in the background.
Future<bool?> showRecordPaymentDialog(
  BuildContext context, {
  required String contractId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider(
      create: (_) => RecordPaymentCubit(
        contractId: contractId,
        facade: getIt<InstallmentsFacade>(),
        featureGate: getIt<FeatureGate>(),
      ),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        backgroundColor: AppColors.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 740),
          child: const _RecordPaymentView(isDialog: true),
        ),
      ),
    ),
  );
}

class RecordPaymentScreen extends StatelessWidget {
  final String contractId;

  const RecordPaymentScreen({super.key, required this.contractId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => RecordPaymentCubit(
        contractId: contractId,
        facade: getIt<InstallmentsFacade>(),
        featureGate: getIt<FeatureGate>(),
      ),
      child: const _RecordPaymentView(isDialog: false),
    );
  }
}

class _RecordPaymentView extends StatefulWidget {
  final bool isDialog;

  const _RecordPaymentView({this.isDialog = false});

  @override
  State<_RecordPaymentView> createState() => _RecordPaymentViewState();
}

class _RecordPaymentViewState extends State<_RecordPaymentView> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _pinController = TextEditingController();
  final _receiptController = TextEditingController();
  String _paymentMethod = 'cash';
  DateTime _paymentDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _guardFeature();
    _amountController.addListener(() => setState(() {}));
  }

  Future<void> _pickPaymentDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      setState(() {
        _paymentDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          now.hour,
          now.minute,
          now.second,
        );
      });
    }
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
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _pinController.dispose();
    _receiptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<RecordPaymentCubit>();

    final bodyContent = BlocConsumer<RecordPaymentCubit, RecordPaymentState>(
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
        if (state.status == RecordPaymentStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.status == RecordPaymentStatus.error) {
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
                Text('خطأ: ${state.errorMessage ?? "تعذر تحميل بيانات العقد"}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => cubit.load(),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }

        final remainingDisplay = Money(state.remainingPiasters).toDisplay();
        final currentDueAmountPiasters =
            state.nextInstallmentRemainingPiasters > 0
            ? state.nextInstallmentRemainingPiasters
            : state.monthlyAmountPiasters;
        final monthlyDisplay = Money(currentDueAmountPiasters).toDisplay();
        final enteredDouble =
            double.tryParse(_amountController.text.trim()) ?? 0;
        final enteredPiasters = (enteredDouble * 100).round();
        final excessPiasters =
            (enteredPiasters > currentDueAmountPiasters &&
                enteredPiasters <= state.remainingPiasters)
            ? (enteredPiasters - currentDueAmountPiasters)
            : 0;

        final paidDay = DateTime(
          _paymentDate.year,
          _paymentDate.month,
          _paymentDate.day,
        );
        String? timingBadgeText;
        Color timingBadgeColor = AppColors.success;
        if (state.nextDueDate != null) {
          final dueDay = DateTime(
            state.nextDueDate!.year,
            state.nextDueDate!.month,
            state.nextDueDate!.day,
          );
          final diff = paidDay.difference(dueDay).inDays;
          if (diff < 0) {
            timingBadgeText = 'قبل الموعد بـ ${diff.abs()} يوم';
            timingBadgeColor = Colors.teal.shade700;
          } else if (diff == 0) {
            timingBadgeText = 'في موعد الاستحقاق';
            timingBadgeColor = AppColors.success;
          } else {
            timingBadgeText = 'بعد الموعد بـ $diff يوم';
            timingBadgeColor = AppColors.error;
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'الرصيد المتبقي على العقد',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$remainingDisplay ج.م',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              state.nextInstallmentNumber != null
                                  ? 'المستحق للقسط #${state.nextInstallmentNumber}'
                                  : 'قيمة القسط الشهري',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$monthlyDisplay ج.م',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (state.nextDueDate != null) ...[
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.event_note_rounded,
                                size: 16,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'تاريخ استحقاق القسط القادم:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            DateFormat('yyyy/MM/dd').format(state.nextDueDate!),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Amount Input
              Container(
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
                      'تفاصيل الدفعة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Payment Date Row (recorded whether early or late)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'تاريخ السداد الفعلي (يُسجَّل تلقائياً)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      DateFormat(
                                        'yyyy/MM/dd',
                                      ).format(_paymentDate),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (timingBadgeText != null) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: timingBadgeColor.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          timingBadgeText,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: timingBadgeColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _pickPaymentDate,
                            icon: const Icon(
                              Icons.edit_calendar_rounded,
                              size: 16,
                            ),
                            label: const Text('تغيير'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'المبلغ المدفوع (ج.م) *',
                        hintText: monthlyDisplay,
                        border: const OutlineInputBorder(),
                        suffixText: 'ج.م',
                      ),
                    ),
                    if (excessPiasters > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.purple.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.fast_rewind_rounded,
                              color: Colors.purple.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'سيتم سداد القسط الحالي (${Money(currentDueAmountPiasters).toDisplay()} ج.م) وترحيل الزيادة (${Money(excessPiasters).toDisplay()} ج.م) لآخر قسط تلقائياً.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.purple.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () =>
                              _amountController.text = monthlyDisplay,
                          child: const Text('دفع القسط الحالي'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () =>
                              _amountController.text = remainingDisplay,
                          child: const Text('سداد كامل المبلغ'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Payment Method
                    const Text(
                      'طريقة الدفع',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('نقدي (كاش)')),
                            selected: _paymentMethod == 'cash',
                            onSelected: (val) {
                              if (val) setState(() => _paymentMethod = 'cash');
                            },
                            selectedColor: AppColors.primary.withValues(
                              alpha: 0.15,
                            ),
                            checkmarkColor: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('بطاقة / بنكي')),
                            selected: _paymentMethod == 'card',
                            onSelected: (val) {
                              if (val) setState(() => _paymentMethod = 'card');
                            },
                            selectedColor: AppColors.primary.withValues(
                              alpha: 0.15,
                            ),
                            checkmarkColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Receipt Number (optional)
                    TextField(
                      controller: _receiptController,
                      decoration: const InputDecoration(
                        labelText: 'رقم الإيصال / السند (اختياري)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Notes (optional)
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات إضافية (اختياري)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Manager PIN (hidden completely when disabled in settings)
                    if (state.isPinRequired) ...[
                      TextField(
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الرقم السري للمدير (PIN) *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ] else
                      const SizedBox(height: 8),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: state.isSubmitting
                            ? null
                            : () => _handleSubmit(context, cubit, state),
                        child: state.isSubmitting
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'تأكيد تسجيل الدفعة',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (widget.isDialog) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.payment_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'تسجيل دفعة قسط',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
          Flexible(child: bodyContent),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.onSurface,
          ),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'تسجيل دفعة قسط',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.onSurface,
          ),
        ),
      ),
      body: bodyContent,
    );
  }

  void _handleSubmit(
    BuildContext context,
    RecordPaymentCubit cubit,
    RecordPaymentState state,
  ) async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال المبلغ المدفوع')),
      );
      return;
    }

    final amountEgp = double.tryParse(amountText);
    if (amountEgp == null || amountEgp <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال مبلغ صحيح أكبر من صفر')),
      );
      return;
    }

    final amountPiasters = (amountEgp * 100).round();
    if (amountPiasters > state.remainingPiasters) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('المبلغ المدخل يتجاوز الرصيد المتبقي على العقد'),
        ),
      );
      return;
    }

    final pin = _pinController.text.trim();
    if (state.isPinRequired && pin.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرقم السري للمدير مطلوب لإتمام الدفعة')),
      );
      return;
    }

    final isFullSettlement = (amountPiasters >= state.remainingPiasters);
    final success = await cubit.submit(
      amountPiasters: amountPiasters,
      paymentMethod: _paymentMethod,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      pin: pin,
      receiptNumber: _receiptController.text.trim().isEmpty
          ? null
          : _receiptController.text.trim(),
      paidAt: _paymentDate,
    );

    if (success && context.mounted) {
      if (isFullSettlement) {
        final result = await showPromissoryNoteDeliveryDialog(context);
        if (result != null && context.mounted) {
          await getIt<InstallmentsFacade>().markPromissoryNoteDelivered(
            contractId: cubit.contractId,
            delivered: result != PromissoryNoteDeliveryResult.inSafe,
            deliveredAt: result == PromissoryNoteDeliveryResult.delivered ? DateTime.now() : null,
            hasNote: result != PromissoryNoteDeliveryResult.noReceipt,
          );
        }
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل الدفعة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    }
  }
}
