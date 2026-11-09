import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import 'package:drift/drift.dart' hide Column, Table;
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../data/datasources/purchases_local_data_source.dart';

import '../cubits/purchases_cubit.dart';
import '../cubits/suppliers_cubit.dart';
import '../cubits/suppliers_state.dart';
import '../widgets/supplier_form_dialog.dart';

class _InvoiceItemRow {
  final String variantId;
  final String productName;
  final String sku;
  final String color;
  final String size;
  int qty;
  double costPricePounds;

  _InvoiceItemRow({
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.color,
    required this.size,
    required this.qty,
    required this.costPricePounds,
  });

  double get totalPounds => qty * costPricePounds;
}

class CreatePurchaseScreen extends StatefulWidget {
  const CreatePurchaseScreen({super.key});

  @override
  State<CreatePurchaseScreen> createState() => _CreatePurchaseScreenState();
}

class _CreatePurchaseScreenState extends State<CreatePurchaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceNumController = TextEditingController();
  final _paidController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  String? _selectedSupplierId;
  DateTime _purchaseDate = DateTime.now();
  final List<_InvoiceItemRow> _items = [];
  bool _isSaving = false;

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    context.read<SuppliersCubit>().loadSuppliers();
  }

  @override
  void dispose() {
    _invoiceNumController.dispose();
    _paidController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _totalInvoicePounds {
    return _items.fold(0.0, (sum, it) => sum + it.totalPounds);
  }

  double get _paidPounds {
    return double.tryParse(_paidController.text.trim()) ?? 0.0;
  }

  double get _remainingPounds {
    final rem = _totalInvoicePounds - _paidPounds;
    return rem < 0 ? 0 : rem;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _purchaseDate = picked);
    }
  }

  Future<void> _showAddSupplierDialog() async {
    showDialog(
      context: context,
      builder: (_) => SupplierFormDialog(
        onSave:
            ({
              required String name,
              String? phone,
              String? companyName,
              String? address,
            }) async {
              final cubit = context.read<SuppliersCubit>();
              final newSupplier = await cubit.addSupplier(
                name: name,
                phone: phone,
                companyName: companyName,
                address: address,
              );
              if (newSupplier != null) {
                setState(() => _selectedSupplierId = newSupplier.id);
              }
            },
      ),
    );
  }

  Future<void> _showAddVariantDialog() async {
    final db = getIt<AppDatabase>();
    final query =
        db.select(db.productVariants).join([
          innerJoin(
            db.products,
            db.products.id.equalsExp(db.productVariants.productId),
          ),
        ])..where(
          db.productVariants.deletedAt.isNull() &
              db.products.deletedAt.isNull(),
        );

    final rows = await query.get();

    if (!mounted) return;

    if (rows.isEmpty) {
      _showToast(
        'لا توجد أصناف مسجلة بالنظام. يرجى إضافة منتجات وتصنيفات أولاً.',
        isError: true,
      );
      return;
    }

    String searchQuery = '';
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final filtered = rows.where((r) {
              final v = r.readTable(db.productVariants);
              final p = r.readTable(db.products);
              final q = searchQuery.toLowerCase().trim();
              if (q.isEmpty) return true;
              return p.name.toLowerCase().contains(q) ||
                  v.sku.toLowerCase().contains(q) ||
                  v.color.toLowerCase().contains(q);
            }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'اختيار صنف للفاتورة',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 500,
                height: 450,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText:
                            'ابحث باسم الموديل، كود الصنف (SKU)، أو اللون...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (val) =>
                          setDialogState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('لا توجد نتائج مطابقة'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final row = filtered[idx];
                                final v = row.readTable(db.productVariants);
                                final p = row.readTable(db.products);

                                final currentCostPounds = v.costPrice / 100.0;

                                return ListTile(
                                  title: Text(
                                    '${p.name} (${v.color} - مقاس ${v.size})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'كود: ${v.sku} | الرصيد الحالي: ${v.quantity} قطعة',
                                  ),
                                  trailing: Text(
                                    'تكلفة سابقة: ${currentCostPounds.toStringAsFixed(2)} ج.م',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _promptQuantityAndCost(v, p);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _promptQuantityAndCost(ProductVariant v, Product p) {
    final qtyCtrl = TextEditingController(text: '10');
    final costCtrl = TextEditingController(
      text: (v.costPrice / 100.0).toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'تحديد الكمية وسعر الشراء\n${p.name} (${v.color} - مقاس ${v.size})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'الكمية المشتراة (عدد القطع) *',
                prefixIcon: const Icon(Icons.add_shopping_cart_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: costCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'سعر شراء القطعة (ج.م) *',
                prefixIcon: const Icon(Icons.monetization_on_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
              final costPounds = double.tryParse(costCtrl.text.trim()) ?? 0.0;

              if (qty <= 0) {
                _showToast('يرجى إدخال كمية صحيحة أكبر من صفر', isError: true);
                return;
              }
              if (costPounds < 0) {
                _showToast('سعر الشراء غير صحيح', isError: true);
                return;
              }

              setState(() {
                final existingIdx = _items.indexWhere(
                  (it) => it.variantId == v.id,
                );
                if (existingIdx >= 0) {
                  _items[existingIdx].qty += qty;
                  _items[existingIdx].costPricePounds = costPounds;
                } else {
                  _items.add(
                    _InvoiceItemRow(
                      variantId: v.id,
                      productName: p.name,
                      sku: v.sku,
                      color: v.color,
                      size: v.size,
                      qty: qty,
                      costPricePounds: costPounds,
                    ),
                  );
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text(
              'إضافة للفاتورة',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedSupplierId == null) {
      _showToast('يرجى اختيار المورد أولاً', isError: true);
      return;
    }

    if (_items.isEmpty) {
      _showToast('يرجى إضافة صنف واحد على الأقل للفاتورة', isError: true);
      return;
    }

    final authState = context.read<AuthCubit>().state;
    String currentUserId = 'system';
    if (authState is AuthAuthenticated) {
      currentUserId = authState.user.name;
    }

    setState(() => _isSaving = true);

    try {
      final itemsDraft = _items.map((it) {
        return PurchaseItemDraft(
          variantId: it.variantId,
          qty: it.qty,
          costPrice: (it.costPricePounds * 100).round(),
        );
      }).toList();

      final paidPiasters = (_paidPounds * 100).round();

      final created = await context
          .read<PurchasesCubit>()
          .createPurchaseInvoice(
            supplierId: _selectedSupplierId!,
            invoiceNumber: _invoiceNumController.text.trim().isEmpty
                ? null
                : _invoiceNumController.text.trim(),
            purchaseDate: _purchaseDate,
            paidAmount: paidPiasters,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            items: itemsDraft,
            userId: currentUserId,
          );

      if (!mounted) return;

      if (created != null) {
        _showToast('تم حفظ فاتورة المشتريات وتحديث رصيد المخزن والمورد بنجاح');
        Navigator.pop(context, true);
      } else {
        _showToast('فشل حفظ الفاتورة', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showToast('خطأ أثناء الحفظ: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'فاتورة مشتريات جديدة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _isSaving ? null : _submitInvoice,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.white,
                    ),
              label: Text(
                _isSaving ? 'جارِ الحفظ...' : 'حفظ واعتماد الفاتورة',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card: Supplier & Invoice Info
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'بيانات المورد والفاتورة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: BlocBuilder<SuppliersCubit, SuppliersState>(
                              builder: (context, state) {
                                return Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: _selectedSupplierId,
                                        decoration: InputDecoration(
                                          labelText: 'المورد *',
                                          prefixIcon: const Icon(
                                            Icons.business_rounded,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        items: state.suppliers.map((s) {
                                          return DropdownMenuItem(
                                            value: s.id,
                                            child: Text(
                                              '${s.name} ${s.companyName != null ? '(${s.companyName})' : ''}',
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) => setState(
                                          () => _selectedSupplierId = val,
                                        ),
                                        validator: (v) => v == null
                                            ? 'يرجى اختيار المورد'
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'إضافة مورد جديد',
                                      style: IconButton.styleFrom(
                                        backgroundColor: AppColors.primary
                                            .withValues(alpha: 0.1),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.person_add_rounded,
                                        color: AppColors.primary,
                                      ),
                                      onPressed: _showAddSupplierDialog,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _invoiceNumController,
                              decoration: InputDecoration(
                                labelText: 'رقم الفاتورة الورقية (اختياري)',
                                prefixIcon: const Icon(Icons.receipt_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: _pickDate,
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'تاريخ الفاتورة',
                                  prefixIcon: const Icon(
                                    Icons.calendar_month_rounded,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  '${_purchaseDate.year}/${_purchaseDate.month.toString().padLeft(2, '0')}/${_purchaseDate.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Items Section
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الأصناف المشتراة (${_items.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            label: const Text(
                              'إضافة صنف للفاتورة',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: _showAddVariantDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_items.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          alignment: Alignment.center,
                          child: Column(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'لم تتم إضافة أي أصناف بعد. اضغط على "إضافة صنف للفاتورة"',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Table(
                          border: TableBorder(
                            horizontalInside: BorderSide(
                              color: Colors.grey.shade200,
                            ),
                          ),
                          columnWidths: const {
                            0: FlexColumnWidth(4),
                            1: FlexColumnWidth(2),
                            2: FlexColumnWidth(2),
                            3: FlexColumnWidth(2),
                            4: FixedColumnWidth(60),
                          },
                          children: [
                            TableRow(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                              ),
                              children: const [
                                Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'الصنف / المقاس / اللون',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'الكمية (قطعة)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'سعر الشراء للقطعة',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'الإجمالي',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'إجراء',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            ..._items.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final it = entry.value;

                              return TableRow(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          it.productName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'كود: ${it.sku} | لون: ${it.color} | مقاس: ${it.size}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      '${it.qty} قطعة',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      '${it.costPricePounds.toStringAsFixed(2)} ج.م',
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      '${it.totalPounds.toStringAsFixed(2)} ج.م',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: IconButton(
                                      tooltip: 'حذف من الفاتورة',
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Colors.red,
                                      ),
                                      onPressed: () =>
                                          setState(() => _items.removeAt(idx)),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Payment Summary Card
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ملخص الدفع والمديونية',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'إجمالي قيمة الفاتورة:',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_totalInvoicePounds.toStringAsFixed(2)} ج.م',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.green.shade200,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'المبلغ المدفوع مقدماً:',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_paidPounds.toStringAsFixed(2)} ج.م',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _remainingPounds > 0
                                    ? Colors.red.shade50
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _remainingPounds > 0
                                      ? Colors.red.shade200
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'المتبقي آجل (يضاف لمديونية المورد):',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_remainingPounds.toStringAsFixed(2)} ج.م',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                      color: _remainingPounds > 0
                                          ? Colors.red.shade900
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _paidController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'المبلغ المدفوع الآن نقدياً (ج.م)',
                                prefixIcon: const Icon(Icons.payments_outlined),
                                helperText:
                                    'ادخل 0 إذا كانت الفاتورة آجلة بالكامل، أو ادخل كامل المبلغ إذا كانت مسددة',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                              validator: (v) {
                                final val = double.tryParse(v ?? '') ?? 0;
                                if (val < 0) {
                                  return 'المبلغ لا يمكن أن يكون سالباً';
                                }
                                if (val > _totalInvoicePounds &&
                                    _totalInvoicePounds > 0) {
                                  return 'المبلغ المدفوع أكبر من إجمالي الفاتورة';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextFormField(
                              controller: _notesController,
                              decoration: InputDecoration(
                                labelText: 'ملاحظات الفاتورة',
                                prefixIcon: const Icon(Icons.notes_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
