import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class PreOrderDeliveryDialog extends StatefulWidget {
  final PreOrderEntity order;

  const PreOrderDeliveryDialog({super.key, required this.order});

  static Future<bool?> show(BuildContext context, PreOrderEntity order) {
    return showDialog<bool>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<PreOrdersCubit>(),
        child: PreOrderDeliveryDialog(order: order),
      ),
    );
  }

  @override
  State<PreOrderDeliveryDialog> createState() => _PreOrderDeliveryDialogState();
}

class _PreOrderDeliveryDialogState extends State<PreOrderDeliveryDialog> {
  final TextEditingController _finalPaymentCtrl = TextEditingController();
  final TextEditingController _courierFeeCtrl = TextEditingController(
    text: '0',
  );
  final TextEditingController _courierNameCtrl = TextEditingController();

  String _deliveryType = 'pickup'; // 'pickup' | 'courier'
  String _paymentMethod = 'cash';
  late final Set<String> _selectedItemIds;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedItemIds = widget.order.items.map((e) => e.id).toSet();
    _recalculatePaymentAmount();
  }

  void _recalculatePaymentAmount() {
    final totalRemaining = widget.order.remainingWithShippingPiasters;
    final totalItemsCount = widget.order.items.length;

    int duePiasters;
    if (_selectedItemIds.length == totalItemsCount || totalItemsCount == 0) {
      duePiasters = totalRemaining;
    } else {
      // تسليم جزئي: حساب نسبة الأصناف المختارة من الإجمالي
      final selectedTotal = widget.order.items
          .where((it) => _selectedItemIds.contains(it.id))
          .fold(0, (sum, it) => sum + it.totalPricePiasters);
      final orderRetail = widget.order.totalPiasters > 0
          ? widget.order.totalPiasters
          : 1;
      // نصيب الأصناف المختارة بعد توزيع العربون بنسبة قيمتها
      final ratio = selectedTotal / orderRetail;
      duePiasters = (totalRemaining * ratio).round();
    }

    if (_deliveryType == 'courier') {
      final courierFee =
          (double.tryParse(_courierFeeCtrl.text.trim()) ?? 0.0) * 100;
      duePiasters += courierFee.round();
    }

    final remLe = duePiasters > 0 ? duePiasters / 100.0 : 0.0;
    _finalPaymentCtrl.text =
        remLe > 0 ? remLe.toStringAsFixed(1).replaceAll('.0', '') : '0';

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _finalPaymentCtrl.dispose();
    _courierFeeCtrl.dispose();
    _courierNameCtrl.dispose();
    super.dispose();
  }

  bool get _isPartialDelivery =>
      _selectedItemIds.length < widget.order.items.length &&
      widget.order.items.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تسليم أوردر الحجز #${widget.order.orderNumber}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  'العميل: ${widget.order.customerName} (${widget.order.customerPhone})',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. خيار طريقة التسليم (استلام من المحل vs توصيل دليفري)
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _deliveryType = 'pickup';
                            _courierFeeCtrl.text = '0';
                            _recalculatePaymentAmount();
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _deliveryType == 'pickup'
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.storefront_rounded,
                                size: 15,
                                color: _deliveryType == 'pickup'
                                    ? Colors.white
                                    : AppColors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'استلام من المحل',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: _deliveryType == 'pickup'
                                      ? Colors.white
                                      : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _deliveryType = 'courier';
                            _recalculatePaymentAmount();
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _deliveryType == 'courier'
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.local_shipping_outlined,
                                size: 15,
                                color: _deliveryType == 'courier'
                                    ? Colors.white
                                    : AppColors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'شحن محلي / شركة توصيل',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: _deliveryType == 'courier'
                                      ? Colors.white
                                      : AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_deliveryType == 'courier') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _courierNameCtrl,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                        decoration: InputDecoration(
                          labelText: 'شركة الشحن / اسم الطيار',
                          prefixIcon: Icon(
                            Icons.delivery_dining_rounded,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _courierFeeCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          labelText: 'مصاريف الشحن (ج.م)',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (_) => _recalculatePaymentAmount(),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // 2. قائمة اختيار الأصناف (دعم التسليم الجزئي)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'الأصناف المراد تسليمها الآن:',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            if (_isPartialDelivery) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'تسليم جزئي (${_selectedItemIds.length}/${widget.order.items.length})',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (_selectedItemIds.length ==
                                  widget.order.items.length) {
                                _selectedItemIds.clear();
                              } else {
                                _selectedItemIds.addAll(
                                  widget.order.items.map((e) => e.id),
                                );
                              }
                              _recalculatePaymentAmount();
                            });
                          },
                          child: Text(
                            _selectedItemIds.length == widget.order.items.length
                                ? 'إلغاء تحديد الكل'
                                : 'تحديد الكل',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 10, color: AppColors.outlineVariant),
                    ...widget.order.items.map((it) {
                      final isSelected = _selectedItemIds.contains(it.id);
                      return CheckboxListTile(
                        value: isSelected,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.primary,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          it.productName,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            decoration: isSelected
                                ? null
                                : TextDecoration.lineThrough,
                            color: isSelected
                                ? AppColors.onSurface
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                        subtitle: it.variantDescription != null
                            ? Text(
                                it.variantDescription!,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10.5,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              )
                            : null,
                        secondary: Text(
                          '${it.quantity} × ${Money(it.unitPricePiasters).toDisplay()} ج',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedItemIds.add(it.id);
                            } else {
                              _selectedItemIds.remove(it.id);
                            }
                            _recalculatePaymentAmount();
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 3. ملخص المبالغ المالية
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  children: [
                    _row(
                      'إجمالي الأوردر:',
                      '${Money(widget.order.totalWithShippingPiasters).toDisplay()} ج.م',
                      false,
                    ),
                    const SizedBox(height: 4),
                    _row(
                      'العربون والمدفوعات السابقة:',
                      '${Money(widget.order.depositPiasters).toDisplay()} ج.م',
                      false,
                    ),
                    if (widget.order.allocatedShippingPiasters > 0) ...[
                      const SizedBox(height: 4),
                      _row(
                        'نصيب العميل من الشحن:',
                        '+${Money(widget.order.allocatedShippingPiasters).toDisplay()} ج.م',
                        false,
                      ),
                    ],
                    const Divider(height: 14, color: AppColors.outlineVariant),
                    _row(
                      _isPartialDelivery
                          ? 'المطلوب تحصيله لهذه الأصناف المسلمة:'
                          : 'المتبقي الإجمالي للتحصيل الآن:',
                      '${_finalPaymentCtrl.text} ج.م',
                      true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 4. حقل المبلغ المدفوع وطريقة الدفع
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _finalPaymentCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                      decoration: InputDecoration(
                        labelText: 'المبلغ المحصل الآن (ج.م) *',
                        prefixIcon: Icon(
                          Icons.payments_outlined,
                          color: AppColors.primary,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: InputDecoration(
                        labelText: 'طريقة الدفع',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'cash',
                          child: Text('كاش (نقداً)'),
                        ),
                        DropdownMenuItem(
                          value: 'instapay',
                          child: Text('انستاباي (InstaPay)'),
                        ),
                        DropdownMenuItem(
                          value: 'vodafone_cash',
                          child: Text('فودافون كاش'),
                        ),
                        DropdownMenuItem(
                          value: 'card',
                          child: Text('فيزا / بطاقة'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _paymentMethod = val);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'إلغاء',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _isPartialDelivery
                ? AppColors.primary
                : AppColors.success,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              : Icon(
                  _isPartialDelivery
                      ? Icons.playlist_add_check_rounded
                      : Icons.check_circle_rounded,
                ),
          label: Text(
            _isSubmitting
                ? 'جاري التسليم...'
                : (_isPartialDelivery
                    ? 'تأكيد التسليم الجزئي'
                    : 'تأكيد التسليم الكامل والإغلاق'),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          onPressed: _isSubmitting
              ? null
              : () async {
                  if (_selectedItemIds.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('يرجى تحديد صنف واحد على الأقل لتسليمه'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                    return;
                  }

                  final amtNum =
                      double.tryParse(_finalPaymentCtrl.text.trim()) ?? 0.0;
                  final piasters = (amtNum * 100).round();

                  setState(() => _isSubmitting = true);

                  try {
                    final cubit = context.read<PreOrdersCubit>();
                    final isAllDelivered =
                        _selectedItemIds.length == widget.order.items.length;

                    if (isAllDelivered) {
                      final ok = await cubit.deliverPreOrder(
                        widget.order.id,
                        finalPaymentPiasters: piasters,
                        paymentMethod: _paymentMethod,
                      );
                      if (!context.mounted) return;
                      if (ok) {
                        Navigator.of(context).pop(true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'تم تسليم الأوردر بالكامل وإغلاق الحساب بنجاح!',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } else {
                        setState(() => _isSubmitting = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              cubit.state.errorMessage ??
                                  'فشل إتمام تسليم الأوردر',
                            ),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    } else {
                      // تسليم جزئي: إضافة دفعة بقيمة الأصناف المسلمة وتسجيل ملاحظة
                      if (piasters > 0) {
                        final ok = await cubit.addPayment(
                          widget.order.id,
                          piasters,
                          paymentMethod: _paymentMethod,
                          notes:
                              'تسليم جزئي لـ ${_selectedItemIds.length} أصناف من أصل ${widget.order.items.length}${_deliveryType == 'courier' && _courierNameCtrl.text.trim().isNotEmpty ? ' (توصيل ${_courierNameCtrl.text.trim()})' : ''}',
                        );
                        if (!ok) {
                          if (context.mounted) {
                            setState(() => _isSubmitting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  cubit.state.errorMessage ??
                                      'فشل تسجيل دفعة التسليم الجزئي',
                                ),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                          return;
                        }
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop(true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'تم تسجيل تسليم جزئي لـ ${_selectedItemIds.length} أصناف بنجاح، وتبقى ${widget.order.items.length - _selectedItemIds.length} أصناف قيد الانتظار!',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => _isSubmitting = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('حدث خطأ أثناء تنفيذ التسليم: $e'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  }
                },
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
            color: isHighlight
                ? AppColors.onSurface
                : AppColors.onSurfaceVariant,
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
