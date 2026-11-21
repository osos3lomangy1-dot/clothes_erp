import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/domain/entities/customer_entity.dart';
import '../../data/services/pre_order_excel_service.dart';
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
  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl; // المقاس / اللون
  final TextEditingController urlCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl; // تكلفة المندوب
  final TextEditingController commissionCtrl; // عمولة التاجر
  final TextEditingController priceCtrl; // سعر البيع للعميل

  _ItemEntry({
    String? id,
    String name = '',
    String desc = '',
    String url = '',
    String qty = '1',
    String cost = '',
    String commission = '',
    String price = '',
  })  : id = id ?? const Uuid().v4(),
        nameCtrl = TextEditingController(text: name),
        descCtrl = TextEditingController(text: desc),
        urlCtrl = TextEditingController(text: url),
        qtyCtrl = TextEditingController(text: qty),
        costCtrl = TextEditingController(text: cost),
        commissionCtrl = TextEditingController(text: commission),
        priceCtrl = TextEditingController(text: price);

  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    urlCtrl.dispose();
    qtyCtrl.dispose();
    costCtrl.dispose();
    commissionCtrl.dispose();
    priceCtrl.dispose();
  }
}

class _CreatePreOrderDialogState extends State<CreatePreOrderDialog> {
  final _formKey = GlobalKey<FormState>();

  // بيانات العميل
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();

  // بيانات المندوب والشحن
  final _agentNameCtrl = TextEditingController();
  final _trackingNumberCtrl = TextEditingController();
  final _defaultCommissionCtrl = TextEditingController(text: '50');

  // بيانات الحساب والعربون
  final _depositCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  CustomerEntity? _selectedCustomer;
  DateTime? _expectedDeliveryDate;
  String _paymentMethod = 'cash'; // 'cash', 'instapay', 'vodafone_cash', 'card'

  // قائمة الأصناف المضافة للأوردر
  final List<_ItemEntry> _items = [];

  // حقول شريط الإدخال السريع بالـ Enter
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

  bool _isImportingExcel = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCustomer != null) {
      _selectedCustomer = widget.initialCustomer;
      _customerNameCtrl.text = widget.initialCustomer!.name;
      _customerPhoneCtrl.text = widget.initialCustomer!.phone;
    }
  }

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _agentNameCtrl.dispose();
    _trackingNumberCtrl.dispose();
    _defaultCommissionCtrl.dispose();
    _depositCtrl.dispose();
    _notesCtrl.dispose();

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

    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  // --- الحسابات اللحظية للإدخال السريع ---

  void _onDefaultCommissionChanged(String val) {
    final dComm = double.tryParse(val.trim()) ?? 0.0;
    _fastCommissionCtrl.text = dComm > 0 ? dComm.toStringAsFixed(0) : '';
    _onFastCostOrCommissionChanged();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى كتابة اسم الصنف أو كود شي إن'),
          backgroundColor: AppColors.error,
          duration: Duration(seconds: 2),
        ),
      );
      _fastNameFocus.requestFocus();
      return;
    }

    final desc = _fastDescCtrl.text.trim();
    final qty = _fastQtyCtrl.text.trim().isNotEmpty ? _fastQtyCtrl.text.trim() : '1';
    final cost = _fastCostCtrl.text.trim();
    final comm = _fastCommissionCtrl.text.trim().isNotEmpty
        ? _fastCommissionCtrl.text.trim()
        : _defaultCommissionCtrl.text.trim();
    final price = _fastSalePriceCtrl.text.trim().isNotEmpty
        ? _fastSalePriceCtrl.text.trim()
        : ((double.tryParse(cost) ?? 0) + (double.tryParse(comm) ?? 0)).toString();
    final url = _fastUrlCtrl.text.trim();

    setState(() {
      _items.add(
        _ItemEntry(
          name: name,
          desc: desc,
          qty: qty,
          cost: cost,
          commission: comm,
          price: price,
          url: url,
        ),
      );

      // إعادة ضبط حقول الإدخال السريع
      _fastNameCtrl.clear();
      _fastDescCtrl.clear();
      _fastQtyCtrl.text = '1';
      _fastCostCtrl.clear();
      _fastCommissionCtrl.text = _defaultCommissionCtrl.text.trim();
      _fastSalePriceCtrl.clear();
      _fastUrlCtrl.clear();
    });

    // إعادة التركيز على اسم الصنف للإدخال التالي فوراً
    _fastNameFocus.requestFocus();
  }

  void _removeItem(int index) {
    setState(() {
      final item = _items.removeAt(index);
      item.dispose();
    });
  }

  // --- حساب الإجماليات المالية للأوردر ---

  int get _calculatedTotalSalePiasters {
    int total = 0;
    for (final item in _items) {
      final qty = int.tryParse(item.qtyCtrl.text.trim()) ?? 1;
      final priceNum = double.tryParse(item.priceCtrl.text.trim()) ?? 0.0;
      total += (qty * (priceNum * 100).round());
    }
    return total;
  }

  int get _calculatedTotalCostPiasters {
    int total = 0;
    for (final item in _items) {
      final qty = int.tryParse(item.qtyCtrl.text.trim()) ?? 1;
      final costNum = double.tryParse(item.costCtrl.text.trim()) ?? 0.0;
      total += (qty * (costNum * 100).round());
    }
    return total;
  }

  int get _calculatedTotalProfitPiasters {
    final profit = _calculatedTotalSalePiasters - _calculatedTotalCostPiasters;
    return profit.clamp(0, _calculatedTotalSalePiasters);
  }

  int get _depositPiasters {
    final depNum = double.tryParse(_depositCtrl.text.trim()) ?? 0.0;
    return (depNum * 100).round();
  }

  // --- استيراد وتصدير الإكسيل ---

  Future<void> _handleImportExcel() async {
    setState(() => _isImportingExcel = true);
    try {
      final defaultComm =
          (double.tryParse(_defaultCommissionCtrl.text.trim()) ?? 50.0) * 100;
      final imported = await PreOrderExcelService.pickAndImportItems(
        defaultCommissionPiasters: defaultComm.round(),
      );

      if (imported != null && imported.isNotEmpty && mounted) {
        setState(() {
          for (final it in imported) {
            _items.add(
              _ItemEntry(
                id: it.id,
                name: it.productName,
                desc: it.variantDescription ?? '',
                qty: it.quantity.toString(),
                cost: (it.costPricePiasters / 100).toStringAsFixed(1).replaceAll('.0', ''),
                commission: (it.commissionPiasters / 100).toStringAsFixed(1).replaceAll('.0', ''),
                price: (it.unitPricePiasters / 100).toStringAsFixed(1).replaceAll('.0', ''),
                url: it.itemUrl ?? '',
              ),
            );
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم استيراد ${imported.length} صنف بنجاح من ملف الإكسيل'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء قراءة ملف الإكسيل: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImportingExcel = false);
    }
  }

  Future<void> _handleDownloadTemplate() async {
    try {
      final path = await PreOrderExcelService.downloadTemplate();
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ نموذج الإكسيل بنجاح في:\n$path'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تحميل النموذج: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSalePiasters = _calculatedTotalSalePiasters;
    final totalCostPiasters = _calculatedTotalCostPiasters;
    final totalProfitPiasters = _calculatedTotalProfitPiasters;
    final depositPiasters = _depositPiasters;
    final remainingPiasters =
        (totalSalePiasters - depositPiasters).clamp(0, totalSalePiasters);

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 900),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. ترويسة الحوار
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
                            'تسجيل أوردر حجز مسبق ووساطة شي إن',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            'تسعير تكلفة المندوب، عمولة التاجر، إدخال سريع بالإنتر، ودعم شيتات الإكسيل',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11.5,
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
                const Divider(height: 24, color: AppColors.outlineVariant),

                // 2. محتوى النموذج
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // قسم العميل
                        _buildSectionHeader('بيانات العميل', Icons.person_rounded),
                        const SizedBox(height: 8),
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
                            const SizedBox(width: 10),
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

                        const SizedBox(height: 16),

                        // قسم المندوب والشحن والعمولة الافتراضية
                        _buildSectionHeader('بيانات وسيط الشراء / المندوب والتتبع', Icons.local_shipping_rounded),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _agentNameCtrl,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                decoration: _inputDecoration(
                                  label: 'اسم المندوب / الوسيط (اختياري)',
                                  hint: 'مثال: كابتن أحمد / وسيط شي إن',
                                  icon: Icons.badge_outlined,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _trackingNumberCtrl,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                                decoration: _inputDecoration(
                                  label: 'رقم البوليصة / كود التتبع (Tracking #)',
                                  hint: 'مثال: SH-9284102',
                                  icon: Icons.tag_rounded,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _defaultCommissionCtrl,
                                keyboardType: TextInputType.number,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                                decoration: _inputDecoration(
                                  label: 'عمولتك الافتراضية (ج.م)',
                                  hint: '50',
                                  icon: Icons.monetization_on_outlined,
                                ),
                                onChanged: _onDefaultCommissionChanged,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // شريط الإدخال السريع مع أزرار الإكسيل
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildSectionHeader('إضافة أصناف الحجز (سريع بالـ Enter)', Icons.bolt_rounded),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed: _handleDownloadTemplate,
                                  icon: const Icon(Icons.download_rounded, size: 16),
                                  label: const Text(
                                    'تحميل نموذج إكسيل',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                ElevatedButton.icon(
                                  onPressed: _isImportingExcel ? null : _handleImportExcel,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: _isImportingExcel
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : const Icon(Icons.upload_file_rounded, size: 16),
                                  label: const Text(
                                    'استيراد من إكسيل',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // سطر الإدخال السريع بالـ Enter
                        _buildFastEntryBox(),

                        const SizedBox(height: 14),

                        // جدول / قائمة الأصناف المضافة
                        if (_items.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.shopping_bag_outlined, size: 36, color: Colors.grey.shade400),
                                const SizedBox(height: 6),
                                Text(
                                  'لم يتم إضافة أصناف بعد. استخدم سطر الإدخال السريع أعلاه أو زر استيراد إكسيل',
                                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          )
                        else
                          ...List.generate(_items.length, (idx) => _buildItemRow(idx)),

                        const SizedBox(height: 16),

                        // قسم العربون وطريقة الدفع
                        _buildSectionHeader('العربون والماليات والتسليم', Icons.payments_rounded),
                        const SizedBox(height: 8),
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
                            const SizedBox(width: 10),
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

                        const SizedBox(height: 10),

                        // تاريخ الاستلام والملاحظات
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
                                borderRadius: BorderRadius.circular(10),
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
                                      fontSize: 12,
                                      color: _expectedDeliveryDate != null
                                          ? AppColors.onSurface
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _notesCtrl,
                                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                                decoration: _inputDecoration(
                                  label: 'ملاحظات إضافية',
                                  hint: 'أية تعليمات خاصة بالشحن أو الاستلام',
                                  icon: Icons.notes_rounded,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // 3. شريط الملخص المالي أسفل النموذج (5 خانات ذكية)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildSummaryItem('إجمالي العميل', Money(totalSalePiasters).toDisplay(), AppColors.onSurface),
                              Container(width: 1, height: 30, color: AppColors.outlineVariant),
                              _buildSummaryItem('تكلفة المندوب', Money(totalCostPiasters).toDisplay(), Colors.blueGrey.shade700),
                              Container(width: 1, height: 30, color: AppColors.outlineVariant),
                              _buildSummaryItem('صافي ربحك', '+${Money(totalProfitPiasters).toDisplay()}', AppColors.primary),
                              Container(width: 1, height: 30, color: AppColors.outlineVariant),
                              _buildSummaryItem('العربون المقبوض', Money(depositPiasters).toDisplay(), AppColors.success),
                              Container(width: 1, height: 30, color: AppColors.outlineVariant),
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

                const SizedBox(height: 14),

                // 4. أزرار الإجراء السفلية
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
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _submit,
                      icon: const Icon(Icons.check_rounded, size: 20),
                      label: const Text(
                        'تأكيد وحفظ أوردر الحجز',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13.5),
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

  // --- سطر الإدخال السريع الذكي (Fast Inline Entry Box) ---

  Widget _buildFastEntryBox() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          // السطر الأول: الاسم والمقاس والكمية
          Row(
            children: [
              // اسم الصنف أو الرابط
              Expanded(
                flex: 4,
                child: TextFormField(
                  controller: _fastNameCtrl,
                  focusNode: _fastNameFocus,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  decoration: _compactInput(
                    label: 'اسم الصنف أو كود شي إن *',
                    hint: 'اكتب واضغط Enter...',
                  ),
                  onFieldSubmitted: (_) => _fastDescFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),

              // المقاس واللون
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _fastDescCtrl,
                  focusNode: _fastDescFocus,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  decoration: _compactInput(
                    label: 'المقاس/اللون',
                    hint: 'L - أسود',
                  ),
                  onFieldSubmitted: (_) => _fastQtyFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),

              // الكمية
              SizedBox(
                width: 75,
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

          // السطر الثاني: التكلفة والعمولة وسعر البيع وزر الإضافة
          Row(
            children: [
              // تكلفة المندوب
              Expanded(
                child: TextFormField(
                  controller: _fastCostCtrl,
                  focusNode: _fastCostFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: _compactInput(label: 'تكلفة المندوب'),
                  onChanged: (_) => _onFastCostOrCommissionChanged(),
                  onFieldSubmitted: (_) => _fastCommissionFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),

              // العمولة
              Expanded(
                child: TextFormField(
                  controller: _fastCommissionCtrl,
                  focusNode: _fastCommissionFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                  decoration: _compactInput(label: 'العمولة'),
                  onChanged: (_) => _onFastCostOrCommissionChanged(),
                  onFieldSubmitted: (_) => _fastSalePriceFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),

              // سعر البيع للعميل
              Expanded(
                child: TextFormField(
                  controller: _fastSalePriceCtrl,
                  focusNode: _fastSalePriceFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: _compactInput(label: 'سعر البيع'),
                  onChanged: _onFastSalePriceChanged,
                  onFieldSubmitted: (_) => _addFastItem(),
                ),
              ),
              const SizedBox(width: 8),

              // زر إضافة بالـ Enter
              ElevatedButton.icon(
                onPressed: _addFastItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('إضافة [Enter]', style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // رابط المنتج على الإنترنت (اختياري)
          TextFormField(
            controller: _fastUrlCtrl,
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
            decoration: _compactInput(
              label: 'رابط المنتج على الموقع (شي إن / المورد - اختياري)',
              hint: 'https://shein.com/...',
            ),
            onFieldSubmitted: (_) => _addFastItem(),
          ),
        ],
      ),
    );
  }

  // --- كارت الصنف في القائمة المضافة ---

  Widget _buildItemRow(int idx) {
    final item = _items[idx];
    final qty = int.tryParse(item.qtyCtrl.text.trim()) ?? 1;
    final costNum = double.tryParse(item.costCtrl.text.trim()) ?? 0.0;
    final priceNum = double.tryParse(item.priceCtrl.text.trim()) ?? 0.0;
    final totalCost = qty * costNum;
    final totalSale = qty * priceNum;
    final totalProfit = totalSale - totalCost;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Text(
                  '${idx + 1}',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // اسم الصنف
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: item.nameCtrl,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  decoration: _compactInput(label: 'اسم الصنف'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 6),

              // المقاس / اللون
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: item.descCtrl,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  decoration: _compactInput(label: 'المقاس/اللون'),
                ),
              ),
              const SizedBox(width: 6),

              // الكمية
              SizedBox(
                width: 50,
                child: TextFormField(
                  controller: item.qtyCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: _compactInput(label: 'الكمية'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 6),

              // تكلفة المندوب
              SizedBox(
                width: 80,
                child: TextFormField(
                  controller: item.costCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: _compactInput(label: 'تكلفة المندوب'),
                  onChanged: (val) {
                    final c = double.tryParse(val) ?? 0;
                    final comm = double.tryParse(item.commissionCtrl.text) ?? 0;
                    item.priceCtrl.text = (c + comm).toStringAsFixed(1).replaceAll('.0', '');
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 6),

              // العمولة
              SizedBox(
                width: 70,
                child: TextFormField(
                  controller: item.commissionCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                  decoration: _compactInput(label: 'العمولة'),
                  onChanged: (val) {
                    final comm = double.tryParse(val) ?? 0;
                    final c = double.tryParse(item.costCtrl.text) ?? 0;
                    item.priceCtrl.text = (c + comm).toStringAsFixed(1).replaceAll('.0', '');
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 6),

              // سعر البيع للعميل
              SizedBox(
                width: 80,
                child: TextFormField(
                  controller: item.priceCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: _compactInput(label: 'سعر البيع'),
                  onChanged: (val) {
                    final s = double.tryParse(val) ?? 0;
                    final c = double.tryParse(item.costCtrl.text) ?? 0;
                    final comm = (s - c).clamp(0.0, double.infinity);
                    item.commissionCtrl.text = comm.toStringAsFixed(1).replaceAll('.0', '');
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 4),

              // زر الحذف
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                onPressed: () => _removeItem(idx),
                tooltip: 'حذف الصنف',
              ),
            ],
          ),

          // تفاصيل سريعة: الرابط وإجمالي الربح
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: item.urlCtrl,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                  decoration: _compactInput(
                    label: 'رابط شي إن / المورد (اختياري)',
                    hint: 'https://...',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'التكلفة: ${totalCost.toStringAsFixed(1)} ج | البيع: ${totalSale.toStringAsFixed(1)} ج | الربح: +${totalProfit.toStringAsFixed(1)} ج',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
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
            fontSize: 13,
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
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          '$value ج.م',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: AppColors.primary),
      labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
      hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: Colors.grey),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
      hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5, color: Colors.grey),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.outlineVariant),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة صنف واحد على الأقل للأوردر'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final totalSalePiasters = _calculatedTotalSalePiasters;
    if (totalSalePiasters <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد أسعار الأصناف بحيث يكون إجمالي البيع أكبر من صفر'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final depositPiasters = _depositPiasters;
    if (depositPiasters > totalSalePiasters) {
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

      final costNum = double.tryParse(item.costCtrl.text.trim()) ?? 0.0;
      final commNum = double.tryParse(item.commissionCtrl.text.trim()) ?? 0.0;
      final priceNum = double.tryParse(item.priceCtrl.text.trim()) ?? (costNum + commNum);

      final unitPricePiasters = (priceNum * 100).round();
      final costPiasters = (costNum * 100).round();
      final commPiasters = (commNum * 100).round();
      final itemTotalPricePiasters = qty * unitPricePiasters;

      items.add(
        PreOrderItemEntity(
          id: item.id.isNotEmpty ? item.id : const Uuid().v4(),
          preOrderId: '',
          productName: name,
          variantDescription: desc.isNotEmpty ? desc : null,
          itemUrl: url.isNotEmpty ? url : null,
          quantity: qty,
          unitPricePiasters: unitPricePiasters,
          totalPricePiasters: itemTotalPricePiasters,
          costPricePiasters: costPiasters,
          commissionPiasters: commPiasters,
        ),
      );
    }

    final order = PreOrderEntity(
      id: const Uuid().v4(),
      branchId: '',
      orderNumber: '',
      customerId: _selectedCustomer?.id,
      customerName: _customerNameCtrl.text.trim(),
      customerPhone: _customerPhoneCtrl.text.trim(),
      agentName: _agentNameCtrl.text.trim().isNotEmpty ? _agentNameCtrl.text.trim() : null,
      trackingNumber: _trackingNumberCtrl.text.trim().isNotEmpty ? _trackingNumberCtrl.text.trim() : null,
      notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      expectedDeliveryDate: _expectedDeliveryDate,
      totalPiasters: totalSalePiasters,
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
            'تم تسجيل طلب الحجز بنجاح بقيمة ${Money(totalSalePiasters).toDisplay()} ج.م وعربون ${Money(depositPiasters).toDisplay()} ج.م',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}
