import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/pre_order_batch_entity.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class PreOrderBatchCard extends StatefulWidget {
  final PreOrderBatchEntity batch;

  const PreOrderBatchCard({super.key, required this.batch});

  @override
  State<PreOrderBatchCard> createState() => _PreOrderBatchCardState();
}

class _PreOrderBatchCardState extends State<PreOrderBatchCard> {
  bool _isExpanded = false;

  Color _getStatusColor(String status) {
    switch (status) {
      case PreOrderStatuses.pendingProcessing:
        return Colors.orange.shade800;
      case PreOrderStatuses.arrivedAtStore:
        return Colors.teal.shade700;
      case PreOrderStatuses.delivered:
        return AppColors.success;
      default:
        return Colors.blueGrey;
    }
  }

  void _showBatchWhatsAppModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.chat_rounded,
                        color: Color(0xFF25D366), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إرسال إشعارات واتساب لعملاء ${widget.batch.batchNumber}',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'إرسال رسالة وصول مخصصة بحساب كل عميل ونصيبه من الشحن والمتبقي',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 20, color: AppColors.outlineVariant),
              Expanded(
                child: widget.batch.orders.isEmpty
                    ? const Center(
                        child: Text(
                          'لا يوجد عملاء في هذه الشحنة',
                          style: TextStyle(fontFamily: 'Cairo', color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        itemCount: widget.batch.orders.length,
                        separatorBuilder: (context, _) =>
                            const Divider(height: 12, color: AppColors.outlineVariant),
                        itemBuilder: (context, idx) {
                          final o = widget.batch.orders[idx];
                          final remaining = o.remainingWithShippingPiasters;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: Colors.teal.shade50,
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                            ),
                            title: Text(
                              o.customerName,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'هاتف: ${o.customerPhone} • الأصناف: ${Money(o.totalPiasters).toDisplay()} ج • الشحن: ${Money(o.allocatedShippingPiasters).toDisplay()} ج • المتبقي: ${Money(remaining).toDisplay()} ج',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            trailing: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.send_rounded, size: 14),
                              label: const Text(
                                'واتساب',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold),
                              ),
                              onPressed: () => _sendWhatsAppToCustomer(o),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendWhatsAppToCustomer(PreOrderEntity order) async {
    final phone = order.customerPhone.trim();
    if (phone.isEmpty) return;

    var formattedPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (formattedPhone.startsWith('0')) {
      formattedPhone = '2$formattedPhone';
    }

    final message = '''
أهلاً بحضرتك أستاذ/ة ${order.customerName}،
شحنتك رقم #${order.orderNumber} ضمن [${widget.batch.batchNumber}] وصلت المحل وجاهزة للاستلام الآن! 🎉

📦 إجمالي الأصناف: ${Money(order.totalPiasters).toDisplay()} ج.م
🚚 نصيب الشحن العام: ${Money(order.allocatedShippingPiasters).toDisplay()} ج.م
💰 العربون المسدد: ${Money(order.depositPiasters).toDisplay()} ج.م
💵 المبلغ المتبقي عند الاستلام: ${Money(order.remainingWithShippingPiasters).toDisplay()} ج.م

نتشرف بزيارتك لاستلام طلبك في أقرب وقت! يسعدنا دائماً خدمتك.
''';

    final uri = Uri.parse(
      'https://wa.me/$formattedPhone?text=${Uri.encodeComponent(message.trim())}',
    );

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    final statusColor = _getStatusColor(batch.status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.indigo.shade100, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. ترويسة الكارت
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_rounded,
                          size: 15, color: Colors.indigo.shade800),
                      const SizedBox(width: 4),
                      Text(
                        batch.batchNumber,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // بيانات المندوب والبوليصة
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (batch.agentName != null) ...[
                        Row(
                          children: [
                            Icon(Icons.badge_outlined,
                                size: 12, color: Colors.blueGrey.shade600),
                            const SizedBox(width: 3),
                            Text(
                              batch.agentName!,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade800,
                              ),
                            ),
                            if (batch.trackingNumber != null) ...[
                              const Text(' • ',
                                  style: TextStyle(color: Colors.grey)),
                              Icon(Icons.tag_rounded,
                                  size: 12, color: Colors.blueGrey.shade600),
                              const SizedBox(width: 2),
                              Text(
                                batch.trackingNumber!,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Colors.blueGrey.shade700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      Text(
                        'تاريخ الشحنة: ${batch.createdAt.year}-${batch.createdAt.month.toString().padLeft(2, '0')}-${batch.createdAt.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),

                // بادج الحالة
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 3.5, backgroundColor: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        PreOrderStatuses.getLabel(batch.status),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.outlineVariant),

          // 2. شريط الأرقام المالية والمقاييس للشحنة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50.withValues(alpha: 0.3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricColumn('العملاء', '${batch.totalOrdersCount}',
                    Colors.indigo.shade900),
                Container(
                    width: 1, height: 22, color: AppColors.outlineVariant),
                _buildMetricColumn(
                    'القطع', '${batch.totalPiecesCount}', Colors.blueGrey.shade800),
                Container(
                    width: 1, height: 22, color: AppColors.outlineVariant),
                _buildMetricColumn(
                    'المبيعات',
                    Money(batch.totalRetailPiasters).toDisplay(),
                    AppColors.onSurface),
                Container(
                    width: 1, height: 22, color: AppColors.outlineVariant),
                _buildMetricColumn(
                    'الشحن',
                    Money(batch.totalShippingPiasters).toDisplay(),
                    Colors.orange.shade800),
                Container(
                    width: 1, height: 22, color: AppColors.outlineVariant),
                _buildMetricColumn('صافي ربحك',
                    '+${Money(batch.totalProfitPiasters).toDisplay()}', AppColors.primary),
                Container(
                    width: 1, height: 22, color: AppColors.outlineVariant),
                _buildMetricColumn(
                  'المتبقي',
                  Money(batch.totalRemainingWithShippingPiasters).toDisplay(),
                  batch.totalRemainingWithShippingPiasters > 0
                      ? AppColors.error
                      : AppColors.success,
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.outlineVariant),

          // 3. قسم قائمة العملاء القابلة للطي
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Colors.indigo.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'تفاصيل أوردرات العملاء داخل الشحنة (${batch.orders.length})',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'طريقة الشحن: ${ShippingSplitMethods.getLabel(batch.shippingSplitMethod)}',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isExpanded) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: Colors.grey.shade50,
              child: Column(
                children: List.generate(batch.orders.length, (idx) {
                  final o = batch.orders[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.indigo.shade100,
                          child: Text(
                            '${idx + 1}',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 3,
                          child: Text(
                            '${o.customerName} (${o.customerPhone})',
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            'الأصناف: ${Money(o.totalPiasters).toDisplay()} ج + الشحن: ${Money(o.allocatedShippingPiasters).toDisplay()} ج',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: Colors.blueGrey.shade700),
                          ),
                        ),
                        Text(
                          'المتبقي: ${Money(o.remainingWithShippingPiasters).toDisplay()} ج.م',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: o.remainingWithShippingPiasters > 0
                                ? AppColors.error
                                : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],

          const Spacer(),
          const Divider(height: 1, color: AppColors.outlineVariant),

          // 4. أزرار الإجراءات السريعة
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // زر وصول الشحنة بالكامل في المحل
                if (batch.status == PreOrderStatuses.pendingProcessing) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded,
                        size: 16),
                    label: const Text(
                      'استلام الشحنة بالكامل في المحل',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      final cubit = context.read<PreOrdersCubit>();
                      final ok =
                          await cubit.markBatchArrivedAtStore(batch.id);
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'تم استلام الشحنة (${batch.batchNumber}) بالكامل وتحويل جميع أوردراتها إلى جاهزة للاستلام',
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                ],

                // زر إرسال واتساب للعملاء
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.chat_rounded, size: 15),
                  label: const Text(
                    'إرسال واتساب للعملاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _showBatchWhatsAppModal(context),
                ),

                const Spacer(),

                // More Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded,
                      size: 20, color: Colors.grey),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  onSelected: (val) {
                    if (val == 'delete') {
                      context.read<PreOrdersCubit>().deleteBatch(batch.id);
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded,
                              size: 18, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('حذف الشحنة المجمعة',
                              style:
                                  TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 9.5, color: Colors.grey),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
