import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/data/services/customer_ledger_service.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/entities/pre_order_item_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class OrderItemActionDialog extends StatefulWidget {
  final PreOrderEntity order;
  final PreOrderItemEntity item;

  const OrderItemActionDialog({
    super.key,
    required this.order,
    required this.item,
  });

  static Future<void> show(
    BuildContext context, {
    required PreOrderEntity order,
    required PreOrderItemEntity item,
  }) {
    return showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<PreOrdersCubit>(),
        child: OrderItemActionDialog(order: order, item: item),
      ),
    );
  }

  @override
  State<OrderItemActionDialog> createState() => _OrderItemActionDialogState();
}

class _OrderItemActionDialogState extends State<OrderItemActionDialog> {
  String _selectedAction =
      'cancelBeforeOrder'; // 'cancelBeforeOrder', 'outOfStock', 'damaged'
  String _refundOption = 'cash'; // 'cash', 'keep'
  final _refundAmountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _transferToClearance = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Default refund amount: proportional deposit for this item
    final itemTotal = widget.item.totalPricePiasters;
    final orderTotal = widget.order.totalPiasters;
    int suggestedRefund = 0;
    if (orderTotal > 0 && widget.order.depositPiasters > 0) {
      suggestedRefund =
          ((widget.order.depositPiasters * itemTotal) / orderTotal).round();
    }
    _refundAmountCtrl.text = (suggestedRefund / 100)
        .toStringAsFixed(1)
        .replaceAll('.0', '');
  }

  @override
  void dispose() {
    _refundAmountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  int get _refundPiasters {
    final v = double.tryParse(_refundAmountCtrl.text.trim()) ?? 0.0;
    return (v * 100).round();
  }

  Future<void> _sendApologyWhatsApp() async {
    final message =
        'عميلنا العزيز ${widget.order.customerName}،\nنعتذر لك جداً، الصنف [${widget.item.productName}${widget.item.variantDescription != null ? " - ${widget.item.variantDescription}" : ""}] قد نفد من المصدر / غير متوفر لدى المورد أثناء تأكيد الطلب.\nتم خصم قيمته وإرجاع العربون الخاص به.\nشاكرين تفهمك ونسعد بخدمتك دائماً!';

    final baseUri = CustomerLedgerService.buildWhatsAppUri(
      widget.order.customerPhone,
    );
    if (baseUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم الهاتف غير صالح'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح واتساب'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleConfirm() async {
    setState(() => _isSubmitting = true);
    final cubit = context.read<PreOrdersCubit>();
    bool ok = false;

    try {
      if (_selectedAction == 'cancelBeforeOrder') {
        ok = await cubit.cancelOrderItem(
          widget.item.id,
          refundOption: _refundOption,
          refundPiasters: _refundOption == 'cash' ? _refundPiasters : 0,
          notes: _notesCtrl.text.trim().isNotEmpty
              ? _notesCtrl.text.trim()
              : 'إلغاء قبل الطلب',
        );
      } else if (_selectedAction == 'outOfStock') {
        ok = await cubit.markOrderItemOutOfStock(
          widget.item.id,
          refundOption: _refundOption,
          refundPiasters: _refundOption == 'cash' ? _refundPiasters : 0,
          notes: _notesCtrl.text.trim().isNotEmpty
              ? _notesCtrl.text.trim()
              : 'نفد من المصدر / غير متوفر لدى المورد',
        );
      } else if (_selectedAction == 'damaged') {
        ok = await cubit.markOrderItemDamaged(
          widget.item.id,
          refundDeposit: _refundOption == 'cash',
          refundPiasters: _refundOption == 'cash' ? _refundPiasters : 0,
          transferToClearance: _transferToClearance,
          notes: _notesCtrl.text.trim().isNotEmpty
              ? _notesCtrl.text.trim()
              : 'صنف غير مطابق / تالف شحن',
        );
      }

      if (ok && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تنفيذ الإجراء وتحديث الحسابات والمخزن بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 680),
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
                      Icons.rule_rounded,
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
                          'إدارة استثناء الصنف: ${widget.item.productName}',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'العميل: ${widget.order.customerName} | الكمية: ${widget.item.quantity} | القيمة: ${Money(widget.item.totalPricePiasters).toDisplay()} ج',
                          style: const TextStyle(
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

              // Content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'اختر نوع السيناريو / الاستثناء:',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 1. Cancel before order
                      _buildActionOption(
                        id: 'cancelBeforeOrder',
                        title: 'إلغاء الصنف قبل تأكيد الطلب من المصدر / المورد',
                        subtitle:
                            'إلغاء طلب الصنف من المورد لعدم دفع تكلفته مع تسوية عربون العميل',
                      ),
                      const SizedBox(height: 6),

                      // 2. Out of stock by Shein
                      _buildActionOption(
                        id: 'outOfStock',
                        title: 'نفد من المصدر / غير متوفر لدى المورد',
                        subtitle:
                            'خصم التكلفة تلقائياً من المورد وإرجاع عربون الصنف للعميل مع رسالة اعتذار',
                      ),
                      const SizedBox(height: 6),

                      // 3. Defect / Wrong item
                      _buildActionOption(
                        id: 'damaged',
                        title: 'صنف غير مطابق أو تالف شحن (Defect / Wrong Item)',
                        subtitle:
                            'رد العربون للعميل، وتحويل الصنف لركن التخفيضات (Outlet/Clearance) للبيع الفوري',
                      ),

                      const SizedBox(height: 16),
                      const Divider(height: 1, color: AppColors.outlineVariant),
                      const SizedBox(height: 12),

                      // Deposit Refund Strategy
                      const Text(
                        'خيارات العربون والماليات للعميل:',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: _buildRefundOption(
                              id: 'cash',
                              title: 'رد كاش للعميل الآن',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildRefundOption(
                              id: 'keep',
                              title: 'إبقاء كرصيد يخصم من باقي حسابه',
                            ),
                          ),
                        ],
                      ),

                      if (_refundOption == 'cash') ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _refundAmountCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            labelText: 'مبلغ العربون المسترد كاش (ج.م) *',
                            prefixIcon: const Icon(
                              Icons.money_off_csred_rounded,
                              size: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],

                      // Clearance transfer option for damaged items
                      if (_selectedAction == 'damaged') ...[
                        const SizedBox(height: 10),
                        CheckboxListTile(
                          value: _transferToClearance,
                          onChanged: (v) =>
                              setState(() => _transferToClearance = v ?? true),
                          activeColor: AppColors.primary,
                          title: const Text(
                            'طرح الصنف في ركن التخفيضات (Outlet/Clearance) بالمخزن',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: const Text(
                            'إنشاء صنف جديد بباركود فوري في الكاشير بسعر مخفض للبيع المباشر',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10.5,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(
                              color: AppColors.outlineVariant,
                            ),
                          ),
                        ),
                      ],

                      // WhatsApp apology button for out of stock
                      if (_selectedAction == 'outOfStock') ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _sendApologyWhatsApp,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF25D366),
                            side: const BorderSide(color: Color(0xFF25D366)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.chat_rounded, size: 16),
                          label: const Text(
                            'إرسال رسالة اعتذار وتوضيح عبر واتساب للعميل',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _notesCtrl,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                        decoration: InputDecoration(
                          labelText: 'ملاحظات إضافية (اختياري)',
                          hintText: 'سبب الإلغاء أو تفاصيل التلف...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
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
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text(
                      'إلغاء',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _handleConfirm,
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
                    icon: _isSubmitting
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
                      'تأكيد الإجراء',
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

  Widget _buildActionOption({
    required String id,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedAction == id;
    return InkWell(
      onTap: () => setState(() => _selectedAction = id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outlineVariant,
            width: isSelected ? 1.5 : 1.0,
          ),
          color: isSelected ? AppColors.primary.withValues(alpha: 0.04) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefundOption({
    required String id,
    required String title,
  }) {
    final isSelected = _refundOption == id;
    return InkWell(
      onTap: () => setState(() => _refundOption = id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outlineVariant,
            width: isSelected ? 1.5 : 1.0,
          ),
          color: isSelected ? AppColors.primary.withValues(alpha: 0.04) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
