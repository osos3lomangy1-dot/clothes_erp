import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/retail_sector.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/barcode_helper.dart';
import 'package:drift/drift.dart' hide Column, Table;
import '../../../../core/database/branch_provider.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../inventory/domain/entities/goods_receipt_entity.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../settings/data/services/activity_settings_service.dart';
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

class PurchaseInitialItem {
  final String variantId;
  final String productName;
  final String sku;
  final String color;
  final String size;
  final int qty;
  final double costPricePounds;

  const PurchaseInitialItem({
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.color,
    required this.size,
    required this.qty,
    required this.costPricePounds,
  });
}

class CreatePurchaseScreen extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onSaved;
  final GoodsReceiptEntity? initialGoodsReceipt;
  final List<PurchaseInitialItem>? initialItems;

  const CreatePurchaseScreen({
    super.key,
    this.onBack,
    this.onSaved,
    this.initialGoodsReceipt,
    this.initialItems,
  });

  @override
  Widget build(BuildContext context) {
    bool hasSuppliersCubit = false;
    try {
      context.read<SuppliersCubit>();
      hasSuppliersCubit = true;
    } catch (_) {
      hasSuppliersCubit = false;
    }

    bool hasPurchasesCubit = false;
    try {
      context.read<PurchasesCubit>();
      hasPurchasesCubit = true;
    } catch (_) {
      hasPurchasesCubit = false;
    }

    Widget content = _CreatePurchaseScreenContent(
      onBack: onBack,
      onSaved: onSaved,
      initialGoodsReceipt: initialGoodsReceipt,
      initialItems: initialItems,
    );

    if (!hasPurchasesCubit) {
      content = BlocProvider<PurchasesCubit>(
        create: (_) => getIt<PurchasesCubit>(),
        child: content,
      );
    }

    if (!hasSuppliersCubit) {
      content = BlocProvider<SuppliersCubit>(
        create: (_) => getIt<SuppliersCubit>(),
        child: content,
      );
    }

    return content;
  }
}

class _CreatePurchaseScreenContent extends StatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onSaved;
  final GoodsReceiptEntity? initialGoodsReceipt;
  final List<PurchaseInitialItem>? initialItems;

  const _CreatePurchaseScreenContent({
    this.onBack,
    this.onSaved,
    this.initialGoodsReceipt,
    this.initialItems,
  });

  @override
  State<_CreatePurchaseScreenContent> createState() => _CreatePurchaseScreenContentState();
}

class _CreatePurchaseScreenContentState extends State<_CreatePurchaseScreenContent> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceNumController = TextEditingController();
  final _paidController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  static const List<String> kitchenSupplyUnits = [
    'بالعدد / حبة',
    'كيلوجرام',
    'شيكارة 25ك',
    'لتر / جركن',
    'كرتونة / باكت',
  ];

  StreamSubscription<String?>? _sectorSub;
  StreamSubscription<List<ActivityType>>? _activitySub;
  String _sectorMode = RetailSector.apparel;

  bool get _isHospitality {
    if (RetailSector.isHospitalityMode(_sectorMode)) return true;
    final enabled = getIt.isRegistered<ActivitySettingsService>()
        ? getIt<ActivitySettingsService>().cachedEnabledActivities
        : <ActivityType>[];
    if (enabled.length == 1 && enabled.contains(ActivityType.restaurantsCafes)) {
      return true;
    }
    return false;
  }

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

    if (getIt.isRegistered<FeatureGate>()) {
      getIt<FeatureGate>().getMeta(RetailSector.metaKey).then((mode) {
        if (mounted && mode != null) {
          setState(() => _sectorMode = mode);
        }
      });
      _sectorSub = getIt<FeatureGate>().watchMeta(RetailSector.metaKey).listen((mode) {
        if (mounted) setState(() => _sectorMode = mode ?? RetailSector.apparel);
      });
    }
    if (getIt.isRegistered<ActivitySettingsService>()) {
      _activitySub = getIt<ActivitySettingsService>().watchEnabledActivities().listen((_) {
        if (mounted) setState(() {});
      });
    }

    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      if (widget.initialGoodsReceipt != null) {
        final gr = widget.initialGoodsReceipt!;
        if (gr.notes != null && gr.notes!.isNotEmpty) {
          _notesController.text = 'مبنية على استلام بضاعة #${gr.id}: ${gr.notes}';
        } else {
          _notesController.text = 'مبنية على استلام بضاعة معلق #${gr.id}';
        }
      }
      for (final it in widget.initialItems!) {
        _items.add(_InvoiceItemRow(
          variantId: it.variantId,
          productName: it.productName,
          sku: it.sku,
          color: it.color,
          size: it.size,
          qty: it.qty,
          costPricePounds: it.costPricePounds,
        ));
      }
    } else if (widget.initialGoodsReceipt != null) {
      final gr = widget.initialGoodsReceipt!;
      if (gr.notes != null && gr.notes!.isNotEmpty) {
        _notesController.text = 'مبنية على استلام بضاعة #${gr.id}: ${gr.notes}';
      } else {
        _notesController.text = 'مبنية على استلام بضاعة معلق #${gr.id}';
      }

      for (final it in gr.items) {
        _items.add(_InvoiceItemRow(
          variantId: it.variantId,
          productName: it.productName ?? 'منتج',
          sku: it.sku ?? '',
          color: it.color ?? '',
          size: it.size ?? '',
          qty: it.quantity,
          costPricePounds: 0.0,
        ));
      }
      _fetchVariantCostPricesForReceipt();
    }
  }

  Future<void> _fetchVariantCostPricesForReceipt() async {
    try {
      final db = getIt<AppDatabase>();
      bool changed = false;
      for (final it in _items) {
        if (it.costPricePounds == 0.0) {
          final row = await (db.select(db.productVariants)
                ..where((tbl) => tbl.id.equals(it.variantId)))
              .getSingleOrNull();
          if (row != null && row.costPrice > 0) {
            it.costPricePounds = row.costPrice / 100.0;
            changed = true;
          }
        }
      }
      if (changed && mounted) {
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _sectorSub?.cancel();
    _activitySub?.cancel();
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
        onSave: ({
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
          if (newSupplier == null) {
            return cubit.state.errorMessage ?? 'تعذر إضافة المورد. يرجى إعادة المحاولة.';
          }
          if (mounted) {
            setState(() => _selectedSupplierId = newSupplier.id);
          }
          return null;
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

    final allRows = await query.get();
    final rows = allRows.where((r) {
      final p = r.readTable(db.products);
      final cul = RestaurantCulinaryData.parse(p.description);
      if (_isHospitality) {
        return cul.isRawMaterial == true;
      } else {
        return cul.isRawMaterial != true;
      }
    }).toList();

    if (!mounted) return;

    if (rows.isEmpty) {
      _showToast(
        _isHospitality
            ? 'لا توجد خامات أو مستلزمات مسجلة بالنظام. يرجى إضافة خامات ومستلزمات أولاً.'
            : 'لا توجد أصناف مسجلة بالنظام. يرجى إضافة منتجات وتصنيفات أولاً.',
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
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isHospitality
                          ? 'اختيار خامة / مستلزم للفاتورة'
                          : 'اختيار صنف للفاتورة',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('add_new_variant_to_product_btn'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(
                      _isHospitality
                          ? 'إضافة وحدة توريد لخامة مسجلة'
                          : 'إضافة مقاس جديد لصنف مسجل',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddNewVariantDialog();
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                height: 450,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: _isHospitality
                            ? 'ابحث باسم الخامة، المستلزم، أو كود التوريد...'
                            : 'ابحث باسم الموديل، كود الصنف، أو اللون...',
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
                                    _isHospitality
                                        ? '${p.name} (${v.size})'
                                        : '${p.name} (${v.color} - مقاس ${v.size})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _isHospitality
                                        ? 'كود: ${v.sku} | الرصيد الحالي: ${v.quantity} ${v.size}'
                                        : 'كود: ${v.sku} | الرصيد الحالي: ${v.quantity} قطعة',
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

  Future<void> _showAddQuickRawMaterialDialog() async {
    final db = getIt<AppDatabase>();
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController(text: '50.00');
    final qtyCtrl = TextEditingController(text: '1');
    final packSizeCtrl = TextEditingController(text: '500');
    String selectedUnit = kitchenSupplyUnits.first;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.kitchen_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'إضافة خامة أو مستلزم تشغيل سريع',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      key: const Key('raw_material_name_field'),
                      controller: nameCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'اسم الخامة أو المستلزم *',
                        hintText: 'مثال: أرز بسمتي، صدور دجاج، زيت قلي، مناديل...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: const Key('raw_material_unit_dropdown'),
                      initialValue: selectedUnit,
                      decoration: const InputDecoration(
                        labelText: 'وحدة التوريد للمطبخ *',
                        border: OutlineInputBorder(),
                      ),
                      items: kitchenSupplyUnits
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedUnit = val);
                      },
                    ),
                    Builder(builder: (ctx) {
                      final isBulk = selectedUnit.contains('كرتونة') ||
                          selectedUnit.contains('باكت') ||
                          selectedUnit.contains('شيكارة') ||
                          selectedUnit.contains('جركن') ||
                          selectedUnit.contains('لتر');

                      if (!isBulk) return const SizedBox.shrink();

                      final costVal = double.tryParse(costCtrl.text.trim()) ?? 0.0;
                      final packSizeVal = int.tryParse(packSizeCtrl.text.trim()) ?? 1;
                      final unitCost = packSizeVal > 0 ? (costVal / packSizeVal) : costVal;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          TextFormField(
                            key: const Key('raw_material_pack_size_field'),
                            controller: packSizeCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'عدد الحبات / القطع داخل الوحدة (حجم العبوة) *',
                              hintText: 'مثال: 500 أو 24 أو 25000',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 2),
                            child: Text(
                              'تكلفة الحبة الواحدة: ${unitCost.toStringAsFixed(2)} ج.م',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('raw_material_cost_field'),
                            controller: costCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'سعر شراء الوحدة (ج.م) *',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const Key('raw_material_qty_field'),
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'الكمية الموردة *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                key: const Key('confirm_add_raw_material_btn'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.check, color: Colors.white, size: 18),
                label: const Text(
                  'حفظ وإدراج بالفاتورة',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    _showToast('يرجى كتابة اسم الخامة', isError: true);
                    return;
                  }
                  final cost = double.tryParse(costCtrl.text.trim()) ?? 0.0;
                  final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                  if (qty <= 0) {
                    _showToast('يرجى تحديد كمية صحيحة أكبر من صفر', isError: true);
                    return;
                  }

                  final isBulkUnit = selectedUnit.contains('كرتونة') ||
                      selectedUnit.contains('باكت') ||
                      selectedUnit.contains('شيكارة') ||
                      selectedUnit.contains('جركن') ||
                      selectedUnit.contains('لتر');
                  final packSize = isBulkUnit ? (int.tryParse(packSizeCtrl.text.trim()) ?? 1) : 1;
                  final baseUnitStr = selectedUnit.contains('شيكارة')
                      ? 'جم'
                      : (selectedUnit.contains('جركن') || selectedUnit.contains('لتر')
                          ? 'مل'
                          : 'حبة');

                  final branchId = getIt.isRegistered<BranchProvider>()
                      ? await getIt<BranchProvider>().getBranchId()
                      : 'branch_main';

                  final categories = await (db.select(db.categories)
                    ..where((c) => c.deletedAt.isNull())).get();
                  String categoryId = categories.isNotEmpty ? categories.first.id : 'cat_raw';
                  final foundCat = categories.where((c) =>
                    c.name.contains('خام') || c.name.contains('مستلزم') || c.name.contains('مطبخ')).firstOrNull;
                  if (foundCat != null) {
                    categoryId = foundCat.id;
                  }

                  final newProductId = const Uuid().v4();
                  final newVariantId = const Uuid().v4();
                  final sku = BarcodeHelper.generateSku(size: selectedUnit);
                  final culinary = RestaurantCulinaryData(
                    isRawMaterial: true,
                    purchaseUnit: selectedUnit,
                    baseUnit: isBulkUnit ? baseUnitStr : selectedUnit,
                    conversionFactor: isBulkUnit ? packSize.toDouble() : 1.0,
                  );

                  final now = DateTime.now();
                  await db.into(db.products).insert(
                    ProductsCompanion.insert(
                      id: newProductId,
                      branchId: branchId,
                      categoryId: categoryId,
                      name: name,
                      description: Value(culinary.toEncodedString()),
                      activityType: const Value('restaurantsCafes'),
                      createdAt: now,
                      updatedAt: now,
                    ),
                  );

                  await db.into(db.productVariants).insert(
                    ProductVariantsCompanion.insert(
                      id: newVariantId,
                      branchId: branchId,
                      productId: newProductId,
                      sku: sku,
                      size: selectedUnit,
                      color: 'خامة',
                      costPrice: (cost * 100).round(),
                      sellPrice: 0,
                      quantity: const Value(0),
                      createdAt: now,
                      updatedAt: now,
                    ),
                  );

                  if (!mounted) return;
                  setState(() {
                    _items.add(_InvoiceItemRow(
                      variantId: newVariantId,
                      productName: name,
                      sku: sku,
                      color: 'خامة',
                      size: selectedUnit,
                      qty: qty,
                      costPricePounds: cost,
                    ));
                  });

                  if (dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                  }
                  _showToast('تمت إضافة الخامة وإدراجها بالفاتورة بنجاح');
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddNewVariantDialog() async {
    final db = getIt<AppDatabase>();
    final allProducts = await (db.select(db.products)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();

    final products = allProducts.where((p) {
      final cul = RestaurantCulinaryData.parse(p.description);
      if (_isHospitality) {
        return cul.isRawMaterial == true;
      } else {
        return cul.isRawMaterial != true;
      }
    }).toList();

    if (!mounted) return;
    if (products.isEmpty) {
      _showToast(
        _isHospitality
            ? 'لا توجد خامات مسجلة لإضافة وحدة توريد لها'
            : 'لا توجد منتجات مسجلة لإضافة مقاس لها',
        isError: true,
      );
      return;
    }

    Product selectedProduct = products.first;
    final sizeCtrl = TextEditingController(text: _isHospitality ? kitchenSupplyUnits.first : 'L');
    final colorCtrl = TextEditingController(text: _isHospitality ? 'خامة' : 'افتراضي');
    final costCtrl = TextEditingController(text: '100.00');
    final sellCtrl = TextEditingController(text: _isHospitality ? '0.00' : '150.00');
    final qtyCtrl = TextEditingController(text: '10');

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              _isHospitality
                  ? 'إضافة وحدة توريد جديدة لخامة مسجلة'
                  : 'إضافة مقاس جديد لموديل مسجل',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<Product>(
                      isExpanded: true,
                      key: const Key('select_existing_product_dropdown'),
                      initialValue: selectedProduct,
                      decoration: InputDecoration(
                        labelText: _isHospitality
                            ? 'اختر الخامة / المستلزم المسجل *'
                            : 'اختر الموديل / المنتج المسجل *',
                        border: const OutlineInputBorder(),
                      ),
                      items: products.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedProduct = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_isHospitality) ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: const Key('new_variant_supply_unit_dropdown'),
                        initialValue: kitchenSupplyUnits.contains(sizeCtrl.text)
                            ? sizeCtrl.text
                            : kitchenSupplyUnits.first,
                        decoration: const InputDecoration(
                          labelText: 'وحدة التوريد للمطبخ *',
                          border: OutlineInputBorder(),
                        ),
                        items: kitchenSupplyUnits
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              sizeCtrl.text = val;
                            });
                          }
                        },
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('new_variant_size_field'),
                              controller: sizeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'المقاس / البعد *',
                                hintText: 'مثال: 2×3 م أو 42 أو XL',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: const Key('new_variant_color_field'),
                              controller: colorCtrl,
                              decoration: const InputDecoration(
                                labelText: 'اللون',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('new_variant_cost_field'),
                            controller: costCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: _isHospitality
                                  ? 'سعر الشراء للوحدة (ج.م) *'
                                  : 'سعر الشراء (ج.م) *',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        if (!_isHospitality) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: const Key('new_variant_sell_field'),
                              controller: sellCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'سعر البيع (ج.م) *',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('new_variant_qty_field'),
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الكمية المشتراة الموردة *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                key: const Key('confirm_add_new_variant_btn'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.check, color: Colors.white, size: 18),
                label: const Text('حفظ وإضافة للفاتورة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final size = sizeCtrl.text.trim();
                  if (size.isEmpty) {
                    _showToast(
                      _isHospitality ? 'يرجى اختيار وحدة التوريد' : 'يرجى تحديد المقاس أو البعد',
                      isError: true,
                    );
                    return;
                  }
                  final costPounds = double.tryParse(costCtrl.text.trim()) ?? 0.0;
                  final sellPounds = double.tryParse(sellCtrl.text.trim()) ?? 0.0;
                  final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                  if (qty <= 0) {
                    _showToast('يرجى إدخال كمية صحيحة أكبر من صفر', isError: true);
                    return;
                  }
                  final newVariantId = const Uuid().v4();
                  final cleanSku = BarcodeHelper.generateSku(size: size);
                  final color = _isHospitality
                      ? 'خامة'
                      : (colorCtrl.text.trim().isEmpty ? 'افتراضي' : colorCtrl.text.trim());

                  await db.into(db.productVariants).insert(
                    ProductVariantsCompanion.insert(
                      id: newVariantId,
                      branchId: selectedProduct.branchId,
                      productId: selectedProduct.id,
                      sku: cleanSku,
                      size: size,
                      color: color,
                      costPrice: (costPounds * 100).round(),
                      sellPrice: (sellPounds * 100).round(),
                      quantity: const Value(0),
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    ),
                  );

                  if (!mounted) return;
                  setState(() {
                    _items.add(_InvoiceItemRow(
                      variantId: newVariantId,
                      productName: selectedProduct.name,
                      sku: cleanSku,
                      color: color,
                      size: size,
                      qty: qty,
                      costPricePounds: costPounds,
                    ));
                  });
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  _showToast('تمت إضافة المقاس الجديد وإدراجه بالفاتورة بنجاح');
                },
              ),
            ],
          );
        },
      ),
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

  Future<void> _showEditItemPriceDialog(int index, _InvoiceItemRow item) async {
    final priceCtrl = TextEditingController(
      text: item.costPricePounds > 0 ? item.costPricePounds.toStringAsFixed(2) : '',
    );
    final qtyCtrl = TextEditingController(text: item.qty.toString());

    await showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit_note_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('تعديل سعر وتفاصيل الصنف بالفاتورة'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'كود: ${item.sku} | مقاس: ${item.size} | لون: ${item.color}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              TextField(
                key: Key('edit_item_cost_field_$index'),
                controller: priceCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'سعر الشراء للقطعة (ج.م)',
                  prefixIcon: const Icon(Icons.attach_money_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: Key('edit_item_qty_field_$index'),
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'الكمية (قطع)',
                  prefixIcon: const Icon(Icons.numbers_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            key: const Key('save_item_edit_btn'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final newPrice = double.tryParse(priceCtrl.text.trim());
              final newQty = int.tryParse(qtyCtrl.text.trim());
              if (newPrice == null || newPrice < 0) {
                _showToast('يرجى إدخال سعر شراء صحيح', isError: true);
                return;
              }
              if (newQty == null || newQty <= 0) {
                _showToast('يرجى إدخال كمية صحيحة أكبر من صفر', isError: true);
                return;
              }

              setState(() {
                item.costPricePounds = newPrice;
                item.qty = newQty;
              });

              Navigator.pop(dlgCtx);
              _showToast('تم تعديل بيانات الصنف بالفاتورة بنجاح');
            },
            child: const Text('حفظ التعديل', style: TextStyle(color: Colors.white)),
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
            goodsReceiptId: widget.initialGoodsReceipt?.id,
          );

      if (!mounted) return;

      if (created != null) {
        _showToast('تم حفظ فاتورة المشتريات وتحديث رصيد المخزن والمورد بنجاح');
        if (widget.onSaved != null) {
          widget.onSaved!();
        } else {
          Navigator.pop(context, true);
        }
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          tooltip: 'رجوع لقائمة المشتريات',
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
        title: const Text(
          'فاتورة مشتريات جديدة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Builder(
            builder: (ctx) {
              final screenWidth = MediaQuery.sizeOf(ctx).width;
              final isCompact = screenWidth < 650;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: isCompact
                    ? IconButton(
                        tooltip: 'حفظ واعتماد الفاتورة',
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
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
                                size: 20,
                              ),
                      )
                    : ElevatedButton.icon(
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
              );
            },
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final supplierWidget = BlocBuilder<SuppliersCubit, SuppliersState>(
                            builder: (context, state) {
                              return Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
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
                                            overflow: TextOverflow.ellipsis,
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
                                    icon: Icon(
                                      Icons.person_add_rounded,
                                      color: AppColors.primary,
                                    ),
                                    onPressed: _showAddSupplierDialog,
                                  ),
                                ],
                              );
                            },
                          );

                          final invoiceNumWidget = TextFormField(
                            controller: _invoiceNumController,
                            decoration: InputDecoration(
                              labelText: 'رقم الفاتورة الورقية (اختياري)',
                              prefixIcon: const Icon(Icons.receipt_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );

                          final datePickerWidget = InkWell(
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
                          );

                          if (constraints.maxWidth < 1150) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                supplierWidget,
                                const SizedBox(height: 12),
                                if (constraints.maxWidth < 650) ...[
                                  invoiceNumWidget,
                                  const SizedBox(height: 12),
                                  datePickerWidget,
                                ] else ...[
                                  Row(
                                    children: [
                                      Expanded(child: invoiceNumWidget),
                                      const SizedBox(width: 14),
                                      Expanded(child: datePickerWidget),
                                    ],
                                  ),
                                ],
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 4,
                                child: supplierWidget,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 3,
                                child: invoiceNumWidget,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                flex: 3,
                                child: datePickerWidget,
                              ),
                            ],
                          );
                        },
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
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          Text(
                            _isHospitality
                                ? 'الخامات والمستلزمات المشتراة (${_items.length})'
                                : 'الأصناف المشتراة (${_items.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              if (_isHospitality)
                                ElevatedButton.icon(
                                  key: const Key('add_raw_material_btn'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.add_circle_outline_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    '+ خامة أو مستلزم جديد',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: _showAddQuickRawMaterialDialog,
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
                                label: Text(
                                  _isHospitality
                                      ? 'إضافة خامة مسجلة'
                                      : 'إضافة صنف للفاتورة',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: _showAddVariantDialog,
                              ),
                            ],
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
                                _isHospitality
                                    ? 'لم تتم إضافة أي خامات بعد. اضغط على "+ خامة أو مستلزم جديد"'
                                    : 'لم تتم إضافة أي أصناف بعد. اضغط على "إضافة صنف للفاتورة"',
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
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    _isHospitality
                                        ? 'الخامة / المستلزم / الوحدة'
                                        : 'الصنف / المقاس / اللون',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    _isHospitality
                                        ? 'الكمية الموردة'
                                        : 'الكمية (قطعة)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    _isHospitality
                                        ? 'سعر شراء الوحدة'
                                        : 'سعر الشراء للقطعة',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'الإجمالي',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const Padding(
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
                                          _isHospitality
                                              ? 'كود: ${it.sku} | الوحدة: ${it.size}'
                                              : 'كود: ${it.sku} | لون: ${it.color} | مقاس: ${it.size}',
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
                                      _isHospitality
                                          ? '${it.qty} ${it.size}'
                                          : '${it.qty} قطعة',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                    child: InkWell(
                                      key: Key('edit_purchase_cost_btn_$idx'),
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () => _showEditItemPriceDialog(idx, it),
                                      child: Tooltip(
                                        message: 'اضغط لتعديل سعر الشراء أو الكمية',
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.blue.shade200),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${it.costPricePounds.toStringAsFixed(2)} ج.م',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue.shade900,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.edit_outlined,
                                                size: 14,
                                                color: Colors.blue.shade700,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 650;
                          final card1 = Container(
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
                          );

                          final card2 = Container(
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
                          );

                          final card3 = Container(
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
                          );

                          if (isCompact) {
                            return Column(
                              children: [
                                card1,
                                const SizedBox(height: 10),
                                card2,
                                const SizedBox(height: 10),
                                card3,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: card1),
                              const SizedBox(width: 14),
                              Expanded(child: card2),
                              const SizedBox(width: 14),
                              Expanded(child: card3),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final paidWidget = TextFormField(
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
                          );

                          final notesWidget = TextFormField(
                            controller: _notesController,
                            decoration: InputDecoration(
                              labelText: 'ملاحظات الفاتورة',
                              prefixIcon: const Icon(Icons.notes_rounded),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );

                          if (constraints.maxWidth < 650) {
                            return Column(
                              children: [
                                paidWidget,
                                const SizedBox(height: 12),
                                notesWidget,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(child: paidWidget),
                              const SizedBox(width: 14),
                              Expanded(child: notesWidget),
                            ],
                          );
                        },
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
