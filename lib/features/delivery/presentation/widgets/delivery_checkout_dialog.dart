import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/delivery_courier_entity.dart';
import '../../domain/entities/delivery_order_entity.dart';

class DeliveryCheckoutDialog extends StatefulWidget {
  final String branchId;
  final String? saleId;
  final String orderRef;
  final String? customerId;
  final String initialCustomerName;
  final String initialCustomerPhone;
  final int orderTotalPiasters;
  final List<DeliveryCourierEntity> couriers;

  const DeliveryCheckoutDialog({
    super.key,
    required this.branchId,
    this.saleId,
    required this.orderRef,
    this.customerId,
    this.initialCustomerName = '',
    this.initialCustomerPhone = '',
    required this.orderTotalPiasters,
    this.couriers = const [],
  });

  @override
  State<DeliveryCheckoutDialog> createState() => _DeliveryCheckoutDialogState();
}

class _DeliveryCheckoutDialogState extends State<DeliveryCheckoutDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _feeCtrl;
  late TextEditingController _orderTotalCtrl;
  late TextEditingController _notesCtrl;

  String? _selectedCourierId;
  String _paymentMethod = 'cod'; // 'cod' or 'paid'

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialCustomerName);
    _phoneCtrl = TextEditingController(text: widget.initialCustomerPhone);
    _addressCtrl = TextEditingController();
    _feeCtrl = TextEditingController(text: '20.00'); // default 20 EGP delivery fee
    _orderTotalCtrl = TextEditingController(
      text: (widget.orderTotalPiasters / 100.0).toStringAsFixed(2),
    );
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _feeCtrl.dispose();
    _orderTotalCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  int _parsePiasters(String text) {
    final cleaned = text.trim().replaceAll(',', '');
    final val = double.tryParse(cleaned) ?? 0.0;
    return (val * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final feePiasters = _parsePiasters(_feeCtrl.text);
    final effectiveOrderTotalPiasters = widget.saleId != null
        ? widget.orderTotalPiasters
        : _parsePiasters(_orderTotalCtrl.text);
    final grandTotal = effectiveOrderTotalPiasters + feePiasters;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.delivery_dining_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'بيانات طلب التوصيل (دليفري)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order total banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('رقم الفاتورة: ${widget.orderRef}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('قيمة المنتجات: ${Money(effectiveOrderTotalPiasters).toDisplay()} ج.م', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('الإجمالي مع التوصيل', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(
                            '${Money(grandTotal).toDisplay()} ج.م',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                if (widget.saleId == null) ...[
                  TextFormField(
                    controller: _orderTotalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'قيمة الطلب / المنتجات (ج.م) *',
                      prefixIcon: const Icon(Icons.receipt_long_rounded, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'قيمة الطلب مطلوبة' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                ],

                // Customer Name
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'اسم العميل *',
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم العميل مطلوب' : null,
                ),
                const SizedBox(height: 10),

                // Customer Phone
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف للتواصل *',
                    prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'رقم الهاتف مطلوب' : null,
                ),
                const SizedBox(height: 10),

                // Delivery Address
                TextFormField(
                  controller: _addressCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'عنوان التوصيل بالتفصيل * (المنطقة، الشارع، العمارة، الشقة)',
                    prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'عنوان التوصيل مطلوب' : null,
                ),
                const SizedBox(height: 10),

                // Delivery Fee & Courier Row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _feeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'رسوم التوصيل (ج.م)',
                          prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCourierId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'طيار الدليفري (اختياري)',
                          prefixIcon: const Icon(Icons.two_wheeler_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('قيد الانتظار (لاحقاً)', overflow: TextOverflow.ellipsis),
                          ),
                          ...widget.couriers.map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (val) => setState(() => _selectedCourierId = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Payment Method with courier
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    const Text('طريقة الدفع:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ChoiceChip(
                      label: const Text('دفع عند الاستلام (COD)'),
                      selected: _paymentMethod == 'cod',
                      onSelected: (val) => setState(() => _paymentMethod = 'cod'),
                    ),
                    ChoiceChip(
                      label: const Text('مدفوع مسبقاً'),
                      selected: _paymentMethod == 'paid',
                      onSelected: (val) => setState(() => _paymentMethod = 'paid'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات إضافية للتوصيل (اختياري)',
                    prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;

            final feePiasters = _parsePiasters(_feeCtrl.text);
            final courierMatch = widget.couriers
                .where((c) => c.id == _selectedCourierId)
                .firstOrNull;

            final order = DeliveryOrderEntity(
              id: const Uuid().v4(),
              branchId: widget.branchId,
              saleId: widget.saleId,
              orderRef: widget.orderRef,
              customerId: widget.customerId,
              customerName: _nameCtrl.text.trim(),
              customerPhone: _phoneCtrl.text.trim(),
              deliveryAddress: _addressCtrl.text.trim(),
              courierId: _selectedCourierId,
              courierName: courierMatch?.name,
              deliveryFeePiasters: feePiasters,
              orderTotalPiasters: effectiveOrderTotalPiasters,
              paymentMethod: _paymentMethod,
              paymentStatus: _paymentMethod == 'paid' ? 'paid_online' : 'pending',
              status: _selectedCourierId != null ? 'out_for_delivery' : 'preparing',
              notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );

            Navigator.pop(context, order);
          },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('تأكيد طلب التوصيل'),
        ),
      ],
    );
  }
}
