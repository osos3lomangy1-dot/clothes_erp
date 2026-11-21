import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'مصادرة العربون ونقل البضاعة للمخزن',
              style: TextStyle(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تأكيد رفض العميل (${widget.order.customerName}) للاستلام وتخلفه عن الموعد المحدد للأوردر #${widget.order.orderNumber}.',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.monetization_on_rounded, size: 16, color: Colors.orange.shade900),
                      const SizedBox(width: 6),
                      Text(
                        'مبلغ العربون المصادر: ${Money(widget.order.depositPiasters).toDisplay()} ج.م',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'يتم قيد المبلغ محاسبياً كـ "إيراد تشغيلي آخر" لتعويض تكاليف الشحن والمصنعية.',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Checkbox: Transfer items to general store inventory
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'نقل بضاعة الأوردر للمخزن العام كبضاعة حاضرة للبيع الفوري',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'سيتم إدراج ${widget.order.items.length} أصناف في شبكة المنتجات بأسعار البيع الخاصة بها ليتمكن الكاشير من بيعها لأي عميل.',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
              ),
              value: _transferToInventory,
              onChanged: (val) {
                if (val != null) setState(() => _transferToInventory = val);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('تراجع', style: TextStyle(fontFamily: 'Cairo')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: Colors.orange.shade800,
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
