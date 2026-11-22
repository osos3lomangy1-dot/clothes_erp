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
  late TextEditingController _waybillCtrl;
  late TextEditingController _notesCtrl;

  String? _selectedCourierId;
  String _paymentMethod = 'cod'; // 'cod' or 'paid'
  String _shippingFeePayer = 'store_collected'; // 'store_collected' or 'customer_direct'
  String? _selectedZone;

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
    _waybillCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _feeCtrl.dispose();
    _orderTotalCtrl.dispose();
    _waybillCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  int _parsePiasters(String text) {
    final cleaned = text.trim().replaceAll(',', '');
    final val = double.tryParse(cleaned) ?? 0.0;
    return (val * 100).round();
  }

  DeliveryCourierEntity? get _selectedCourier {
    if (_selectedCourierId == null) return null;
    return widget.couriers.where((c) => c.id == _selectedCourierId).firstOrNull;
  }

  void _applyZone(String zoneName, double fee) {
    setState(() {
      _selectedZone = zoneName;
      _feeCtrl.text = fee.toStringAsFixed(2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final feePiasters = _parsePiasters(_feeCtrl.text);
    final effectiveOrderTotalPiasters = widget.saleId != null
        ? widget.orderTotalPiasters
        : _parsePiasters(_orderTotalCtrl.text);

    // If customer direct, shipping is collected by the shipping company, but total for client is goods + shipping
    final grandTotal = effectiveOrderTotalPiasters + feePiasters;
    final courier = _selectedCourier;
    final isShippingCompany = courier?.isShippingCompany ?? false;

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
            child: Icon(
              isShippingCompany ? Icons.local_shipping_rounded : Icons.delivery_dining_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isShippingCompany ? 'بيانات الشحن الخارجي (شركة شحن)' : 'بيانات طلب التوصيل (دليفري)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
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
                          Text('قيمة المنتجات: ${Money(effectiveOrderTotalPiasters).toDisplay()} ج.م', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          if (_shippingFeePayer == 'customer_direct')
                            const Text(
                              'نمط الشحن: يدفع للشركة مباشرة (صافي للمحل 100%)',
                              style: TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('المطلوب من العميل', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                          Text(
                            '${Money(grandTotal).toDisplay()} ج.م',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Customer Name & Phone
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'اسم العميل *',
                          prefixIcon: const Icon(Icons.person_outline, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم العميل مطلوب' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف *',
                          prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'الهاتف مطلوب' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Address
                TextFormField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                    labelText: 'العنوان بالتفصيل (الشارع، العمارة، الشقة) *',
                    prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'العنوان مطلوب' : null,
                ),
                const SizedBox(height: 10),

                // Quick Zone Selection Chips
                const Text('مناطق التوصيل السريعة:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('داخل الحي (20 ج.م)', style: TextStyle(fontSize: 11)),
                      selected: _selectedZone == 'local',
                      onSelected: (_) => _applyZone('local', 20.0),
                    ),
                    ChoiceChip(
                      label: const Text('أطراف المدينة (35 ج.م)', style: TextStyle(fontSize: 11)),
                      selected: _selectedZone == 'city_edge',
                      onSelected: (_) => _applyZone('city_edge', 35.0),
                    ),
                    ChoiceChip(
                      label: const Text('شحن محافظات (60 ج.م)', style: TextStyle(fontSize: 11)),
                      selected: _selectedZone == 'governorates',
                      onSelected: (_) => _applyZone('governorates', 60.0),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Delivery Fee & Courier / Shipping Company
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _feeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'رسوم الشحن (ج.م) *',
                          prefixIcon: const Icon(Icons.attach_money_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'أدخل رسوم الشحن' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCourierId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'الطيار / شركة الشحن',
                          prefixIcon: Icon(
                            isShippingCompany ? Icons.local_shipping_outlined : Icons.two_wheeler_outlined,
                            size: 20,
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('قيد الانتظار (لاحقاً)', overflow: TextOverflow.ellipsis),
                          ),
                          ...widget.couriers.map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Row(
                                  children: [
                                    Icon(
                                      c.isShippingCompany ? Icons.apartment_rounded : Icons.two_wheeler_rounded,
                                      size: 16,
                                      color: c.isShippingCompany ? Colors.indigo : AppColors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${c.name} (${c.isShippingCompany ? "شركة شحن" : "طيار"})',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedCourierId = val;
                            final match = widget.couriers.where((c) => c.id == val).firstOrNull;
                            if (match != null && match.isShippingCompany && match.defaultRatePiasters != null) {
                              _feeCtrl.text = (match.defaultRatePiasters! / 100.0).toStringAsFixed(2);
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Shipping Company Specific Settings (Waybill & Payer)
                if (isShippingCompany) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'إعدادات شركة الشحن والبوليصة:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('delivery_waybill_input'),
                          controller: _waybillCtrl,
                          decoration: InputDecoration(
                            labelText: 'رقم بوليصة الشحن (Waybill / Tracking No)',
                            hintText: 'مثال: BOSTA-98234 أو ARAMEX-0192',
                            prefixIcon: const Icon(Icons.receipt_long_rounded, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('جهة تحصيل تكلفة الشحن:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('محصل للمتجر (Store Collected)', style: TextStyle(fontSize: 11)),
                                selected: _shippingFeePayer == 'store_collected',
                                onSelected: (_) => setState(() => _shippingFeePayer = 'store_collected'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ChoiceChip(
                                label: const Text('مباشر للشركة (Direct to Courier)', style: TextStyle(fontSize: 11)),
                                selected: _shippingFeePayer == 'customer_direct',
                                onSelected: (_) => setState(() => _shippingFeePayer = 'customer_direct'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Payment Method
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
            final courierMatch = _selectedCourier;

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
              providerType: courierMatch?.providerType ?? 'in_house',
              shippingFeePayer: _shippingFeePayer,
              waybillNumber: _waybillCtrl.text.trim().isEmpty ? null : _waybillCtrl.text.trim(),
              shippingCostPiasters: isShippingCompany ? (courierMatch?.defaultRatePiasters ?? feePiasters) : null,
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
