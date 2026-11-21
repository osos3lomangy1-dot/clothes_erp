import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/domain/entities/customer_entity.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../domain/entities/pre_order_batch_entity.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/entities/pre_order_item_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class CreatePreOrderBatchDialog extends StatefulWidget {
  const CreatePreOrderBatchDialog({super.key});

  @override
  State<CreatePreOrderBatchDialog> createState() =>
      _CreatePreOrderBatchDialogState();
}

class _BatchItemEntry {
  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;
  final TextEditingController urlCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl;
  final TextEditingController commissionCtrl;
  final TextEditingController priceCtrl;

  _BatchItemEntry({
    String? id,
    String name = '',
    String desc = '',
    String url = '',
    String qty = '1',
    String cost = '',
    String commission = '50',
    String price = '',
  }) : id = id ?? const Uuid().v4(),
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

class _BatchCustomerEntry {
  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController depositCtrl;
  final TextEditingController customShippingCtrl;
  final TextEditingController notesCtrl;

  // حقول الإدخال السريع لصنف العميل
  final fastNameCtrl = TextEditingController();
  final fastDescCtrl = TextEditingController();
  final fastQtyCtrl = TextEditingController(text: '1');
  final fastCostCtrl = TextEditingController();
  final fastCommissionCtrl = TextEditingController(text: '50');
  final fastSalePriceCtrl = TextEditingController();
  final fastUrlCtrl = TextEditingController();

  final fastNameFocus = FocusNode();
  final fastDescFocus = FocusNode();
  final fastQtyFocus = FocusNode();
  final fastCostFocus = FocusNode();
  final fastCommissionFocus = FocusNode();
  final fastSalePriceFocus = FocusNode();

  CustomerEntity? selectedCustomer;
  String paymentMethod = 'cash';
  final List<_BatchItemEntry> items = [];

  _BatchCustomerEntry({
    String? id,
    String name = '',
    String phone = '',
    String deposit = '',
  }) : id = id ?? const Uuid().v4(),
       nameCtrl = TextEditingController(text: name),
       phoneCtrl = TextEditingController(text: phone),
       depositCtrl = TextEditingController(text: deposit),
       customShippingCtrl = TextEditingController(text: '0'),
       notesCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    phoneCtrl.dispose();
    depositCtrl.dispose();
    customShippingCtrl.dispose();
    notesCtrl.dispose();

    fastNameCtrl.dispose();
    fastDescCtrl.dispose();
    fastQtyCtrl.dispose();
    fastCostCtrl.dispose();
    fastCommissionCtrl.dispose();
    fastSalePriceCtrl.dispose();
    fastUrlCtrl.dispose();

    fastNameFocus.dispose();
    fastDescFocus.dispose();
    fastQtyFocus.dispose();
    fastCostFocus.dispose();
    fastCommissionFocus.dispose();
    fastSalePriceFocus.dispose();

    for (final it in items) {
      it.dispose();
    }
  }

  int get totalPieces => items.fold(0, (sum, it) {
    final q = int.tryParse(it.qtyCtrl.text.trim()) ?? 1;
    return sum + (q > 0 ? q : 1);
  });

  int get totalSalePiasters => items.fold(0, (sum, it) {
    final q = int.tryParse(it.qtyCtrl.text.trim()) ?? 1;
    final p = double.tryParse(it.priceCtrl.text.trim()) ?? 0.0;
    return sum + (q * (p * 100).round());
  });

  int get totalCostPiasters => items.fold(0, (sum, it) {
    final q = int.tryParse(it.qtyCtrl.text.trim()) ?? 1;
    final c = double.tryParse(it.costCtrl.text.trim()) ?? 0.0;
    return sum + (q * (c * 100).round());
  });

  int get depositPiasters {
    final d = double.tryParse(depositCtrl.text.trim()) ?? 0.0;
    return (d * 100).round();
  }
}

class _CreatePreOrderBatchDialogState extends State<CreatePreOrderBatchDialog> {
  final _formKey = GlobalKey<FormState>();

  // بيانات الشحنة العامة
  late final TextEditingController _batchNumberCtrl;
  final _agentNameCtrl = TextEditingController();
  final _trackingNumberCtrl = TextEditingController();
  final _totalShippingCtrl = TextEditingController(text: '0');
  final _defaultCommissionCtrl = TextEditingController(text: '50');

  String _shippingSplitMethod = ShippingSplitMethods.perItem;
  DateTime? _expectedDeliveryDate;

  final List<_BatchCustomerEntry> _customers = [];
  List<CustomerEntity> _availableCustomers = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _batchNumberCtrl = TextEditingController(
      text: 'شحنة ${now.day}-${now.month}-${now.year}',
    );
    _loadExistingCustomers();
    _addCustomer(); // عميل أول تلقائي
  }

  Future<void> _loadExistingCustomers() async {
    try {
      final repo = getIt<CustomerRepository>();
      final res = await repo.getCustomers();
      res.fold((_) {}, (list) {
        if (mounted) setState(() => _availableCustomers = list);
      });
    } catch (_) {}
  }

  void _addCustomer() {
    setState(() {
      final entry = _BatchCustomerEntry();
      entry.fastCommissionCtrl.text = _defaultCommissionCtrl.text.trim();
      _customers.add(entry);
    });
  }

  void _attachPendingOrders() {
    final cubit = context.read<PreOrdersCubit>();
    final pending = cubit.state.allOrders
        .where(
          (o) =>
              o.batchId == null &&
              o.status == PreOrderStatuses.pendingProcessing &&
              !_customers.any((c) => c.nameCtrl.text.trim() == o.customerName),
        )
        .toList();

    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'لا توجد أوردرات فردية معلقة غير مدمجة حالياً لضمها',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      return;
    }

    final selectedOrderIds = <String>{};

    showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (context, setModalState) {
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
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.link_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'ضم أوردرات فردية معلقة للشحنة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 350,
              child: ListView.separated(
                itemCount: pending.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: AppColors.outlineVariant),
                itemBuilder: (context, idx) {
                  final po = pending[idx];
                  final isChecked = selectedOrderIds.contains(po.id);
                  return CheckboxListTile(
                    value: isChecked,
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Row(
                      children: [
                        Text(
                          po.orderNumber,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          po.customerName,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '${po.items.length} أصناف • إجمالي: ${Money(po.totalPiasters).toDisplay()} ج • عربون: ${Money(po.depositPiasters).toDisplay()} ج',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        if (val == true) {
                          selectedOrderIds.add(po.id);
                        } else {
                          selectedOrderIds.remove(po.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dCtx),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  final toAttach = pending
                      .where((o) => selectedOrderIds.contains(o.id))
                      .toList();
                  Navigator.pop(dCtx);
                  if (toAttach.isNotEmpty) {
                    setState(() {
                      for (final order in toAttach) {
                        final entry = _BatchCustomerEntry(
                          id: order.id,
                          name: order.customerName,
                          phone: order.customerPhone,
                          deposit: (order.depositPiasters / 100.0)
                              .toStringAsFixed(1)
                              .replaceAll('.0', ''),
                        );
                        for (final it in order.items) {
                          entry.items.add(
                            _BatchItemEntry(
                              id: it.id,
                              name: it.productName,
                              desc: it.variantDescription ?? '',
                              qty: it.quantity.toString(),
                              cost: (it.costPricePiasters / 100.0)
                                  .toStringAsFixed(1)
                                  .replaceAll('.0', ''),
                              commission: (it.commissionPiasters / 100.0)
                                  .toStringAsFixed(1)
                                  .replaceAll('.0', ''),
                              price: (it.unitPricePiasters / 100.0)
                                  .toStringAsFixed(1)
                                  .replaceAll('.0', ''),
                              url: it.itemUrl ?? '',
                            ),
                          );
                        }
                        _customers.add(entry);
                      }
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تم ضم ${toAttach.length} أوردرات للشحنة وحساب الشحن تلقائياً!',
                        ),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                },
                child: Text(
                  'ضم (${selectedOrderIds.length}) للشحنة',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _removeCustomer(int index) {
    if (_customers.length <= 1) return;
    setState(() {
      final c = _customers.removeAt(index);
      c.dispose();
    });
  }

  @override
  void dispose() {
    _batchNumberCtrl.dispose();
    _agentNameCtrl.dispose();
    _trackingNumberCtrl.dispose();
    _totalShippingCtrl.dispose();
    _defaultCommissionCtrl.dispose();

    for (final c in _customers) {
      c.dispose();
    }
    super.dispose();
  }

  // --- حسابات الشحن وتوزيع الحصص ---

  int get _totalShippingPiasters {
    final s = double.tryParse(_totalShippingCtrl.text.trim()) ?? 0.0;
    return (s * 100).round();
  }

  int get _allBatchPieces {
    return _customers.fold(0, (sum, c) => sum + c.totalPieces);
  }

  int _calculateCustomerAllocatedShipping(_BatchCustomerEntry customer) {
    final totalShipping = _totalShippingPiasters;
    if (totalShipping <= 0) return 0;

    switch (_shippingSplitMethod) {
      case ShippingSplitMethods.freeShipping:
        return 0;
      case ShippingSplitMethods.equalPerCustomer:
        if (_customers.isEmpty) return 0;
        return (totalShipping / _customers.length).round();
      case ShippingSplitMethods.customFixed:
        final cVal =
            double.tryParse(customer.customShippingCtrl.text.trim()) ?? 0.0;
        return (cVal * 100).round();
      case ShippingSplitMethods.perItem:
      default:
        final allPieces = _allBatchPieces;
        if (allPieces <= 0) return 0;
        return (totalShipping * customer.totalPieces / allPieces).round();
    }
  }

  // --- ملخص الشحنة العام ---

  int get _batchTotalRetailPiasters =>
      _customers.fold(0, (sum, c) => sum + c.totalSalePiasters);

  int get _batchTotalCostPiasters =>
      _customers.fold(0, (sum, c) => sum + c.totalCostPiasters);

  int get _batchTotalDepositsPiasters =>
      _customers.fold(0, (sum, c) => sum + c.depositPiasters);

  int get _batchTotalProfitPiasters {
    final baseProfit = _batchTotalRetailPiasters - _batchTotalCostPiasters;
    if (_shippingSplitMethod == ShippingSplitMethods.freeShipping) {
      return (baseProfit - _totalShippingPiasters).clamp(
        0,
        _batchTotalRetailPiasters,
      );
    }
    return baseProfit.clamp(0, _batchTotalRetailPiasters);
  }

  int get _batchTotalRemainingPiasters {
    int rem = 0;
    for (final c in _customers) {
      final allocShipping = _calculateCustomerAllocatedShipping(c);
      final totalWithShipping = c.totalSalePiasters + allocShipping;
      rem += (totalWithShipping - c.depositPiasters).clamp(
        0,
        totalWithShipping,
      );
    }
    return rem;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 920),
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
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.inventory_2_rounded,
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
                            'إنشاء شحنة مجمعة وتوزيع الشحن (Group Batch Hub)',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            'تجميع طلبات عدة عملاء في شحنة واحدة، توزيع الشحن العام، وحساب صافي أرباحك',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11.5,
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
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(height: 22, color: AppColors.outlineVariant),

                // 2. المحتوى التمريري
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // بيانات الشحنة العامة
                        _buildSectionHeader(
                          'بيانات الشحنة والمندوب وتكلفة الشحن العام',
                          Icons.local_shipping_rounded,
                        ),
                        const SizedBox(height: 8),

                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _batchNumberCtrl,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: _inputDecoration(
                                  label: 'اسم أو كود الشحنة المجمعة *',
                                  hint: 'مثال: شحنة 25 نوفمبر / BATCH-102',
                                  icon: Icons.tag_rounded,
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'مطلوب اسم الشحنة'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _agentNameCtrl,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                                decoration: _inputDecoration(
                                  label: 'المندوب / الوسيط',
                                  hint: 'كابتن فلان أو شركة الشحن',
                                  icon: Icons.badge_outlined,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _trackingNumberCtrl,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                                decoration: _inputDecoration(
                                  label: 'رقم بوليصة الشحن العام',
                                  hint: 'SH-9284102',
                                  icon: Icons.numbers_rounded,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // إجمالي الشحن وطريقة التوزيع والعمولة الافتراضية
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _totalShippingCtrl,
                                keyboardType: TextInputType.number,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                                decoration: _inputDecoration(
                                  label: 'إجمالي الشحن العام (ج.م) *',
                                  hint: '400',
                                  icon: Icons.local_shipping_outlined,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                initialValue: _shippingSplitMethod,
                                decoration: _inputDecoration(
                                  label: 'طريقة توزيع الشحن العام على العملاء',
                                  icon: Icons.call_split_rounded,
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: ShippingSplitMethods.perItem,
                                    child: Text(
                                      ShippingSplitMethods.getLabel(
                                        ShippingSplitMethods.perItem,
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value:
                                        ShippingSplitMethods.equalPerCustomer,
                                    child: Text(
                                      ShippingSplitMethods.getLabel(
                                        ShippingSplitMethods.equalPerCustomer,
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: ShippingSplitMethods.customFixed,
                                    child: Text(
                                      ShippingSplitMethods.getLabel(
                                        ShippingSplitMethods.customFixed,
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: ShippingSplitMethods.freeShipping,
                                    child: Text(
                                      ShippingSplitMethods.getLabel(
                                        ShippingSplitMethods.freeShipping,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _shippingSplitMethod = val);
                                  }
                                },
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
                                  label: 'العمولة الافتراضية (ج.م)',
                                  hint: '50',
                                  icon: Icons.monetization_on_outlined,
                                ),
                                onChanged: (val) {
                                  for (final c in _customers) {
                                    c.fastCommissionCtrl.text = val.trim();
                                  }
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        // شريط عملاء الشحنة
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildSectionHeader(
                              'عملاء الشحنة (${_customers.length})',
                              Icons.groups_rounded,
                            ),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _attachPendingOrders,
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
                                    Icons.link_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'ضم أوردرات فردية معلقة',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: _addCustomer,
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
                                    Icons.person_add_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    '+ إضافة عميل للشحنة',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // كروت العملاء
                        ...List.generate(
                          _customers.length,
                          (cIdx) => _buildCustomerCard(cIdx),
                        ),

                        const SizedBox(height: 16),

                        // تاريخ الوصول المتوقع للشحنة بالكامل
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now().add(
                                const Duration(days: 7),
                              ),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked != null) {
                              setState(() => _expectedDeliveryDate = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: InputDecorator(
                            decoration: _inputDecoration(
                              label: 'تاريخ وصول الشحنة المتوقع للمحل',
                              icon: Icons.calendar_today_rounded,
                            ),
                            child: Text(
                              _expectedDeliveryDate != null
                                  ? '${_expectedDeliveryDate!.year}-${_expectedDeliveryDate!.month.toString().padLeft(2, '0')}-${_expectedDeliveryDate!.day.toString().padLeft(2, '0')}'
                                  : 'تحديد موعد وصول الشحنة المتوقع للمحل (اختياري)',
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

                        const SizedBox(height: 18),

                        // 3. شريط الملخص المالي العام للشحنة بالكامل (متجاوب مع التمرير لمنع أي Overflow)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildSummaryItem(
                                  'العملاء',
                                  '${_customers.length}',
                                  AppColors.onSurface,
                                ),
                                _summaryDivider(),
                                _buildSummaryItem(
                                  'إجمالي القطع',
                                  '$_allBatchPieces',
                                  AppColors.onSurface,
                                ),
                                _summaryDivider(),
                                _buildSummaryItem(
                                  'المبيعات',
                                  Money(_batchTotalRetailPiasters).toDisplay(),
                                  AppColors.onSurface,
                                ),
                                _summaryDivider(),
                                _buildSummaryItem(
                                  'تكلفة المندوب',
                                  Money(_batchTotalCostPiasters).toDisplay(),
                                  AppColors.onSurfaceVariant,
                                ),
                                _summaryDivider(),
                                _buildSummaryItem(
                                  'الشحن العام',
                                  Money(_totalShippingPiasters).toDisplay(),
                                  AppColors.primary,
                                ),
                                _summaryDivider(),
                                _buildSummaryItem(
                                  'صافي أرباحك',
                                  '+${Money(_batchTotalProfitPiasters).toDisplay()}',
                                  AppColors.primary,
                                ),
                                _summaryDivider(),
                                _buildSummaryItem(
                                  'إجمالي العربونات',
                                  Money(
                                    _batchTotalDepositsPiasters,
                                  ).toDisplay(),
                                  AppColors.success,
                                ),
                                _summaryDivider(),
                                _buildSummaryItem(
                                  'المتبقي تحصيله',
                                  Money(
                                    _batchTotalRemainingPiasters,
                                  ).toDisplay(),
                                  _batchTotalRemainingPiasters > 0
                                      ? AppColors.error
                                      : AppColors.success,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 4. أزرار الإجراء
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
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
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _submitBatch,
                      icon: const Icon(Icons.check_rounded, size: 20),
                      label: const Text(
                        'تأكيد وحفظ الشحنة المجمعة',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                        ),
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

  // --- كارت العميل داخل الشحنة ---

  Widget _buildCustomerCard(int cIdx) {
    final customer = _customers[cIdx];
    final allocatedShipping = _calculateCustomerAllocatedShipping(customer);
    final totalWithShipping = customer.totalSalePiasters + allocatedShipping;
    final remainingWithShipping = (totalWithShipping - customer.depositPiasters)
        .clamp(0, totalWithShipping);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: 12,
          top: 4,
        ),
        leading: CircleAvatar(
          radius: 13,
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Text(
            '${cIdx + 1}',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      customer.nameCtrl.text.isNotEmpty
                          ? customer.nameCtrl.text
                          : 'عميل جديد #${cIdx + 1}',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (customer.phoneCtrl.text.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '(${customer.phoneCtrl.text})',
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
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Text(
                'القطع: ${customer.totalPieces} | الشحن: ${Money(allocatedShipping).toDisplay()} ج | المتبقي: ${Money(remainingWithShipping).toDisplay()} ج',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            if (_customers.length > 1) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.error,
                ),
                onPressed: () => _removeCustomer(cIdx),
                tooltip: 'حذف العميل من الشحنة',
              ),
            ],
          ],
        ),
        children: [
          // السطر الأول: بيانات العميل (الاسم ورقم الهاتف)
          Row(
            children: [
              if (_availableCustomers.isNotEmpty) ...[
                Expanded(
                  flex: 3,
                  child: Autocomplete<CustomerEntity>(
                    displayStringForOption: (c) => '${c.name} (${c.phone})',
                    optionsBuilder: (textVal) {
                      if (textVal.text.isEmpty) return const [];
                      return _availableCustomers.where(
                        (c) =>
                            c.name.toLowerCase().contains(
                              textVal.text.toLowerCase(),
                            ) ||
                            c.phone.contains(textVal.text),
                      );
                    },
                    onSelected: (selected) {
                      setState(() {
                        customer.selectedCustomer = selected;
                        customer.nameCtrl.text = selected.name;
                        customer.phoneCtrl.text = selected.phone;
                      });
                    },
                    fieldViewBuilder:
                        (context, textCtrl, focusNode, onFieldSubmitted) {
                          // مزامنة مبدئية إذا تم إدخال اسم
                          if (customer.nameCtrl.text.isNotEmpty &&
                              textCtrl.text.isEmpty) {
                            textCtrl.text = customer.nameCtrl.text;
                          }
                          return TextFormField(
                            controller: textCtrl,
                            focusNode: focusNode,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                            decoration: _compactInput(
                              label:
                                  'اسم العميل (بحث في المسجلين أو كتابة جديد) *',
                              hint: 'مثال: سارة محمد',
                            ),
                            onChanged: (val) {
                              customer.nameCtrl.text = val;
                              setState(() {});
                            },
                          );
                        },
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: customer.nameCtrl,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    decoration: _compactInput(label: 'اسم العميل *'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: customer.phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  decoration: _compactInput(
                    label: 'رقم الهاتف (واتساب) *',
                    hint: '01xxxxxxxxx',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // السطر الثاني: العربون، طريقة الدفع، والشحن المخصص
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: customer.depositCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                  decoration: _compactInput(label: 'العربون المدفوع (ج.م)'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: customer.paymentMethod,
                  decoration: _compactInput(label: 'طريقة دفع العربون'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('كاش (نقداً)')),
                    DropdownMenuItem(
                      value: 'instapay',
                      child: Text('انستاباي'),
                    ),
                    DropdownMenuItem(
                      value: 'vodafone_cash',
                      child: Text('فودافون كاش'),
                    ),
                    DropdownMenuItem(value: 'card', child: Text('فيزا / بطاقة')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => customer.paymentMethod = val);
                    }
                  },
                ),
              ),
              if (_shippingSplitMethod == ShippingSplitMethods.customFixed) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: customer.customShippingCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration:
                        _compactInput(label: 'الشحن المخصص للعميل (ج.م)'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // سطر الإدخال السريع بالإنتر لأصناف هذا العميل
          _buildCustomerFastItemRow(customer),

          const SizedBox(height: 8),

          // قائمة أصناف هذا العميل
          if (customer.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'لا توجد أصناف لهذا العميل بعد. اكتب بيانات الصنف واضغط Enter',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            )
          else
            ...List.generate(customer.items.length, (itIdx) {
              final it = customer.items[itIdx];
              final q = int.tryParse(it.qtyCtrl.text.trim()) ?? 1;
              final p = double.tryParse(it.priceCtrl.text.trim()) ?? 0.0;
              final c = double.tryParse(it.costCtrl.text.trim()) ?? 0.0;
              final itemTotal = q * p;
              final itemProfit = itemTotal - (q * c);

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Text(
                      '${itIdx + 1}. ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              it.nameCtrl.text.isNotEmpty
                                  ? it.nameCtrl.text
                                  : 'صنف بدون اسم',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (it.descCtrl.text.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '(${it.descCtrl.text})',
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
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          'الكمية: $q | البيع: ${itemTotal.toStringAsFixed(1)} ج | الربح: +${itemProfit.toStringAsFixed(1)} ج',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppColors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          final removed = customer.items.removeAt(itIdx);
                          removed.dispose();
                        });
                      },
                      child: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // --- سطر الإدخال السريع بالـ Enter لأصناف العميل ---

  Widget _buildCustomerFastItemRow(_BatchCustomerEntry customer) {
    void addFastItem() {
      final name = customer.fastNameCtrl.text.trim();
      if (name.isEmpty) {
        customer.fastNameFocus.requestFocus();
        return;
      }

      final desc = customer.fastDescCtrl.text.trim();
      final qty = customer.fastQtyCtrl.text.trim().isNotEmpty
          ? customer.fastQtyCtrl.text.trim()
          : '1';
      final cost = customer.fastCostCtrl.text.trim();
      final comm = customer.fastCommissionCtrl.text.trim().isNotEmpty
          ? customer.fastCommissionCtrl.text.trim()
          : _defaultCommissionCtrl.text.trim();
      final price = customer.fastSalePriceCtrl.text.trim().isNotEmpty
          ? customer.fastSalePriceCtrl.text.trim()
          : ((double.tryParse(cost) ?? 0) + (double.tryParse(comm) ?? 0))
                .toString();
      final url = customer.fastUrlCtrl.text.trim();

      setState(() {
        customer.items.add(
          _BatchItemEntry(
            name: name,
            desc: desc,
            qty: qty,
            cost: cost,
            commission: comm,
            price: price,
            url: url,
          ),
        );

        customer.fastNameCtrl.clear();
        customer.fastDescCtrl.clear();
        customer.fastQtyCtrl.text = '1';
        customer.fastCostCtrl.clear();
        customer.fastCommissionCtrl.text = _defaultCommissionCtrl.text.trim();
        customer.fastSalePriceCtrl.clear();
        customer.fastUrlCtrl.clear();
      });

      customer.fastNameFocus.requestFocus();
    }

    void onCostOrCommissionChanged() {
      final cost = double.tryParse(customer.fastCostCtrl.text.trim()) ?? 0.0;
      final comm =
          double.tryParse(customer.fastCommissionCtrl.text.trim()) ??
          double.tryParse(_defaultCommissionCtrl.text.trim()) ??
          0.0;
      final total = cost + comm;
      customer.fastSalePriceCtrl.text = total > 0
          ? total.toStringAsFixed(1).replaceAll('.0', '')
          : '';
      setState(() {});
    }

    void onSalePriceChanged(String val) {
      final sale = double.tryParse(val.trim()) ?? 0.0;
      final cost = double.tryParse(customer.fastCostCtrl.text.trim()) ?? 0.0;
      final comm = (sale - cost).clamp(0.0, double.infinity);
      customer.fastCommissionCtrl.text = comm > 0
          ? comm.toStringAsFixed(1).replaceAll('.0', '')
          : '';
      setState(() {});
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: TextFormField(
                  controller: customer.fastNameCtrl,
                  focusNode: customer.fastNameFocus,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  decoration: _compactInput(
                    label: 'اسم الصنف أو كود شي إن *',
                    hint: 'اكتب واضغط Enter...',
                  ),
                  onFieldSubmitted: (_) =>
                      customer.fastDescFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: customer.fastDescCtrl,
                  focusNode: customer.fastDescFocus,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  decoration: _compactInput(
                    label: 'المقاس/اللون',
                    hint: 'L - أسود',
                  ),
                  onFieldSubmitted: (_) => customer.fastQtyFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextFormField(
                  controller: customer.fastQtyCtrl,
                  focusNode: customer.fastQtyFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: _compactInput(label: 'الكمية'),
                  onFieldSubmitted: (_) =>
                      customer.fastCostFocus.requestFocus(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: customer.fastCostCtrl,
                  focusNode: customer.fastCostFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: _compactInput(label: 'تكلفة المندوب'),
                  onChanged: (_) => onCostOrCommissionChanged(),
                  onFieldSubmitted: (_) =>
                      customer.fastCommissionFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: customer.fastCommissionCtrl,
                  focusNode: customer.fastCommissionFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  decoration: _compactInput(label: 'العمولة'),
                  onChanged: (_) => onCostOrCommissionChanged(),
                  onFieldSubmitted: (_) =>
                      customer.fastSalePriceFocus.requestFocus(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: customer.fastSalePriceCtrl,
                  focusNode: customer.fastSalePriceFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: _compactInput(label: 'سعر البيع'),
                  onChanged: onSalePriceChanged,
                  onFieldSubmitted: (_) => addFastItem(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: addFastItem,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text(
                  'إضافة [Enter]',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- حفظ الشحنة المجمعة بالكامل ---

  Future<void> _submitBatch() async {
    if (!_formKey.currentState!.validate()) return;

    if (_customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة عميل واحد على الأقل للشحنة'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // تحقق من وجود صنف واحد على الأقل في الشحنة
    if (_allBatchPieces <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة صنف واحد على الأقل في الشحنة'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final batchId = const Uuid().v4();
    final batchNum = _batchNumberCtrl.text.trim();
    final agentName = _agentNameCtrl.text.trim().isNotEmpty
        ? _agentNameCtrl.text.trim()
        : null;
    final trackingNumber = _trackingNumberCtrl.text.trim().isNotEmpty
        ? _trackingNumberCtrl.text.trim()
        : null;
    final totalShipping = _totalShippingPiasters;

    final batch = PreOrderBatchEntity(
      id: batchId,
      branchId: '',
      batchNumber: batchNum,
      agentName: agentName,
      trackingNumber: trackingNumber,
      totalShippingPiasters: totalShipping,
      shippingSplitMethod: _shippingSplitMethod,
      status: PreOrderStatuses.pendingProcessing,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final cubit = context.read<PreOrdersCubit>();
    final orders = <PreOrderEntity>[];
    final customerRepo = getIt<CustomerRepository>();

    for (int i = 0; i < _customers.length; i++) {
      final cEntry = _customers[i];
      final cName = cEntry.nameCtrl.text.trim().isNotEmpty
          ? cEntry.nameCtrl.text.trim()
          : 'عميل #${i + 1}';
      final cPhone = cEntry.phoneCtrl.text.trim();

      // حفظ العميل الجديد في قاعدة البيانات تلقائياً إذا لم يكن مسجلاً
      String? customerId = cEntry.selectedCustomer?.id;
      if (customerId == null && cPhone.isNotEmpty) {
        final newCustId = const Uuid().v4();
        await customerRepo.addCustomer(
          CustomerEntity(
            id: newCustId,
            name: cName,
            phone: cPhone,
            createdAt: DateTime.now(),
          ),
        );
        customerId = newCustId;
      }

      final allocatedShipping = _calculateCustomerAllocatedShipping(cEntry);
      final items = <PreOrderItemEntity>[];

      for (final it in cEntry.items) {
        final iName = it.nameCtrl.text.trim().isNotEmpty
            ? it.nameCtrl.text.trim()
            : 'صنف';
        final iDesc = it.descCtrl.text.trim();
        final iQty = int.tryParse(it.qtyCtrl.text.trim()) ?? 1;
        final iCost = double.tryParse(it.costCtrl.text.trim()) ?? 0.0;
        final iComm = double.tryParse(it.commissionCtrl.text.trim()) ?? 0.0;
        final iPrice =
            double.tryParse(it.priceCtrl.text.trim()) ?? (iCost + iComm);

        final unitPiasters = (iPrice * 100).round();
        final costPiasters = (iCost * 100).round();
        final commPiasters = (iComm * 100).round();
        final totalPiasters = iQty * unitPiasters;

        items.add(
          PreOrderItemEntity(
            id: it.id.isNotEmpty ? it.id : const Uuid().v4(),
            preOrderId: '',
            productName: iName,
            variantDescription: iDesc.isNotEmpty ? iDesc : null,
            quantity: iQty,
            unitPricePiasters: unitPiasters,
            totalPricePiasters: totalPiasters,
            costPricePiasters: costPiasters,
            commissionPiasters: commPiasters,
            itemUrl: it.urlCtrl.text.trim().isNotEmpty
                ? it.urlCtrl.text.trim()
                : null,
          ),
        );
      }

      final cTotalSale = items.fold(
        0,
        (sum, it) => sum + it.totalPricePiasters,
      );
      final cDeposit = cEntry.depositPiasters;

      orders.add(
        PreOrderEntity(
          id: const Uuid().v4(),
          branchId: '',
          orderNumber: '',
          batchId: batchId,
          customerId: customerId,
          customerName: cName,
          customerPhone: cPhone,
          agentName: agentName,
          trackingNumber: trackingNumber,
          notes: cEntry.notesCtrl.text.trim().isNotEmpty
              ? cEntry.notesCtrl.text.trim()
              : null,
          expectedDeliveryDate: _expectedDeliveryDate,
          totalPiasters: cTotalSale,
          allocatedShippingPiasters: allocatedShipping,
          depositPiasters: cDeposit,
          status: PreOrderStatuses.pendingProcessing,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          items: items,
        ),
      );
    }

    final ok = await cubit.createBatch(
      batch,
      orders,
      paymentMethod: _customers.first.paymentMethod,
    );

    if (ok && mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تسجيل الشحنة المجمعة ($batchNum) بنجاح لعدد ${_customers.length} عملاء وإجمالي $_allBatchPieces قطعة',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: AppColors.success,
        ),
      );
    }
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

  Widget _summaryDivider() {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: AppColors.outlineVariant,
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13,
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
      hintStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 11,
        color: AppColors.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
      labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5),
      hintStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontSize: 10,
        color: AppColors.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.outlineVariant),
      ),
    );
  }
}
