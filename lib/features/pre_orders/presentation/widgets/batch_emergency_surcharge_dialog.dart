import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/data/services/customer_ledger_service.dart';
import '../../domain/entities/pre_order_batch_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class BatchEmergencySurchargeDialog extends StatefulWidget {
  final PreOrderBatchEntity batch;

  const BatchEmergencySurchargeDialog({super.key, required this.batch});

  static Future<void> show(BuildContext context, PreOrderBatchEntity batch) {
    return showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<PreOrdersCubit>(),
        child: BatchEmergencySurchargeDialog(batch: batch),
      ),
    );
  }

  @override
  State<BatchEmergencySurchargeDialog> createState() =>
      _BatchEmergencySurchargeDialogState();
}

class _BatchEmergencySurchargeDialogState
    extends State<BatchEmergencySurchargeDialog> {
  final _amountCtrl = TextEditingController();
  String _handledBy = 'customers'; // 'customers' أو 'merchant'
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.batch.emergencyIncreasePiasters > 0) {
      _amountCtrl.text = (widget.batch.emergencyIncreasePiasters / 100)
          .toStringAsFixed(1)
          .replaceAll('.0', '');
      _handledBy = widget.batch.emergencyIncreaseHandledBy;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  int get _surchargePiasters {
    final v = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    return (v * 100).round();
  }

  int get _totalActivePieces => widget.batch.orders.fold(
    0,
    (sum, o) =>
        sum +
        o.items.where((it) => it.isActive).fold(0, (s, it) => s + it.quantity),
  );

  double get _surchargePerPiece {
    final total = _surchargePiasters;
    final pieces = _totalActivePieces;
    if (pieces <= 0 || total <= 0) return 0.0;
    return (total / 100.0) / pieces;
  }

  Future<void> _sendWhatsAppToCustomer(
    BuildContext context,
    String phone,
    String customerName,
    int extraPiasters,
    int remainingPiasters,
  ) async {
    final message =
        'مرحباً $customerName،\nنود إحاطتكم بأنه نظراً لفرق سعر الصرف والجمارك الطارئ المفروض على الشحنة [${widget.batch.batchNumber}]، تم تطبيق زيادة قدرها [${Money(extraPiasters).toDisplay()} ج.م] على طلبكم.\nالمتبقي الجديد للاستلام: [${Money(remainingPiasters).toDisplay()} ج.م].\nشاكرين جداً تفهمكم ونسعد بخدمتكم دائماً!';

    final baseUri = CustomerLedgerService.buildWhatsAppUri(phone);
    if (baseUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم الهاتف غير صالح لمحادثة واتساب'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final fullUri = Uri.parse(
      '${baseUri.toString()}?text=${Uri.encodeComponent(message)}',
    );
    try {
      await launchUrl(fullUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح تطبيق واتساب'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      final cubit = context.read<PreOrdersCubit>();
      final ok = await cubit.applyBatchEmergencyIncrease(
        widget.batch.id,
        _surchargePiasters,
        _handledBy,
      );
      if (ok && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _handledBy == 'customers'
                  ? 'تم توزيع الزيادة على العملاء وتحديث المتبقي بنجاح'
                  : 'تم اعتماد تحمل التاجر للزيادة وخصمها من صافي أرباح الشحنة',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surchargeP = _surchargePiasters;
    final perPiece = _surchargePerPiece;
    final piecesCount = _totalActivePieces;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.currency_exchange_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تطبيق فرق سعر الصرف أو زيادة طارئة (${widget.batch.batchNumber})',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const Text(
                          'معالجة الارتفاع الطارئ في العملة أو الجمارك بمرونة تامة',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 20, color: AppColors.outlineVariant),

              // Inputs
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إجمالي مبلغ الزيادة الطارئة على الشحنة بالكامل (ج.م):',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'مثال: 300',
                          prefixIcon: const Icon(
                            Icons.add_shopping_cart_rounded,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),

                      const Text(
                        'من يتحمل هذه الزيادة؟',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Option A: Customers
                      InkWell(
                        onTap: () => setState(() => _handledBy = 'customers'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _handledBy == 'customers'
                                  ? AppColors.primary
                                  : AppColors.outlineVariant,
                              width: _handledBy == 'customers' ? 1.5 : 1.0,
                            ),
                            color: _handledBy == 'customers'
                                ? AppColors.primary.withValues(alpha: 0.04)
                                : Colors.white,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _handledBy == 'customers'
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: _handledBy == 'customers'
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'توزيع الزيادة على العملاء (حسب عدد القطع)',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      piecesCount > 0
                                          ? 'سيتم إضافة ${perPiece.toStringAsFixed(1)} ج.م لكل قطعة على حساب العميل'
                                          : 'توزيع الزيادة تلقائياً على كل صنف نشط في الشحنة',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Option B: Merchant absorbs
                      InkWell(
                        onTap: () => setState(() => _handledBy = 'merchant'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _handledBy == 'merchant'
                                  ? AppColors.primary
                                  : AppColors.outlineVariant,
                              width: _handledBy == 'merchant' ? 1.5 : 1.0,
                            ),
                            color: _handledBy == 'merchant'
                                ? AppColors.primary.withValues(alpha: 0.04)
                                : Colors.white,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _handledBy == 'merchant'
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: _handledBy == 'merchant'
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'تحمل التاجر للزيادة بالكامل (خصم من الأرباح)',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      'تبقى حسابات ومتبقي العملاء ثابتة كما هي، ويتم خصم الزيادة من صافي أرباح الشحنة',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (_handledBy == 'customers' && surchargeP > 0) ...[
                        const SizedBox(height: 16),
                        const Divider(
                          height: 1,
                          color: AppColors.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'إشعار العملاء بالزيادة والمتبقي الجديد (واتساب):',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...widget.batch.orders.map((o) {
                          final oPieces = o.items
                              .where((it) => it.isActive)
                              .fold(0, (s, it) => s + it.quantity);
                          final extra = piecesCount > 0
                              ? ((surchargeP * oPieces) / piecesCount).round()
                              : 0;
                          final newRemaining =
                              o.remainingWithShippingPiasters + extra;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        o.customerName,
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'القطع: $oPieces | الزيادة: +${Money(extra).toDisplay()} ج | المتبقي الجديد: ${Money(newRemaining).toDisplay()} ج',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10.5,
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.chat_rounded,
                                    color: Color(0xFF25D366),
                                    size: 18,
                                  ),
                                  tooltip: 'إرسال رسالة واتساب توضيحية للعميل',
                                  onPressed: () => _sendWhatsAppToCustomer(
                                    context,
                                    o.customerPhone,
                                    o.customerName,
                                    extra,
                                    newRemaining,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1, color: AppColors.outlineVariant),
              const SizedBox(height: 12),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text(
                      'حفظ واعتماد الزيادة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
