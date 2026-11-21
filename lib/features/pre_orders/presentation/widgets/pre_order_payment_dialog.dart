import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class PreOrderPaymentDialog extends StatefulWidget {
  final PreOrderEntity order;

  const PreOrderPaymentDialog({super.key, required this.order});

  @override
  State<PreOrderPaymentDialog> createState() => _PreOrderPaymentDialogState();
}

class _PreOrderPaymentDialogState extends State<PreOrderPaymentDialog> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _paymentMethod = 'cash'; // 'cash', 'instapay', 'vodafone_cash', 'card'

  @override
  void initState() {
    super.initState();
    final remainingEgp = widget.order.remainingPiasters / 100.0;
    _amountCtrl.text = remainingEgp > 0 ? remainingEgp.toStringAsFixed(2) : '0.00';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainingPiasters = widget.order.remainingPiasters;

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.add_card_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تسجيل دفعة لحجز #${widget.order.orderNumber}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'العميل: ${widget.order.customerName}',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Remaining banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'المتبقي على الحجز:',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    '${Money(remainingPiasters).toDisplay()} ج.م',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Amount field
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
              decoration: InputDecoration(
                labelText: 'مبلغ الدفعة (ج.م) *',
                prefixIcon: Icon(Icons.payments_outlined, color: AppColors.primary),
                suffixText: 'ج.م',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),

            // Payment method dropdown
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: InputDecoration(
                labelText: 'طريقة الدفع',
                prefixIcon: Icon(Icons.payment_rounded, color: AppColors.primary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('كاش (نقداً)')),
                DropdownMenuItem(value: 'instapay', child: Text('انستاباي (InstaPay)')),
                DropdownMenuItem(value: 'vodafone_cash', child: Text('فودافون كاش / محفظة إلكترونية')),
                DropdownMenuItem(value: 'card', child: Text('فيزا / بطاقة بنكية')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _paymentMethod = val);
              },
            ),
            const SizedBox(height: 12),

            // Notes field
            TextField(
              controller: _notesCtrl,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'ملاحظات (رقم العملية أو المرجع)',
                hintText: 'مثال: تحويل انستاباي رقم 4920492',
                prefixIcon: Icon(Icons.notes_rounded, color: AppColors.primary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () async {
            final amtNum = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
            final piasters = (amtNum * 100).round();
            if (piasters <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('يرجى إدخال مبلغ صحيح أكبر من صفر'),
                  backgroundColor: AppColors.error,
                ),
              );
              return;
            }

            final cubit = context.read<PreOrdersCubit>();
            final ok = await cubit.addPayment(
              widget.order.id,
              piasters,
              paymentMethod: _paymentMethod,
              notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
            );

            if (ok && context.mounted) {
              Navigator.of(context).pop(true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'تم تسجيل الدفعة بنجاح بقيمة ${Money(piasters).toDisplay()} ج.م',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: AppColors.success,
                ),
              );
            }
          },
          child: const Text(
            'حفظ الدفعة',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
