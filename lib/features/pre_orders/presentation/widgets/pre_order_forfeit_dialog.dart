import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class PreOrderForfeitDialog extends StatefulWidget {
  final PreOrderEntity order;

  const PreOrderForfeitDialog({super.key, required this.order});

  @override
  State<PreOrderForfeitDialog> createState() => _PreOrderForfeitDialogState();
}

class _PreOrderForfeitDialogState extends State<PreOrderForfeitDialog> {
  bool _transferToInventory = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'مصادرة العربون ونقل البضاعة للمخزن',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تأكيد رفض العميل (${widget.order.customerName}) للاستلام وتخلفه عن الموعد المحدد للأوردر #${widget.order.orderNumber}.',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                height: 1.4,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.monetization_on_rounded,
                          size: 16, color: AppColors.error),
                      const SizedBox(width: 6),
                      Text(
                        'مبلغ العربون المصادر: ${Money(widget.order.depositPiasters).toDisplay()} ج.م',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: AppColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'يتم قيد المبلغ محاسبياً كـ "إيراد تشغيلي آخر" لتعويض تكاليف الشحن والمصنعية.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Checkbox: Transfer items to general store inventory
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.primary,
              title: const Text(
                'نقل بضاعة الأوردر للمخزن العام كبضاعة حاضرة للبيع الفوري',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              subtitle: Text(
                'سيتم إدراج ${widget.order.items.length} أصناف في شبكة المنتجات بأسعار البيع الخاصة بها ليتمكن الكاشير من بيعها لأي عميل.',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              value: _transferToInventory,
              onChanged: (val) {
                if (val != null) setState(() => _transferToInventory = val);
              },
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('تراجع',
              style: TextStyle(
                  fontFamily: 'Cairo', color: AppColors.onSurfaceVariant)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () async {
            final cubit = context.read<PreOrdersCubit>();
            final ok = await cubit.forfeitDeposit(
              widget.order.id,
              transferItemsToInventory: _transferToInventory,
            );

            if (ok && context.mounted) {
              Navigator.of(context).pop(true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'تمت مصادرة العربون (${Money(widget.order.depositPiasters).toDisplay()} ج.م)${_transferToInventory ? ' ونقل البضاعة للمخزن العام بنجاح' : ''}',
                    style: const TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          },
          child: const Text(
            'تأكيد المصادرة',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
