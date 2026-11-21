import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/pre_order_batch_entity.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../cubits/pre_orders_cubit.dart';
import '../cubits/pre_orders_state.dart';

class AttachOrderToBatchDialog extends StatefulWidget {
  final PreOrderBatchEntity batch;

  const AttachOrderToBatchDialog({super.key, required this.batch});

  static Future<void> show(BuildContext context, PreOrderBatchEntity batch) {
    return showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<PreOrdersCubit>(),
        child: AttachOrderToBatchDialog(batch: batch),
      ),
    );
  }

  @override
  State<AttachOrderToBatchDialog> createState() =>
      _AttachOrderToBatchDialogState();
}

class _AttachOrderToBatchDialogState extends State<AttachOrderToBatchDialog> {
  String _search = '';
  String? _attachingOrderId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PreOrdersCubit, PreOrdersState>(
      builder: (context, state) {
        // Unattached orders that are pending
        final unassignedOrders = state.allOrders.where((o) {
          final isPending = o.status == PreOrderStatuses.pendingProcessing;
          final isUnattached = o.batchId == null || o.batchId!.isEmpty;
          final matchesSearch = _search.isEmpty ||
              o.orderNumber.toLowerCase().contains(_search.toLowerCase()) ||
              o.customerName.toLowerCase().contains(_search.toLowerCase()) ||
              o.customerPhone.contains(_search);
          return isPending && isUnattached && matchesSearch;
        }).toList();

        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550, maxHeight: 600),
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
                        child: Icon(Icons.link_rounded,
                            color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ضم أوردر فردي معلق إلى ${widget.batch.batchNumber}',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const Text(
                              'إلحاق أوردر فردي مفتوح بالشحنة المجمعة لتجميع الشحن وتوحيد المندوب',
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
                        icon: const Icon(Icons.close_rounded, color: AppColors.onSurfaceVariant),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: AppColors.outlineVariant),

                  // Search box
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'بحث باسم العميل أو رقم الهاتف أو رقم الأوردر...',
                      hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => setState(() => _search = v.trim()),
                  ),
                  const SizedBox(height: 12),

                  // List of unattached orders
                  Expanded(
                    child: unassignedOrders.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text(
                                  _search.isNotEmpty
                                      ? 'لا توجد طلبات تطابق البحث'
                                      : 'لا توجد طلبات حجز فردية معلقة غير مرتبطة بشحنة',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: unassignedOrders.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 10, color: AppColors.outlineVariant),
                            itemBuilder: (ctx, idx) {
                              final o = unassignedOrders[idx];
                              final isAttaching = _attachingOrderId == o.id;

                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.outlineVariant),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                '#${o.orderNumber}',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                o.customerName,
                                                style: const TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'الهاتف: ${o.customerPhone} | الأصناف: ${o.items.length} قطعة | الإجمالي: ${Money(o.totalPiasters).toDisplay()} ج',
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              color: AppColors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: isAttaching
                                          ? null
                                          : () async {
                                              setState(() => _attachingOrderId = o.id);
                                              final nav = Navigator.of(context);
                                              final messenger = ScaffoldMessenger.of(context);
                                              final ok = await context
                                                  .read<PreOrdersCubit>()
                                                  .attachOrderToBatch(widget.batch.id, o.id);
                                              if (mounted) {
                                                setState(() => _attachingOrderId = null);
                                                if (ok) {
                                                  nav.pop();
                                                  messenger.showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'تم إلحاق أوردر #${o.orderNumber} بالشحنة بنجاح',
                                                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                                      ),
                                                      backgroundColor: AppColors.success,
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: isAttaching
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                            )
                                          : const Icon(Icons.add_link_rounded, size: 16),
                                      label: const Text('ضم للشحنة', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppColors.outlineVariant),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
