import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/domain/entities/customer_entity.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/entities/pre_order_item_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class CreatePreOrderDialog extends StatefulWidget {
  final CustomerEntity? initialCustomer;

  const CreatePreOrderDialog({super.key, this.initialCustomer});

  @override
  State<CreatePreOrderDialog> createState() => _CreatePreOrderDialogState();
}

class _ItemEntry {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController(); // size, color
  final urlCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final priceCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    urlCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

class _CreatePreOrderDialogState extends State<CreatePreOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  CustomerEntity? _selectedCustomer;
  DateTime? _expectedDeliveryDate;
  String _paymentMethod = 'cash'; // 'cash', 'instapay', 'vodafone_cash', 'card'
  final List<_ItemEntry> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialCustomer != null) {
      _selectedCustomer = widget.initialCustomer;
      _customerNameCtrl.text = widget.initialCustomer!.name;
      _customerPhoneCtrl.text = widget.initialCustomer!.phone;
    }
    _addItem();
  }

  void _addItem() {
    setState(() {
      _items.add(_ItemEntry());
    });
  }

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      final item = _items.removeAt(index);
      item.dispose();
    });
  }

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _depositCtrl.dispose();
    _notesCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  int get _calculatedTotalPiasters {
    int total = 0;
    for (final item in _items) {
      final qty = int.tryParse(item.qtyCtrl.text.trim()) ?? 1;
      final priceNum = double.tryParse(item.priceCtrl.text.trim()) ?? 0.0;
      final piasters = (priceNum * 100).round();
      total += (qty * piasters);
    }
    return total;
  }

  int get _depositPiasters {
    final depNum = double.tryParse(_depositCtrl.text.trim()) ?? 0.0;
    return (depNum * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final totalPiasters = _calculatedTotalPiasters;
    final depositPiasters = _depositPiasters;
    final remainingPiasters = (totalPiasters - depositPiasters).clamp(0, totalPiasters);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 850),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.bookmark_add_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تسجيل أوردر حجز مسبق جديد',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            'إدخال بيانات العميل، الأصناف المطلوبة، والعربون المستلم فوراً في الخزينة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(height: 28, color: AppColors.outlineVariant),

                // Form Content
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Customer Section
                        _buildSectionHeader('بيانات العميل', Icons.person_rounded),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _customerNameCtrl,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                decoration: _inputDecoration(
                                  label: 'اسم العميل *',
                                  hint: 'مثال: سارة محمد أو أحمد علي',
                                  icon: Icons.person_outline_rounded,
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? 'مطلوب اسم العميل' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _customerPhoneCtrl,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                decoration: _inputDecoration(
                                  label: 'رقم الهاتف (واتساب) *',
                                  hint: '01xxxxxxxxx',
                                  icon: Icons.phone_android_rounded,
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty) ? 'مطلوب رقم الهاتف' : null,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Items Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildSectionHeader('أصناف الحجز والطلبات الخاصة', Icons.shopping_bag_rounded),
                            TextButton.icon(
                              onPressed: _addItem,
                              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                              label: const Text(
                                '+ إضافة صنف آخر',
                                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Items List
                        ...List.generate(_items.length, (idx) {
                          final item = _items[idx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.outlineVariant),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                      child: Text(
                                        '${idx + 1}',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 3,
                                      child: TextFormField(
                                        controller: item.nameCtrl,
                                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                                        decoration: _compactInput(
                                          label: 'اسم الصنف أو كود شي إن *',
                                          hint: 'مثال: فستان سهرة مخملي / موديل #9482',
                                        ),
                                        validator: (v) => (v == null || v.trim().isEmpty)
                                            ? 'اسم الصنف مطلوب'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: item.descCtrl,
                                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                                        decoration: _compactInput(
                                          label: 'المقاس / اللون / مواصفات',
                                          hint: 'L - أسود أو تفصيل خاص',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 65,
                                      child: TextFormField(
                                        controller: item.qtyCtrl,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        decoration: _compactInput(label: 'الكمية'),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 105,
                                      child: TextFormField(
                                        controller: item.priceCtrl,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        decoration: _compactInput(label: 'سعر البيع (ج.م)'),
                                        onChanged: (_) => setState(() {}),
                                        validator: (v) =>
                                            (v == null || double.tryParse(v) == null)
                                                ? 'السعر مطلوب'
                                                : null,
                                      ),
                                    ),
                                    if (_items.length > 1) ...[
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded,
                                            size: 20, color: AppColors.error),
                                        onPressed: () => _removeItem(idx),
                                        tooltip: 'حذف الصنف',
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: item.urlCtrl,
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5),
                                  decoration: _compactInput(
                                    label: 'رابط صفحة المنتج على الإنترنت (اختياري)',
                                    hint: 'https://shein.com/... أو رابط المورد',
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 16),

                        // Financial & Deposit Section
                        _buildSectionHeader('العربون والماليات', Icons.payments_rounded),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _depositCtrl,
                                keyboardType: TextInputType.number,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                                decoration: _inputDecoration(
                                  label: 'العربون المدفوع الآن (ج.م)',
                                  hint: '0.00',
                                  icon: Icons.attach_money_rounded,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                initialValue: _paymentMethod,
                                decoration: _inputDecoration(
                                  label: 'طريقة دفع العربون',
                                  icon: Icons.payment_rounded,
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'cash', child: Text('كاش (نقداً في الخزينة)')),
                                  DropdownMenuItem(value: 'instapay', child: Text('انستاباي (InstaPay)')),
                                  DropdownMenuItem(value: 'vodafone_cash', child: Text('فودافون كاش / محفظة')),
                                  DropdownMenuItem(value: 'card', child: Text('فيزا / بطاقة بنكية')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _paymentMethod = val);
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Expected Delivery Date & Notes
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now().add(const Duration(days: 7)),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) {
                                    setState(() => _expectedDeliveryDate = picked);
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: InputDecorator(
                                  decoration: _inputDecoration(
                                    label: 'تاريخ الاستلام المتوقع',
                                    icon: Icons.calendar_today_rounded,
                                  ),
                                  child: Text(
                                    _expectedDeliveryDate != null
                                        ? '${_expectedDeliveryDate!.year}-${_expectedDeliveryDate!.month.toString().padLeft(2, '0')}-${_expectedDeliveryDate!.day.toString().padLeft(2, '0')}'
                                        : 'تحديد موعد الوصول المتوقع (اختياري)',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12.5,
                                      color: _expectedDeliveryDate != null
                                          ? AppColors.onSurface
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _notesCtrl,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                decoration: _inputDecoration(
                                  label: 'ملاحظات إضافية',
                                  hint: 'أية تعليمات خاصة بالشحن أو المقاسات',
                                  icon: Icons.notes_rounded,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Financial Summary Banner
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildSummaryItem('إجمالي الطلب', Money(totalPiasters).toDisplay(), AppColors.onSurface),
                              Container(width: 1, height: 32, color: AppColors.outlineVariant),
                              _buildSummaryItem('العربون المقبوض', Money(depositPiasters).toDisplay(), AppColors.primary),
                              Container(width: 1, height: 32, color: AppColors.outlineVariant),
                              _buildSummaryItem(
                                'المتبقي عند الاستلام',
                                Money(remainingPiasters).toDisplay(),
                                remainingPiasters > 0 ? AppColors.error : AppColors.success,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Footer Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _submit,
                      icon: const Icon(Icons.check_rounded, size: 20),
                      label: const Text(
                        'تأكيد وحفظ أوردر الحجز',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          '$value ج.م',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({required String label, String? hint, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.outlineVariant),
      ),
    );
  }

  InputDecoration _compactInput({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.outlineVariant),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final totalPiasters = _calculatedTotalPiasters;
    if (totalPiasters <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد أسعار أصناف الحجز بحيث يكون الإجمالي أكبر من صفر'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final depositPiasters = _depositPiasters;
    if (depositPiasters > totalPiasters) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('العربون المدفوع لا يمكن أن يتجاوز إجمالي الأوردر'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final items = <PreOrderItemEntity>[];
    for (final item in _items) {
      final name = item.nameCtrl.text.trim();
      if (name.isEmpty) continue;
      final desc = item.descCtrl.text.trim();
      final url = item.urlCtrl.text.trim();
      final qty = int.tryParse(item.qtyCtrl.text.trim()) ?? 1;
      final priceNum = double.tryParse(item.priceCtrl.text.trim()) ?? 0.0;
      final unitPricePiasters = (priceNum * 100).round();
      final itemTotalPiasters = qty * unitPricePiasters;

      items.add(PreOrderItemEntity(
        id: const Uuid().v4(),
        preOrderId: '',
        productName: name,
        variantDescription: desc.isNotEmpty ? desc : null,
        itemUrl: url.isNotEmpty ? url : null,
        quantity: qty,
        unitPricePiasters: unitPricePiasters,
        totalPricePiasters: itemTotalPiasters,
      ));
    }

    final order = PreOrderEntity(
      id: const Uuid().v4(),
      branchId: '',
      orderNumber: '',
      customerId: _selectedCustomer?.id,
      customerName: _customerNameCtrl.text.trim(),
      customerPhone: _customerPhoneCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      expectedDeliveryDate: _expectedDeliveryDate,
      totalPiasters: totalPiasters,
      depositPiasters: depositPiasters,
      status: PreOrderStatuses.pendingProcessing,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      items: items,
    );

    final cubit = context.read<PreOrdersCubit>();
    final ok = await cubit.createPreOrder(
      order,
      initialDepositPiasters: depositPiasters,
      paymentMethod: _paymentMethod,
    );

    if (ok && mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تسجيل طلب الحجز بنجاح بقيمة ${Money(totalPiasters).toDisplay()} ج.م وعربون ${Money(depositPiasters).toDisplay()} ج.م',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}
