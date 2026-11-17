import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../domain/facades/installments_facade.dart';
import '../cubits/record_payment_cubit.dart';

class RecordPaymentScreen extends StatelessWidget {
  final String contractId;

  const RecordPaymentScreen({
    super.key,
    required this.contractId,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => RecordPaymentCubit(
        contractId: contractId,
        facade: getIt<InstallmentsFacade>(),
        featureGate: getIt<FeatureGate>(),
      ),
      child: const _RecordPaymentView(),
    );
  }
}

class _RecordPaymentView extends StatefulWidget {
  const _RecordPaymentView();

  @override
  State<_RecordPaymentView> createState() => _RecordPaymentViewState();
}

class _RecordPaymentViewState extends State<_RecordPaymentView> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  final _pinController = TextEditingController();
  final _receiptController = TextEditingController();
  String _paymentMethod = 'cash';

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
          'تسجيل دفعة قسط',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
        ),
      ),
      body: BlocConsumer<RecordPaymentCubit, RecordPaymentState>(
        listener: (context, state) {
          if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!), backgroundColor: Colors.red),
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
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text('خطأ: ${state.errorMessage ?? "تعذر تحميل بيانات العقد"}'),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => cubit.load(), child: const Text('إعادة المحاولة')),
                ],
              ),
            );
          }

          final remainingDisplay = Money(state.remainingPiasters).toDisplay();
          final monthlyDisplay = Money(state.monthlyAmountPiasters).toDisplay();

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
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('الرصيد المتبقي على العقد', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(
                            '$remainingDisplay ج.م',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('قيمة القسط الشهري', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(
                            '$monthlyDisplay ج.م',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
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
                      const Text('تفاصيل الدفعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'المبلغ المدفوع (ج.م) *',
                          hintText: monthlyDisplay,
                          border: const OutlineInputBorder(),
                          suffixText: 'ج.م',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _amountController.text = monthlyDisplay,
                            child: const Text('دفع قسط واحد'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _amountController.text = remainingDisplay,
                            child: const Text('سداد كامل المبلغ'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Payment Method
                      const Text('طريقة الدفع', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                              selectedColor: AppColors.primary.withValues(alpha: 0.15),
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
                              selectedColor: AppColors.primary.withValues(alpha: 0.15),
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

                      // Manager PIN
                      TextField(
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: state.isPinRequired
                              ? 'الرقم السري للمدير (PIN) *'
                              : 'الرقم السري للمدير (اختياري)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: state.isSubmitting
                              ? null
                              : () => _handleSubmit(context, cubit, state),
                          child: state.isSubmitting
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('تأكيد تسجيل الدفعة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
        const SnackBar(content: Text('المبلغ المدخل يتجاوز الرصيد المتبقي على العقد')),
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

    final success = await cubit.submit(
      amountPiasters: amountPiasters,
      paymentMethod: _paymentMethod,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      pin: pin,
      receiptNumber: _receiptController.text.trim().isEmpty ? null : _receiptController.text.trim(),
    );

    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الدفعة بنجاح'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop(true);
    }
  }
}
