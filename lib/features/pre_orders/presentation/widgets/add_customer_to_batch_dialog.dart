import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/pre_order_batch_entity.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/entities/pre_order_item_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class AddCustomerToBatchDialog extends StatefulWidget {
  final PreOrderBatchEntity batch;

  const AddCustomerToBatchDialog({super.key, required this.batch});

  static Future<void> show(BuildContext context, PreOrderBatchEntity batch) {
    return showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<PreOrdersCubit>(),
        child: AddCustomerToBatchDialog(batch: batch),
      ),
    );
  }

  @override
  State<AddCustomerToBatchDialog> createState() =>
      _AddCustomerToBatchDialogState();
}

class _FastItemData {
  String name;
  String desc;
  int qty;
  int costPricePiasters;
  int unitPricePiasters;
  String? url;

  _FastItemData({
    required this.name,
    required this.desc,
    required this.qty,
    required this.costPricePiasters,
    required this.unitPricePiasters,
    this.url,
  });

  int get totalPricePiasters => qty * unitPricePiasters;
  int get totalCostPiasters => qty * costPricePiasters;
  int get totalProfitPiasters => totalPricePiasters - totalCostPiasters;
}

class _AddCustomerToBatchDialogState extends State<AddCustomerToBatchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _defaultCommissionCtrl = TextEditingController(text: '50');
  String _paymentMethod = 'cash';

  // Fast entry fields
  final _fastNameCtrl = TextEditingController();
  final _fastDescCtrl = TextEditingController();
  final _fastQtyCtrl = TextEditingController(text: '1');
  final _fastCostCtrl = TextEditingController();
  final _fastCommissionCtrl = TextEditingController(text: '50');
  final _fastSalePriceCtrl = TextEditingController();
  final _fastUrlCtrl = TextEditingController();

  final _fastNameFocus = FocusNode();
  final _fastDescFocus = FocusNode();
  final _fastQtyFocus = FocusNode();
  final _fastCostFocus = FocusNode();
  final _fastCommissionFocus = FocusNode();
  final _fastSalePriceFocus = FocusNode();

  final List<_FastItemData> _items = [];
  bool _isSaving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _depositCtrl.dispose();
    _defaultCommissionCtrl.dispose();
    _fastNameCtrl.dispose();
    _fastDescCtrl.dispose();
    _fastQtyCtrl.dispose();
    _fastCostCtrl.dispose();
    _fastCommissionCtrl.dispose();
    _fastSalePriceCtrl.dispose();
    _fastUrlCtrl.dispose();
    _fastNameFocus.dispose();
    _fastDescFocus.dispose();
    _fastQtyFocus.dispose();
    _fastCostFocus.dispose();
    _fastCommissionFocus.dispose();
    _fastSalePriceFocus.dispose();
    super.dispose();
  }

  int get _totalSalePiasters =>
      _items.fold(0, (sum, it) => sum + it.totalPricePiasters);

  int get _totalCostPiasters =>
      _items.fold(0, (sum, it) => sum + it.totalCostPiasters);

  int get _totalProfitPiasters => _totalSalePiasters - _totalCostPiasters;

  int get _depositPiasters {
    final v = double.tryParse(_depositCtrl.text.trim()) ?? 0.0;
    return (v * 100).round();
  }

  void _onFastCostOrCommissionChanged() {
    final cost = double.tryParse(_fastCostCtrl.text.trim()) ?? 0.0;
    final comm = double.tryParse(_fastCommissionCtrl.text.trim()) ??
        double.tryParse(_defaultCommissionCtrl.text.trim()) ??
        0.0;
    final total = cost + comm;
    _fastSalePriceCtrl.text =
        total > 0 ? total.toStringAsFixed(1).replaceAll('.0', '') : '';
    setState(() {});
  }

  void _onFastSalePriceChanged(String val) {
    final sale = double.tryParse(val.trim()) ?? 0.0;
    final cost = double.tryParse(_fastCostCtrl.text.trim()) ?? 0.0;
    final comm = (sale - cost).clamp(0.0, double.infinity);
    _fastCommissionCtrl.text =
        comm > 0 ? comm.toStringAsFixed(1).replaceAll('.0', '') : '';
    setState(() {});
  }

  void _addFastItem() {
    final name = _fastNameCtrl.text.trim();
    if (name.isEmpty) {
      _fastNameFocus.requestFocus();
      return;
    }

    final desc = _fastDescCtrl.text.trim();
    final qty = int.tryParse(_fastQtyCtrl.text.trim()) ?? 1;
    final cost = double.tryParse(_fastCostCtrl.text.trim()) ?? 0.0;
    final comm = double.tryParse(_fastCommissionCtrl.text.trim()) ??
        double.tryParse(_defaultCommissionCtrl.text.trim()) ??
        50.0;
    final sale = double.tryParse(_fastSalePriceCtrl.text.trim()) ?? (cost + comm);
    final url = _fastUrlCtrl.text.trim();

    setState(() {
      _items.add(
        _FastItemData(
          name: name,
          desc: desc,
          qty: qty,
          costPricePiasters: (cost * 100).round(),
          unitPricePiasters: (sale * 100).round(),
          url: url.isNotEmpty ? url : null,
        ),
      );

      _fastNameCtrl.clear();
      _fastDescCtrl.clear();
      _fastQtyCtrl.text = '1';
      _fastCostCtrl.clear();
      _fastCommissionCtrl.text = _defaultCommissionCtrl.text.trim();
      _fastSalePriceCtrl.clear();
      _fastUrlCtrl.clear();
    });

    _fastNameFocus.requestFocus();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة صنف واحد على الأقل للعميل'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final uuid = const Uuid();
    final now = DateTime.now();
    final orderId = uuid.v4();

    final orderItems = _items.map((it) {
      return PreOrderItemEntity(
        id: uuid.v4(),
        preOrderId: orderId,
        productName: it.name,
        variantDescription: it.desc.isNotEmpty ? it.desc : null,
        quantity: it.qty,
        unitPricePiasters: it.unitPricePiasters,
        totalPricePiasters: it.totalPricePiasters,
        costPricePiasters: it.costPricePiasters,
        commissionPiasters: it.unitPricePiasters - it.costPricePiasters,
        itemUrl: it.url,
        status: 'active',
      );
    }).toList();

    final order = PreOrderEntity(
      id: orderId,
      branchId: widget.batch.branchId,
      orderNumber: '',
      batchId: widget.batch.id,
      customerName: _nameCtrl.text.trim(),
      customerPhone: _phoneCtrl.text.trim(),
      agentName: widget.batch.agentName,
      trackingNumber: widget.batch.trackingNumber,
      totalPiasters: _totalSalePiasters,
      allocatedShippingPiasters: 0,
      depositPiasters: _depositPiasters,
      createdAt: now,
      updatedAt: now,
      items: orderItems,
    );

    try {
      final ok = await context.read<PreOrdersCubit>().addCustomerToBatch(
            widget.batch.id,
            order,
            initialDepositPiasters: _depositPiasters,
            paymentMethod: _paymentMethod,
          );

      if (ok && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت إضافة العميل (${order.customerName}) وأصنافه للشحنة بنجاح',
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration _compactInput({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
      hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSale = _totalSalePiasters;
    final totalCost = _totalCostPiasters;
    final totalProfit = _totalProfitPiasters;
    final deposit = _depositPiasters;
    final remaining = (totalSale - deposit).clamp(0, totalSale);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750, maxHeight: 800),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
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
                      child: Icon(Icons.person_add_alt_1_rounded,
                          color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إضافة عميل وأصنافه إلى ${widget.batch.batchNumber}',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const Text(
                            'التجميع التدريجي للشحنة المفتوحة طوال الأسبوع',
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

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer info
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _nameCtrl,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                                decoration: _compactInput(label: 'اسم العميل *', hint: 'سارة محمد'),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب اسم العميل' : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                                decoration: _compactInput(label: 'رقم الهاتف (واتساب) *', hint: '01xxxxxxxxx'),
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب الهاتف' : null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              child: TextFormField(
                                controller: _defaultCommissionCtrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                                decoration: _compactInput(label: 'عمولة افتراضية'),
                                onChanged: (v) => _fastCommissionCtrl.text = v,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Fast Entry Row
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
                                children: [
                                  Icon(Icons.bolt_rounded, size: 16, color: AppColors.primary),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'إدخال الأصناف السريع (بالـ Enter):',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: TextFormField(
                                      controller: _fastNameCtrl,
                                      focusNode: _fastNameFocus,
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                                      decoration: _compactInput(label: 'اسم الصنف أو كود المنتج (SKU / Code) *', hint: 'فستان، بلوزة، كود...'),
                                      onFieldSubmitted: (_) => _fastDescFocus.requestFocus(),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: _fastDescCtrl,
                                      focusNode: _fastDescFocus,
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                                      decoration: _compactInput(label: 'المقاس/اللون', hint: 'L - أسود'),
                                      onFieldSubmitted: (_) => _fastQtyFocus.requestFocus(),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 65,
                                    child: TextFormField(
                                      controller: _fastQtyCtrl,
                                      focusNode: _fastQtyFocus,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                                      decoration: _compactInput(label: 'الكمية'),
                                      onFieldSubmitted: (_) => _fastCostFocus.requestFocus(),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _fastCostCtrl,
                                      focusNode: _fastCostFocus,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                                      decoration: _compactInput(label: 'سعر الجملة (التكلفة) *'),
                                      onChanged: (_) => _onFastCostOrCommissionChanged(),
                                      onFieldSubmitted: (_) => _fastCommissionFocus.requestFocus(),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _fastCommissionCtrl,
                                      focusNode: _fastCommissionFocus,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                                      decoration: _compactInput(label: 'عمولتك'),
                                      onChanged: (_) => _onFastCostOrCommissionChanged(),
                                      onFieldSubmitted: (_) => _fastSalePriceFocus.requestFocus(),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _fastSalePriceCtrl,
                                      focusNode: _fastSalePriceFocus,
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                                      decoration: _compactInput(label: 'سعر البيع النهائي للعميل *'),
                                      onChanged: _onFastSalePriceChanged,
                                      onFieldSubmitted: (_) => _addFastItem(),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton.icon(
                                    onPressed: _addFastItem,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.add_rounded, size: 16),
                                    label: const Text('إضافة [Enter]', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // List of added items
                        if (_items.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.outlineVariant),
                            ),
                            child: Text(
                              'لم يتم إضافة أصناف بعد. أدخل الصنف واضغط Enter',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Colors.grey.shade600),
                            ),
                          )
                        else
                          ...List.generate(_items.length, (idx) {
                            final it = _items[idx];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.outlineVariant),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
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
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      '${it.name} ${it.desc.isNotEmpty ? "(${it.desc})" : ""}',
                                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${it.qty} × ${Money(it.unitPricePiasters).toDisplay()} ج',
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '+${Money(it.totalProfitPiasters).toDisplay()} ج ربح',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                    onPressed: () => setState(() => _items.removeAt(idx)),
                                  ),
                                ],
                              ),
                            );
                          }),

                        const SizedBox(height: 14),

                        // Deposit and payment method
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _depositCtrl,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                                decoration: _compactInput(label: 'العربون المدفوع الآن (ج.م)', hint: '0.00'),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                initialValue: _paymentMethod,
                                decoration: _compactInput(label: 'طريقة دفع العربون'),
                                items: const [
                                  DropdownMenuItem(value: 'cash', child: Text('كاش (نقداً)')),
                                  DropdownMenuItem(value: 'instapay', child: Text('انستاباي')),
                                  DropdownMenuItem(value: 'vodafone_cash', child: Text('فودافون كاش')),
                                  DropdownMenuItem(value: 'card', child: Text('فيزا / بطاقة')),
                                ],
                                onChanged: (v) => setState(() => _paymentMethod = v ?? 'cash'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),
                const Divider(height: 1, color: AppColors.outlineVariant),
                const SizedBox(height: 10),

                // Financial Summary Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _summaryMetric('إجمالي العميل', Money(totalSale).toDisplay(), AppColors.onSurface),
                      _summaryMetric('سعر الجملة', Money(totalCost).toDisplay(), AppColors.onSurfaceVariant),
                      _summaryMetric('صافي الربح', '+${Money(totalProfit).toDisplay()}', AppColors.primary),
                      _summaryMetric('العربون', Money(deposit).toDisplay(), AppColors.success),
                      _summaryMetric('المتبقي', Money(remaining).toDisplay(), remaining > 0 ? AppColors.error : AppColors.success),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: const Text(
                        'إضافة للشحنة',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppColors.onSurfaceVariant)),
        Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

