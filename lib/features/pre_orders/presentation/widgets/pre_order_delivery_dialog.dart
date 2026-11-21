import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class PreOrderDeliveryDialog extends StatefulWidget {
  final PreOrderEntity order;

  const PreOrderDeliveryDialog({super.key, required this.order});

  @override
  State<PreOrderDeliveryDialog> createState() => _PreOrderDeliveryDialogState();
}

class _PreOrderDeliveryDialogState extends State<PreOrderDeliveryDialog> {
  late final TextEditingController _finalPaymentCtrl;
  String _paymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    final rem = widget.order.remainingPiasters / 100.0;
    _finalPaymentCtrl = TextEditingController(
      text: rem > 0 ? rem.toStringAsFixed(2) : '0.00',
    );
  }

  @override
  void dispose() {
    _finalPaymentCtrl.dispose();
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
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'تسليم أوردر الحجز #${widget.order.orderNumber}',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'تأكيد تسليم الأصناف للعميل: ${widget.order.customerName}',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                children: [
                  _row('إجمالي الأوردر:', '${Money(widget.order.totalPiasters).toDisplay()} ج.م', false),
                  const SizedBox(height: 4),
                  _row('العربون المسدد سابقاً:', '${Money(widget.order.depositPiasters).toDisplay()} ج.م', false),
                  const Divider(height: 14),
                  _row(
                    'المتبقي المطلوب تحصيله الآن:',
                    '${Money(remainingPiasters).toDisplay()} ج.م',
                    true,
                  ),
                ],
              ),
            ),

            if (remainingPiasters > 0) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _finalPaymentCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
                decoration: InputDecoration(
                  labelText: 'المبلغ المحصل عند التسليم (ج.م) *',
                  prefixIcon: Icon(Icons.payments_outlined, color: AppColors.primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: InputDecoration(
                  labelText: 'طريقة دفع المتبقي',
                  prefixIcon: Icon(Icons.payment_rounded, color: AppColors.primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('كاش (نقداً)')),
                  DropdownMenuItem(value: 'instapay', child: Text('انستاباي (InstaPay)')),
                  DropdownMenuItem(value: 'vodafone_cash', child: Text('فودافون كاش / محفظة')),
                  DropdownMenuItem(value: 'card', child: Text('فيزا / بطاقة بنكية')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _paymentMethod = val);
                },
              ),
            ],
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
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () async {
            final amtNum = double.tryParse(_finalPaymentCtrl.text.trim()) ?? 0.0;
            final piasters = (amtNum * 100).round();

            final cubit = context.read<PreOrdersCubit>();
            final ok = await cubit.deliverPreOrder(
              widget.order.id,
              finalPaymentPiasters: piasters,
              paymentMethod: _paymentMethod,
            );

            if (ok && context.mounted) {
              Navigator.of(context).pop(true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'تم تسليم الأوردر وإغلاق الحساب بنجاح!',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: AppColors.success,
                ),
              );
            }
          },
          child: const Text(
            'تأكيد التسليم والإغلاق',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, String value, bool isHighlight) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: isHighlight ? 12.5 : 12,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            color: isHighlight ? AppColors.onSurface : Colors.grey.shade700,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: isHighlight ? 14 : 12.5,
            fontWeight: FontWeight.bold,
            color: isHighlight ? AppColors.error : AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}
