import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/data/services/customer_ledger_service.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../cubits/pre_orders_cubit.dart';
import 'pre_order_forfeit_dialog.dart';
import 'pre_order_payment_dialog.dart';

class PreOrderCard extends StatelessWidget {
  final PreOrderEntity order;
  final VoidCallback? onDeliver;
  final VoidCallback? onViewDetails;

  const PreOrderCard({
    super.key,
    required this.order,
    this.onDeliver,
    this.onViewDetails,
  });

  void _sendWhatsApp(BuildContext context, String templateType) async {
    final phone = order.customerPhone.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم هاتف العميل غير متوفر'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    String message;
    switch (templateType) {
      case 'arrived':
        message =
            'عزيزي ${order.customerName}، نود إعلامك بأن أوردرك رقم [${order.orderNumber}] وصل بنجاح وجاهز للاستلام الآن بفرعنا.\nالمبلغ المتبقي: [${Money(order.remainingPiasters).toDisplay()} ج.م].\nأهلاً بك في أي وقت!';
        break;
      case 'reminder':
        message =
            'تنبيه لعميلنا العزيز ${order.customerName}: نود تذكيرك بأن أوردرك رقم [${order.orderNumber}] متوفر بالفرع، برجاء التكرم بالاستلام خلال 48 ساعة لتجنب إلغاء الحجز ومصادرة العربون.';
        break;
      case 'booking':
      default:
        message =
            'مرحباً ${order.customerName}، تم تسجيل طلبك رقم [${order.orderNumber}] بنجاح.\nالإجمالي: [${Money(order.totalPiasters).toDisplay()} ج.م]، العربون المدفوع: [${Money(order.depositPiasters).toDisplay()} ج.م]، المتبقي عند الاستلام: [${Money(order.remainingPiasters).toDisplay()} ج.م].\nسنوافيك بإشعار فور وصول شحنتك للمحل. نسعد بخدمتكم!';
        break;
    }

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

    final fullUri = Uri.parse('${baseUri.toString()}?text=${Uri.encodeComponent(message)}');
    try {
      await launchUrl(fullUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح تطبيق واتساب على هذا الجهاز'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showWhatsAppMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'اختيار قالب رسالة واتساب للعميل',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(Icons.check_circle_outline, color: AppColors.primary),
                  title: const Text('إشعار تأكيد الحجز والعربون', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                  subtitle: const Text('إرسال تفاصيل الأوردر والمبلغ المدفوع والمتبقي', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendWhatsApp(context, 'booking');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.storefront_rounded, color: Colors.teal),
                  title: const Text('إشعار وصول الشحنة للمحل', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                  subtitle: const Text('إبلاغ العميل بأن الشحنة جاهزة للاستلام بالفرع', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendWhatsApp(context, 'arrived');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.alarm_rounded, color: Colors.orange),
                  title: const Text('تذكير عاجل بالاستلام', style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                  subtitle: const Text('تنبيه بالاستلام خلال 48 ساعة قبل مصادرة العربون', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendWhatsApp(context, 'reminder');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case PreOrderStatuses.pendingProcessing:
        return Colors.amber.shade800;
      case PreOrderStatuses.arrivedAtStore:
        return Colors.teal.shade700;
      case PreOrderStatuses.delivered:
        return AppColors.success;
      case PreOrderStatuses.defaultedForfeited:
        return Colors.orange.shade800;
      case PreOrderStatuses.refundedCancelled:
        return Colors.grey.shade600;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(order.status);
    final remainingPiasters = order.remainingPiasters;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                // Order Number Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    order.orderNumber,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Customer Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        order.customerPhone,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 3.5, backgroundColor: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        PreOrderStatuses.getLabel(order.status),
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

          // 2. Items Preview
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...order.items.take(3).map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 5, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.productName,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.variantDescription != null &&
                            item.variantDescription!.isNotEmpty) ...[
                          Text(
                            ' (${item.variantDescription})',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          '${item.quantity} × ${Money(item.unitPricePiasters).toDisplay()} ج',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (item.itemUrl != null && item.itemUrl!.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => launchUrl(
                              Uri.parse(item.itemUrl!),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(Icons.open_in_new_rounded, size: 13, color: AppColors.primary),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                if (order.items.length > 3) ...[
                  Text(
                    '+ ${order.items.length - 3} أصناف أخرى...',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const Spacer(),

          // 3. Financial Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              border: Border(
                top: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
                bottom: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildAmountColumn('الإجمالي', Money(order.totalPiasters).toDisplay(), AppColors.onSurface),
                Container(width: 1, height: 22, color: AppColors.outlineVariant),
                _buildAmountColumn('المسدد (عربون)', Money(order.depositPiasters).toDisplay(), AppColors.primary),
                Container(width: 1, height: 22, color: AppColors.outlineVariant),
                _buildAmountColumn(
                  'المتبقي',
                  Money(remainingPiasters).toDisplay(),
                  remainingPiasters > 0 ? AppColors.error : AppColors.success,
                ),
              ],
            ),
          ),

          // 4. Quick Actions Row
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // WhatsApp Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.chat_rounded, size: 15),
                  label: const Text('واتساب', style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold)),
                  onPressed: () => _showWhatsAppMenu(context),
                ),
                const SizedBox(width: 6),

                // Add Payment Button
                if (order.canAddPayment && remainingPiasters > 0) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_card_rounded, size: 15),
                    label: const Text('دفعة', style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => BlocProvider.value(
                          value: context.read<PreOrdersCubit>(),
                          child: PreOrderPaymentDialog(order: order),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                ],

                // Deliver Button
                if (order.canDeliver) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 15),
                    label: const Text('تسليم', style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold)),
                    onPressed: onDeliver,
                  ),
                ],

                const Spacer(),

                // More Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.grey),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onSelected: (val) async {
                    final cubit = context.read<PreOrdersCubit>();
                    if (val == 'arrived') {
                      await cubit.markArrivedAtStore(order.id);
                    } else if (val == 'forfeit') {
                      showDialog(
                        context: context,
                        builder: (_) => BlocProvider.value(
                          value: cubit,
                          child: PreOrderForfeitDialog(order: order),
                        ),
                      );
                    } else if (val == 'cancel') {
                      _showCancelDialog(context, cubit);
                    } else if (val == 'delete') {
                      cubit.deletePreOrder(order.id);
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (order.status == PreOrderStatuses.pendingProcessing)
                      const PopupMenuItem(
                        value: 'arrived',
                        child: Row(
                          children: [
                            Icon(Icons.storefront_rounded, size: 18, color: Colors.teal),
                            SizedBox(width: 8),
                            Text('وصل للمحل جاهز للتسليم', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                          ],
                        ),
                      ),
                    if (order.canForfeit)
                      PopupMenuItem(
                        value: 'forfeit',
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 18, color: Colors.orange.shade800),
                            const SizedBox(width: 8),
                            const Text('مصادرة العربون ونقل للمخزن', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                          ],
                        ),
                      ),
                    if (order.canCancel)
                      const PopupMenuItem(
                        value: 'cancel',
                        child: Row(
                          children: [
                            Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('إلغاء واسترداد جزئي/كامل', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('حذف الحجز', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
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

  Widget _buildAmountColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.grey),
        ),
        Text(
          '$value ج.م',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showCancelDialog(BuildContext context, PreOrdersCubit cubit) {
    final refundCtrl = TextEditingController(
      text: (order.depositPiasters / 100.0).toStringAsFixed(2),
    );
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'إلغاء أوردر الحجز ورد العربون',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'العربون المسدد حالياً: ${Money(order.depositPiasters).toDisplay()} ج.م',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: refundCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'المبلغ المسترد للعميل (ج.م)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                labelText: 'سبب الإلغاء',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تراجع', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final refNum = double.tryParse(refundCtrl.text.trim()) ?? 0.0;
              final refPiasters = (refNum * 100).round();
              cubit.cancelAndRefund(
                order.id,
                refundAmountPiasters: refPiasters,
                notes: reasonCtrl.text.trim(),
              );
              Navigator.pop(ctx);
            },
            child: const Text('تأكيد الإلغاء', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
