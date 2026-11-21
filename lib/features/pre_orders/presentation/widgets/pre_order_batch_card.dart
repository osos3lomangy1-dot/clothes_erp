import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../data/services/pre_order_excel_service.dart';
import '../../domain/entities/pre_order_batch_entity.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/entities/pre_order_item_entity.dart';
import '../cubits/pre_orders_cubit.dart';
import 'add_customer_to_batch_dialog.dart';
import 'attach_order_to_batch_dialog.dart';
import 'bag_pickup_label_dialog.dart';
import 'batch_emergency_surcharge_dialog.dart';
import 'edit_pre_order_item_dialog.dart';
import 'order_item_action_dialog.dart';
import 'pre_order_delivery_dialog.dart';
import 'pre_order_forfeit_dialog.dart';

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
        return AppColors.primary;
      case PreOrderStatuses.arrivedAtStore:
        return AppColors.primary;
      case PreOrderStatuses.delivered:
        return AppColors.success;
      default:
        return AppColors.onSurfaceVariant;
    }
  }

  void _confirmDeleteItem(BuildContext context, PreOrderItemEntity item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'حذف الصنف',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف الصنف (${item.productName})؟\nسيتم تحديث إجمالي طلب العميل ومقاييس الشحنة تلقائياً.',
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<PreOrdersCubit>().deleteOrderItem(item.id);
            },
            child: const Text(
              'تأكيد الحذف',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteBatch(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              'حذف الشحنة المجمعة',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
        content: Text(
          'هل أنت متأكد من حذف الشحنة (${widget.batch.batchNumber})؟',
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<PreOrdersCubit>().deleteBatch(widget.batch.id);
            },
            child: const Text(
              'تأكيد الحذف',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );
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
                    child: const Icon(
                      Icons.chat_rounded,
                      color: Color(0xFF25D366),
                      size: 22,
                    ),
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
                            color: AppColors.onSurface,
                          ),
                        ),
                        const Text(
                          'إرسال رسالة وصول مخصصة بحساب كل عميل ونصيبه من الشحن والمتبقي',
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
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: widget.batch.orders.length,
                        separatorBuilder: (context, _) => const Divider(
                          height: 12,
                          color: AppColors.outlineVariant,
                        ),
                        itemBuilder: (context, idx) {
                          final o = widget.batch.orders[idx];
                          final remaining = o.remainingWithShippingPiasters;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.1,
                              ),
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            title: Text(
                              o.customerName,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            subtitle: Text(
                              'هاتف: ${o.customerPhone} • الأصناف: ${Money(o.totalPiasters).toDisplay()} ج • الشحن: ${Money(o.allocatedShippingPiasters).toDisplay()} ج • المتبقي: ${Money(remaining).toDisplay()} ج',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            trailing: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.send_rounded, size: 14),
                              label: const Text(
                                'واتساب',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
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

    final message =
        '''
أهلاً بحضرتك أستاذ/ة ${order.customerName}،
شحنتك رقم #${order.orderNumber} ضمن [${widget.batch.batchNumber}] وصلت المحل وجاهزة للاستلام الآن!

- إجمالي الأصناف: ${Money(order.totalPiasters).toDisplay()} ج.م
- نصيب الشحن العام: ${Money(order.allocatedShippingPiasters).toDisplay()} ج.م
- العربون المسدد: ${Money(order.depositPiasters).toDisplay()} ج.م
- المبلغ المتبقي عند الاستلام: ${Money(order.remainingWithShippingPiasters).toDisplay()} ج.م

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
        border: Border.all(color: AppColors.outlineVariant),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_2_rounded,
                        size: 15,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        batch.batchNumber,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
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
                            const Icon(
                              Icons.badge_outlined,
                              size: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                batch.agentName!,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (batch.trackingNumber != null) ...[
                              const Text(
                                ' • ',
                                style: TextStyle(
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                              const Icon(
                                Icons.tag_rounded,
                                size: 12,
                                color: AppColors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  batch.trackingNumber!,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      Text(
                        'تاريخ الشحنة: ${batch.createdAt.year}-${batch.createdAt.month.toString().padLeft(2, '0')}-${batch.createdAt.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                // بادج الحالة
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
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

          // 2. كروت المؤشرات المالية والإحصائية المريحة (4 كروت واضحة ومتنفسة)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    icon: Icons.people_outline_rounded,
                    label: 'العملاء والقطع',
                    mainValue: '${batch.totalOrdersCount} عميل (${batch.totalPiecesCount} ق)',
                    mainColor: AppColors.onSurface,
                    subValue: ShippingSplitMethods.getLabel(batch.shippingSplitMethod),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricCard(
                    icon: Icons.point_of_sale_rounded,
                    label: 'المبيعات والمتبقي',
                    mainValue: '${Money(batch.totalRetailPiasters).toDisplay()} ج',
                    mainColor: AppColors.onSurface,
                    subValue: 'المتبقي: ${Money(batch.totalRemainingWithShippingPiasters).toDisplay()} ج',
                    subColor: batch.totalRemainingWithShippingPiasters > 0
                        ? AppColors.error
                        : AppColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricCard(
                    icon: Icons.trending_up_rounded,
                    label: 'صافي ربحك والشحن',
                    mainValue: '+${Money(batch.totalProfitPiasters).toDisplay()} ج',
                    mainColor: AppColors.primary,
                    subValue: 'شحن المندوب: ${Money(batch.totalShippingPiasters).toDisplay()} ج',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'العربونات والتكلفة',
                    mainValue: '${Money(batch.totalDepositsPiasters).toDisplay()} ج عربون',
                    mainColor: AppColors.onSurface,
                    subValue: 'الجملة: ${Money(batch.totalCostPiasters).toDisplay()} ج',
                  ),
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
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'تفاصيل أوردرات العملاء داخل الشحنة (${batch.orders.length})',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'طريقة الشحن: ${ShippingSplitMethods.getLabel(batch.shippingSplitMethod)}',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isExpanded) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: AppColors.surfaceContainerLow,
              child: Column(
                children: List.generate(batch.orders.length, (idx) {
                  final o = batch.orders[idx];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.1,
                              ),
                              child: Text(
                                '${idx + 1}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
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
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 3,
                              child: Text(
                                'الأصناف: ${Money(o.totalPiasters).toDisplay()} ج'
                                '${o.allocatedShippingPiasters > 0 ? " + شحن: ${Money(o.allocatedShippingPiasters).toDisplay()} ج" : ""}'
                                '${o.emergencyIncreasePiasters > 0 ? " + زيادة: ${Money(o.emergencyIncreasePiasters).toDisplay()} ج" : ""}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: AppColors.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
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
                            const SizedBox(width: 6),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                Icons.label_important_outline,
                                size: 15,
                                color: AppColors.primary,
                              ),
                              tooltip: 'طباعة استيكر فرز الكيس',
                              onPressed: () =>
                                  BagPickupLabelDialog.show(context, o),
                            ),
                            if (o.canDeliver) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 16,
                                  color: AppColors.success,
                                ),
                                tooltip: 'تسليم الأوردر للعميل',
                                onPressed: () =>
                                    PreOrderDeliveryDialog.show(context, o),
                              ),
                            ],
                            if (o.canForfeit) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(
                                  Icons.gavel_rounded,
                                  size: 15,
                                  color: AppColors.error,
                                ),
                                tooltip: 'مصادرة العربون وطرح البضاعة للمخزن',
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => BlocProvider.value(
                                    value: context.read<PreOrdersCubit>(),
                                    child: PreOrderForfeitDialog(order: o),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        // قائمة الأصناف للعميل مع إمكانية التعديل وإدارة الاستثناءات والحذف
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ...o.items.map((it) {
                              String statusText = '';
                              Color badgeColor = AppColors.onSurfaceVariant;
                              if (it.isCancelled) {
                                statusText = ' [ملغي قبل الطلب]';
                                badgeColor = AppColors.error;
                              } else if (it.isOutOfStock) {
                                statusText = ' [نفد من المصدر]';
                                badgeColor = AppColors.error;
                              } else if (it.isDamaged) {
                                statusText = ' [تالف/أوتلت]';
                                badgeColor = AppColors.primary;
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: it.isActive
                                        ? AppColors.outlineVariant
                                        : badgeColor.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${it.productName}${it.variantDescription != null ? " (${it.variantDescription})" : ""} × ${it.quantity}$statusText',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        decoration:
                                            (it.isCancelled || it.isOutOfStock)
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: badgeColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // أيقونة تعديل الصنف
                                    InkWell(
                                      onTap: () => EditPreOrderItemDialog.show(
                                        context,
                                        orderId: o.id,
                                        item: it,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.edit_outlined,
                                          size: 12,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    // أيقونة الاستثناءات
                                    InkWell(
                                      onTap: () => OrderItemActionDialog.show(
                                        context,
                                        order: o,
                                        item: it,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.tune_rounded,
                                          size: 12,
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    // أيقونة الحذف
                                    InkWell(
                                      onTap: () =>
                                          _confirmDeleteItem(context, it),
                                      borderRadius: BorderRadius.circular(4),
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.delete_outline_rounded,
                                          size: 12,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            // زر إضافة صنف جديد لهذا العميل
                            InkWell(
                              onTap: () => EditPreOrderItemDialog.show(
                                context,
                                orderId: o.id,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_rounded,
                                      size: 12,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '+ إضافة صنف',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],

          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.outlineVariant),

          // 4. شريط الإجراءات والقرارات الذكي (سلس ومرتب ومنسق في سطر واحد)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                // الإجراءات التشغيلية المباشرة (على اليمين)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (batch.status == PreOrderStatuses.pendingProcessing) ...[
                      // زر استلام الشحنة بالكامل في المحل
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 16,
                        ),
                        label: const Text(
                          'استلام الشحنة في المحل',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          final cubit = context.read<PreOrdersCubit>();
                          final ok = await cubit.markBatchArrivedAtStore(
                            batch.id,
                          );
                          if (ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تم استلام الشحنة (${batch.batchNumber}) بالكامل وتحويل جميع أوردراتها إلى جاهزة للاستلام',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          }
                        },
                      ),
                      // زر إضافة عميل للشحنة
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 15,
                        ),
                        label: const Text(
                          '+ إضافة عميل',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () =>
                            AddCustomerToBatchDialog.show(context, batch),
                      ),
                      // زر ضم أوردر فردي معلق
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.onSurface,
                          side: const BorderSide(color: AppColors.outlineVariant),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.link_rounded, size: 15),
                        label: const Text(
                          'ضم أوردر',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () =>
                            AttachOrderToBatchDialog.show(context, batch),
                      ),
                    ] else ...[
                      // الشحنة وصلت المحل وجاهزة للتسليم
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: AppColors.success,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'وصلت المحل وجاهزة للتسليم',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 15,
                        ),
                        label: const Text(
                          '+ إضافة عميل',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () =>
                            AddCustomerToBatchDialog.show(context, batch),
                      ),
                    ],
                  ],
                ),

                // أدوات المتابعة والتقارير (على اليسار - شريط أيقونات مدمج وأنيق)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToolIconButton(
                      icon: Icons.chat_rounded,
                      color: const Color(0xFF25D366),
                      tooltip: 'واتساب جماعي للعملاء',
                      onPressed: () => _showBatchWhatsAppModal(context),
                    ),
                    const SizedBox(width: 6),
                    _buildToolIconButton(
                      icon: Icons.table_chart_outlined,
                      color: AppColors.onSurface,
                      tooltip: 'كشف المندوب إكسيل',
                      onPressed: () async {
                        final path =
                            await PreOrderExcelService.exportBatchToExcel(batch);
                        if (path != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم تصدير كشف الشحنة للمندوب بنجاح!\n$path',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    _buildToolIconButton(
                      icon: Icons.currency_exchange_rounded,
                      color: AppColors.onSurface,
                      tooltip: 'فرق عملة / زيادة طارئة',
                      onPressed: () =>
                          BatchEmergencySurchargeDialog.show(context, batch),
                    ),
                    const SizedBox(width: 6),
                    PopupMenuButton<String>(
                      tooltip: 'خيارات متقدمة',
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.more_vert_rounded,
                          size: 16,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onSelected: (val) {
                        if (val == 'delete') {
                          _confirmDeleteBatch(context);
                        }
                      },
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: AppColors.error,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'حذف الشحنة المجمعة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String mainValue,
    required Color mainColor,
    required String subValue,
    Color? subColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Icon(icon, size: 16, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Text(
                  mainValue,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: mainColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subValue,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 9.5,
                    color: subColor ?? AppColors.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolIconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}
}
