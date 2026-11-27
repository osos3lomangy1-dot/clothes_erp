import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/barcode_helper.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../barcode_printing/domain/models/barcode_label_item.dart';
import '../../../barcode_printing/presentation/dialogs/barcode_print_dialog.dart';
import '../../../products/domain/entities/activity_type.dart';
import '../../../products/presentation/screens/product_form_screen.dart';
import '../../../purchases/presentation/screens/create_purchase_screen.dart';
import '../../data/datasources/inventory_local_data_source.dart';
import '../../data/services/device_serial_service.dart';
import '../cubits/goods_receipt_cubit.dart';
import '../widgets/serial_units_entry_dialog.dart';
import '../widgets/used_device_intake_dialog.dart';

class _ReceiptLineItem {
  final String variantId;
  final String productName;
  final String sku;
  final String color;
  final String size;
  int quantity;
  double? costPricePounds;
  List<String> imeis;

  _ReceiptLineItem({
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.color,
    required this.size,
    required this.quantity,
    this.costPricePounds,
    List<String>? imeis,
  }) : imeis = imeis ?? [];
}

class BlindReceiveScreen extends StatelessWidget {
  final VoidCallback? onBack;

  const BlindReceiveScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<GoodsReceiptCubit>(),
      child: _BlindReceiveView(onBack: onBack),
    );
  }
}

class _BlindReceiveView extends StatefulWidget {
  final VoidCallback? onBack;

  const _BlindReceiveView({this.onBack});

  @override
  State<_BlindReceiveView> createState() => _BlindReceiveViewState();
}

class _BlindReceiveViewState extends State<_BlindReceiveView> {
  final _searchController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  final _notesController = TextEditingController();

  final List<_ReceiptLineItem> _lines = [];
  bool _isSaving = false;
  bool _mobileImeiEnabled = false;

  @override
  void initState() {
    super.initState();
    if (getIt.isRegistered<FeatureGate>()) {
      try {
        getIt<FeatureGate>()
            .isEnabled(FeatureKeys.mobileImeiUsed)
            .then((enabled) {
          if (mounted && enabled != _mobileImeiEnabled) {
            setState(() => _mobileImeiEnabled = enabled);
          }
        }).catchError((_) {});
      } catch (_) {}
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleBarcodeSubmitted(String code) async {
    final query = code.trim();
    if (query.isEmpty) return;
    _barcodeController.clear();

    final db = getIt<AppDatabase>();
    final row = await (db.select(db.productVariants).join([
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productVariants.productId),
      ),
    ])..where(
      db.productVariants.sku.equals(query) &
          db.productVariants.deletedAt.isNull() &
          db.products.deletedAt.isNull(),
    )).getSingleOrNull();

    if (row != null) {
      final v = row.readTable(db.productVariants);
      final p = row.readTable(db.products);
      _addOrIncrementVariant(
        variantId: v.id,
        productName: p.name,
        sku: v.sku,
        color: v.color,
        size: v.size,
        costPricePounds: v.costPrice > 0 ? (v.costPrice / 100.0) : null,
      );
    } else {
      _showToast('لم يتم العثور على صنف بالباركود: $query', isError: true);
    }
    _barcodeFocusNode.requestFocus();
  }

  void _addOrIncrementVariant({
    required String variantId,
    required String productName,
    required String sku,
    required String color,
    required String size,
    int addQty = 1,
    double? costPricePounds,
    bool showToast = true,
  }) {
    setState(() {
      final existingIndex = _lines.indexWhere((l) => l.variantId == variantId);
      if (existingIndex >= 0) {
        _lines[existingIndex].quantity += addQty;
        if (costPricePounds != null &&
            costPricePounds > 0 &&
            (_lines[existingIndex].costPricePounds == null ||
                _lines[existingIndex].costPricePounds == 0)) {
          _lines[existingIndex].costPricePounds = costPricePounds;
        }
      } else {
        _lines.add(_ReceiptLineItem(
          variantId: variantId,
          productName: productName,
          sku: sku,
          color: color,
          size: size,
          quantity: addQty,
          costPricePounds: costPricePounds,
        ));
      }
    });
    if (showToast) {
      _showToast('تمت إضافة: $productName ($size - $color)');
    }
  }

  Future<void> _openSearchVariantDialog() async {
    final db = getIt<AppDatabase>();
    final rows = await (db.select(db.productVariants).join([
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productVariants.productId),
      ),
    ])..where(
      db.productVariants.deletedAt.isNull() &
          db.products.deletedAt.isNull(),
    )).get();

    if (!mounted) return;
    if (rows.isEmpty) {
      _showToast('لا توجد أصناف مسجلة بالمحل حالياً', isError: true);
      return;
    }

    String searchFilter = '';
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = rows.where((r) {
            final v = r.readTable(db.productVariants);
            final p = r.readTable(db.products);
            final q = searchFilter.toLowerCase().trim();
            if (q.isEmpty) return true;
            return p.name.toLowerCase().contains(q) ||
                v.sku.toLowerCase().contains(q) ||
                v.color.toLowerCase().contains(q) ||
                v.size.toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: AppColors.primary),
                SizedBox(width: 8),
                Text('اختيار صنف للاستلام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 580,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو الكود أو الباركود...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (val) => setDialogState(() => searchFilter = val),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      key: const Key('search_dialog_add_variant_btn'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('إضافة مقاس جديد لصنف مسجل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        _showAddNewVariantToExistingProductDialog();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: filtered.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Center(child: Text('لا توجد نتائج مطابقة للبحث')),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (c, i) => const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final r = filtered[idx];
                              final v = r.readTable(db.productVariants);
                              final p = r.readTable(db.products);

                              final existingIndex = _lines.indexWhere((l) => l.variantId == v.id);
                              final currentQtyInShipment = existingIndex >= 0 ? _lines[existingIndex].quantity : 0;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                      child: Icon(Icons.inventory_2_rounded, color: AppColors.primary),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                              if (currentQtyInShipment > 0)
                                                Container(
                                                  key: Key('search_item_added_badge_${v.id}'),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.shade50,
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: Colors.green.shade300),
                                                  ),
                                                  child: Text(
                                                    'تمت إضافة +1 | الإجمالي: $currentQtyInShipment',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.green.shade800,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'المقاس: ${v.size} | اللون: ${v.color} | SKU: ${v.sku}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      key: Key('search_add_item_btn_${v.id}'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: const Icon(Icons.add, size: 16, color: Colors.white),
                                      label: const Text('إضافة', style: TextStyle(color: Colors.white)),
                                      onPressed: () {
                                        _addOrIncrementVariant(
                                          variantId: v.id,
                                          productName: p.name,
                                          sku: v.sku,
                                          color: v.color,
                                          size: v.size,
                                          costPricePounds: v.costPrice > 0 ? (v.costPrice / 100.0) : null,
                                          showToast: false,
                                        );
                                        setDialogState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                key: const Key('search_dialog_done_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.done_all_rounded, size: 18, color: Colors.white),
                label: Text(
                  'تم والعودة للشحنة ($_totalItemsCount قطعة)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: () => Navigator.pop(dialogCtx),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddNewVariantToExistingProductDialog() async {
    final db = getIt<AppDatabase>();
    final products = await (db.select(db.products)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();

    if (!mounted) return;
    if (products.isEmpty) {
      _showToast('لا توجد منتجات مسجلة لإضافة مقاس لها', isError: true);
      return;
    }

    Product selectedProduct = products.first;
    final sizeCtrl = TextEditingController(text: 'L');
    final colorCtrl = TextEditingController(text: 'افتراضي');
    final costCtrl = TextEditingController(text: '100.00');
    final sellCtrl = TextEditingController(text: '150.00');
    final qtyCtrl = TextEditingController(text: '10');

    List<String> getSizesForProduct(Product p) {
      final act = ActivityType.fromString(p.activityType);
      switch (act) {
        case ActivityType.clothing:
          return const ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL', 'Free Size'];
        case ActivityType.footwearBags:
          return const ['37', '38', '39', '40', '41', '42', '43', '44', '45'];
        case ActivityType.textilesDecor:
          return const ['1.5×2 م', '2×3 م', '2.5×3.5 م', '3×4 م', 'مشاية 1×3 م', 'مشاية 80×2 م', 'رول كامل', 'بالمتر'];
        default:
          return act.standardSizes.isNotEmpty
              ? act.standardSizes
              : const ['S', 'M', 'L', 'XL', '2XL', 'Free Size'];
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final adaptiveSizes = getSizesForProduct(selectedProduct);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.style_outlined, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text('إضافة مقاس جديد لصنف مسجل في الشحنة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<Product>(
                      key: const Key('select_existing_product_dropdown'),
                      initialValue: selectedProduct,
                      decoration: const InputDecoration(
                        labelText: 'اختر الموديل / المنتج المسجل *',
                        border: OutlineInputBorder(),
                      ),
                      items: products.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedProduct = val;
                            final newSizes = getSizesForProduct(val);
                            if (newSizes.isNotEmpty) {
                              sizeCtrl.text = newSizes.first;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'المقاسات السريعة (${ActivityType.fromString(selectedProduct.activityType).labelArabic}):',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in adaptiveSizes)
                          ActionChip(
                            key: Key('shipment_size_chip_$s'),
                            label: Text(s, style: TextStyle(fontSize: 11, fontWeight: sizeCtrl.text == s ? FontWeight.bold : FontWeight.normal)),
                            backgroundColor: sizeCtrl.text == s ? AppColors.primary.withValues(alpha: 0.15) : const Color(0xFFF1F5F9),
                            side: BorderSide(color: sizeCtrl.text == s ? AppColors.primary : Colors.grey.shade300),
                            onPressed: () => setDialogState(() => sizeCtrl.text = s),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('new_variant_cost_field'),
                            controller: costCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'سعر الشراء / التكلفة (ج.م) *',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
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
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('new_variant_qty_field'),
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'الكمية المستلمة في الشحنة *',
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
              OutlinedButton.icon(
                key: const Key('save_and_add_another_variant_btn'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary),
                ),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('حفظ وإضافة مقاس آخر لنفس الموديل', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final size = sizeCtrl.text.trim();
                  if (size.isEmpty) {
                    _showToast('يرجى تحديد المقاس أو البعد', isError: true);
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
                  final color = colorCtrl.text.trim().isEmpty ? 'افتراضي' : colorCtrl.text.trim();

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
                    _lines.add(_ReceiptLineItem(
                      variantId: newVariantId,
                      productName: selectedProduct.name,
                      sku: cleanSku,
                      color: color,
                      size: size,
                      quantity: qty,
                      costPricePounds: costPounds > 0 ? costPounds : null,
                    ));
                  });

                  setDialogState(() {
                    final newSizes = getSizesForProduct(selectedProduct);
                    final existingSizes = _lines.where((l) => l.productName == selectedProduct.name).map((l) => l.size).toSet();
                    final remaining = newSizes.where((s) => !existingSizes.contains(s)).toList();
                    sizeCtrl.text = remaining.isNotEmpty ? remaining.first : '';
                  });
                  _showToast('تم حفظ المقاس وإدراجه بالشحنة - يمكنك إدخال المقاس التالي لنفس الموديل');
                },
              ),
              ElevatedButton.icon(
                key: const Key('confirm_add_new_variant_btn'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.check, color: Colors.white, size: 18),
                label: const Text('حفظ وإنهاء', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final size = sizeCtrl.text.trim();
                  if (size.isEmpty) {
                    _showToast('يرجى تحديد المقاس أو البعد', isError: true);
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
                  final color = colorCtrl.text.trim().isEmpty ? 'افتراضي' : colorCtrl.text.trim();

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
                    _lines.add(_ReceiptLineItem(
                      variantId: newVariantId,
                      productName: selectedProduct.name,
                      sku: cleanSku,
                      color: color,
                      size: size,
                      quantity: qty,
                      costPricePounds: costPounds > 0 ? costPounds : null,
                    ));
                  });
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  _showToast('تمت إضافة المقاس الجديد وإدراجه بالشحنة المستلمة بنجاح');
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openQuickAddVariantDialog() async {
    // Open product/variant creation dialog
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ProductFormDialog(),
    );
    if (mounted) {
      _showToast('إذا تم حفظ الصنف الجديد، يمكنك اختياره الآن من البحث أو الباركود');
    }
  }

  Future<void> _openPrintShipmentBarcodesDialog() async {
    if (_lines.isEmpty) return;
    final db = getIt<AppDatabase>();
    final variantIds = _lines.map((l) => l.variantId).toList();
    final variants = await (db.select(db.productVariants)..where((v) => v.id.isIn(variantIds))).get();
    final priceMap = {for (final v in variants) v.id: v.sellPrice};
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => BarcodePrintDialog(
        title: 'طباعة باركودات الشحنة المستلمة',
        initialItems: _lines.map((l) => BarcodeLabelItem(
          variantId: l.variantId,
          productName: l.productName,
          sku: l.sku,
          color: l.color,
          size: l.size,
          salePricePiasters: priceMap[l.variantId] ?? 0,
          copies: l.quantity,
        )).toList(),
      ),
    );
  }

  Future<void> _showEditCostDialog(_ReceiptLineItem line) async {
    final costCtrl = TextEditingController(
      text: line.costPricePounds != null && line.costPricePounds! > 0
          ? line.costPricePounds!.toStringAsFixed(2)
          : '',
    );

    await showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.monetization_on_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تحديد سعر الشراء / التكلفة (${line.productName} - ${line.size})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'أدخل سعر الشراء للقطعة الواحدة (ج.م):',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('cost_price_input_field'),
                controller: costCtrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'سعر الشراء (ج.م)',
                  hintText: 'مثال: 120.00',
                  suffixText: 'ج.م',
                  border: OutlineInputBorder(),
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
            key: const Key('confirm_edit_cost_btn'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final parsed = double.tryParse(costCtrl.text.trim());
              setState(() {
                line.costPricePounds = (parsed != null && parsed > 0) ? parsed : null;
              });

              if (parsed != null && parsed > 0) {
                final db = getIt<AppDatabase>();
                await (db.update(db.productVariants)
                      ..where((v) => v.id.equals(line.variantId)))
                    .write(ProductVariantsCompanion(
                  costPrice: Value((parsed * 100).round()),
                  updatedAt: Value(DateTime.now()),
                ));
              }

              if (dlgCtx.mounted) {
                Navigator.pop(dlgCtx);
              }
              _showToast('تم تحديث سعر الشراء للصنف');
            },
            child: const Text('حفظ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveReceipt() async {
    if (_lines.isEmpty) {
      _showToast('يرجى إضافة صنف واحد على الأقل للشحنة', isError: true);
      return;
    }
    await _showShipmentSummaryModal();
  }

  bool get _isCashier {
    try {
      final authState = context.read<AuthCubit>().state;
      return authState is AuthAuthenticated &&
          authState.user.role.toLowerCase() == 'cashier';
    } catch (_) {
      return false;
    }
  }

  Future<void> _showShipmentSummaryModal() async {
    final authState = context.read<AuthCubit>().state;
    final isCashier = _isCashier;
    String cashierName = 'كاشير المحل';
    if (authState is AuthAuthenticated) {
      cashierName = authState.user.name.isNotEmpty ? authState.user.name : authState.user.id;
    }

    final distinctProducts = _lines.map((l) => l.productName).toSet().length;
    final totalPieces = _totalItemsCount;
    final totalCostPounds = _lines.fold(0.0, (sum, l) => sum + (l.quantity * (l.costPricePounds ?? 0.0)));
    final notes = _notesController.text.trim();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.inventory_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('ملخص شحنة البضاعة المستلمة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        children: [
                          Text('عدد الأصناف', style: TextStyle(fontSize: 12, color: Colors.blue.shade800)),
                          const SizedBox(height: 4),
                          Text('$distinctProducts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Column(
                        children: [
                          Text('إجمالي القطع', style: TextStyle(fontSize: 12, color: Colors.purple.shade800)),
                          const SizedBox(height: 4),
                          Text('$totalPieces', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.purple.shade900)),
                        ],
                      ),
                    ),
                  ),
                  if (!isCashier) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.secondary.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            Text('إجمالي التكلفة',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.secondary)),
                            const SizedBox(height: 4),
                            Text('${totalCostPounds.toStringAsFixed(2)} ج.م',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 18, color: Colors.grey),
                        const SizedBox(width: 6),
                        const Text('المستلم: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(cashierName, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notes_outlined, size: 18, color: Colors.grey),
                          const SizedBox(width: 6),
                          const Text('ملاحظات: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Expanded(child: Text(notes, style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'يمكنك حفظ الشحنة مباشرة لزيادة المخزون فقط، أو حفظها والتحويل المباشر لإنشاء فاتورة مشتريات للمورد.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('متابعة التعديل'),
          ),
          OutlinedButton.icon(
            key: const Key('save_shipment_only_btn'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.green.shade700,
              side: BorderSide(color: Colors.green.shade700),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('حفظ كشحنة مخزنية فقط', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _executeSaveGoodsReceipt(convertToPurchase: false, dialogCtx: dlgCtx),
          ),
          ElevatedButton.icon(
            key: const Key('save_and_convert_to_purchase_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 18),
            label: const Text('حفظ والتحويل لفاتورة مشتريات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => _executeSaveGoodsReceipt(convertToPurchase: true, dialogCtx: dlgCtx),
          ),
        ],
      ),
    );
  }

  Future<void> _executeSaveGoodsReceipt({
    required bool convertToPurchase,
    required BuildContext dialogCtx,
  }) async {
    final cubit = context.read<GoodsReceiptCubit>();
    final authState = context.read<AuthCubit>().state;
    String cashierId = 'cashier';
    if (authState is AuthAuthenticated) {
      cashierId = authState.user.name.isNotEmpty ? authState.user.name : authState.user.id;
    }

    setState(() => _isSaving = true);
    if (dialogCtx.mounted) {
      Navigator.pop(dialogCtx);
    }

    try {
      final db = getIt<AppDatabase>();
      for (final line in _lines) {
        if (line.costPricePounds != null && line.costPricePounds! > 0) {
          await (db.update(db.productVariants)
                ..where((v) => v.id.equals(line.variantId)))
              .write(ProductVariantsCompanion(
            costPrice: Value((line.costPricePounds! * 100).round()),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }

      final items = _lines.map((l) => GoodsReceiptDraftItem(
        variantId: l.variantId,
        quantity: l.quantity,
      )).toList();

      final receipt = await cubit.createGoodsReceipt(
        items: items,
        cashierId: cashierId,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (!mounted) return;

      if (receipt != null) {
        final linesWithImeis =
            _lines.where((l) => l.imeis.isNotEmpty).toList();
        if (linesWithImeis.isNotEmpty) {
          final serialSvc = getIt.isRegistered<DeviceSerialService>()
              ? getIt<DeviceSerialService>()
              : DeviceSerialService(
                  getIt<AppDatabase>(),
                  getIt.isRegistered<BranchProvider>()
                      ? getIt<BranchProvider>()
                      : BranchProvider(getIt<AppDatabase>()),
                  getIt.isRegistered<TxWriter>()
                      ? getIt<TxWriter>()
                      : TxWriter(getIt<AppDatabase>()),
                );
          for (final l in linesWithImeis) {
            await serialSvc.registerSerialUnits(
              variantId: l.variantId,
              imeis: l.imeis,
              buyPricePiasters: ((l.costPricePounds ?? 0.0) * 100).round(),
              userId: cashierId,
            );
          }
        }
        if (!mounted) return;
        _showToast('تم حفظ استلام الشحنة بنجاح وزيادة المخزون مباشرة!');

        if (convertToPurchase) {
          final initialItems = _lines.map((l) => PurchaseInitialItem(
            variantId: l.variantId,
            productName: l.productName,
            sku: l.sku,
            color: l.color,
            size: l.size,
            qty: l.quantity,
            costPricePounds: l.costPricePounds ?? 0.0,
          )).toList();

          setState(() {
            _lines.clear();
            _notesController.clear();
          });

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreatePurchaseScreen(
                initialItems: initialItems,
                initialGoodsReceipt: receipt,
                onSaved: () {
                  if (mounted && Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          );
        } else {
          setState(() {
            _lines.clear();
            _notesController.clear();
          });
          if (widget.onBack != null) {
            widget.onBack!();
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        }
      } else {
        _showToast(cubit.state.errorMessage ?? 'فشل حفظ الشحنة', isError: true);
      }
    } catch (e) {
      _showToast('فشل حفظ الشحنة: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  int get _totalItemsCount => _lines.fold(0, (sum, l) => sum + l.quantity);

  Future<void> _handleEscBack() async {
    if (_lines.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('تأكيد الرجوع', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text(
            'توجد أصناف مضافة في الشحنة لم تُحفظ بعد. هل تريد الرجوع وتجاهلها؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('بقاء'),
            ),
            ElevatedButton(
              key: const Key('confirm_discard_esc_btn'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تجاهل ورجوع', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (widget.onBack != null) {
      widget.onBack!();
    } else if (Navigator.canPop(context)) {
      await Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final isCashier =
        authState is AuthAuthenticated && authState.user.role == 'cashier';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () =>
            _barcodeFocusNode.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f3):
            _openQuickAddVariantDialog,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (!_isSaving && _totalItemsCount > 0) {
            _saveReceipt();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f12): () {
          if (!_isSaving && _totalItemsCount > 0) {
            _saveReceipt();
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscBack,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: (isCashier || widget.onBack != null || Navigator.canPop(context))
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                tooltip: 'رجوع',
                onPressed: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
              )
            : null,
        title: const Text(
          'استلام بضاعة جديدة',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.onSurface),
        ),
        actions: [
          OutlinedButton.icon(
            key: const Key('blind_receive_add_variant_btn'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(Icons.style_outlined, color: AppColors.primary, size: 18),
            label: const Text('إضافة مقاس لصنف مسجل', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _showAddNewVariantToExistingProductDialog,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(Icons.add_box_rounded, color: AppColors.primary, size: 18),
            label: const Text('إضافة صنف جديد كلياً', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _openQuickAddVariantDialog,
          ),
          if (_mobileImeiEnabled) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const Key('open_used_device_intake_btn'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(Icons.phone_android_rounded, color: AppColors.primary, size: 18),
              label: const Text('شراء مستعمل', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () async {
                final res = await UsedDeviceIntakeDialog.show(context);
                if (res != null && mounted) {
                  _showToast('تم تسجيل الجهاز المستعمل (${res.imei}) وإضافته للمخزون');
                }
              },
            ),
          ],
          const SizedBox(width: 8),
          if (_lines.isNotEmpty) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 18),
              label: Text('طباعة ملصقات (${_lines.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: _openPrintShipmentBarcodesDialog,
            ),
            const SizedBox(width: 8),
          ],
          ElevatedButton.icon(
            key: const Key('save_shipment_appbar_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _totalItemsCount > 0 ? AppColors.primary : const Color(0xFFE2E8F0),
              foregroundColor: _totalItemsCount > 0 ? Colors.white : const Color(0xFF94A3B8),
              disabledBackgroundColor: const Color(0xFFE2E8F0),
              disabledForegroundColor: const Color(0xFF94A3B8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    Icons.check_circle_rounded,
                    color: _totalItemsCount > 0 && !_isSaving ? Colors.white : const Color(0xFF94A3B8),
                    size: 18,
                  ),
            label: Text(
              _isSaving ? 'جاري الحفظ...' : 'حفظ الشحنة ($_totalItemsCount قطعة)',
              style: TextStyle(
                color: _totalItemsCount > 0 && !_isSaving ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: (_isSaving || _totalItemsCount == 0) ? null : _saveReceipt,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Top Controls Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _barcodeController,
                      focusNode: _barcodeFocusNode,
                      decoration: InputDecoration(
                        labelText: 'مسح بالباركود (Scanner)',
                        hintText: 'امسح باركود القطعة واضغط Enter...',
                        prefixIcon: Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onSubmitted: _handleBarcodeSubmitted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                    label: const Text('بحث واختيار من القائمة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: _openSearchVariantDialog,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        labelText: 'ملاحظات الشحنة (اختياري)',
                        hintText: 'مثال: كرتونة قادمة مع المندوب أحمد...',
                        prefixIcon: const Icon(Icons.note_alt_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Items Table
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _lines.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'لم يتم إدراج أي أصناف في شحنة الاستلام بعد',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'استخدم قارئ الباركود أو زر البحث لإضافة الأصناف والكميات المستلمة.',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 40, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                                const Expanded(flex: 3, child: Text('اسم المنتج / الموديل', style: TextStyle(fontWeight: FontWeight.bold))),
                                const Expanded(flex: 2, child: Text('كود الصنف / SKU', style: TextStyle(fontWeight: FontWeight.bold))),
                                const Expanded(flex: 1, child: Text('المقاس', style: TextStyle(fontWeight: FontWeight.bold))),
                                const Expanded(flex: 1, child: Text('اللون', style: TextStyle(fontWeight: FontWeight.bold))),
                                if (!_isCashier)
                                  const Expanded(flex: 2, child: Center(child: Text('سعر الشراء', style: TextStyle(fontWeight: FontWeight.bold)))),
                                const Expanded(flex: 2, child: Center(child: Text('الكمية المستلمة', style: TextStyle(fontWeight: FontWeight.bold)))),
                                const SizedBox(width: 50, child: Center(child: Text('حذف', style: TextStyle(fontWeight: FontWeight.bold)))),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              itemCount: _lines.length,
                              separatorBuilder: (c, i) => const Divider(height: 1),
                              itemBuilder: (ctx, idx) {
                                final line = _lines[idx];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 40,
                                        child: Text('${idx + 1}', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(line.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(line.sku, style: TextStyle(color: Colors.grey.shade700)),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Text(line.size, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Text(line.color),
                                      ),
                                      if (!_isCashier)
                                        Expanded(
                                          flex: 2,
                                          child: Center(
                                            child: InkWell(
                                              key: Key('edit_cost_price_btn_${line.variantId}'),
                                              onTap: () => _showEditCostDialog(line),
                                              borderRadius: BorderRadius.circular(8),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: (line.costPricePounds != null && line.costPricePounds! > 0)
                                                      ? AppColors.secondary.withValues(alpha: 0.1)
                                                      : AppColors.warningContainer,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: (line.costPricePounds != null && line.costPricePounds! > 0)
                                                        ? AppColors.secondary.withValues(alpha: 0.4)
                                                        : AppColors.warning.withValues(alpha: 0.4),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      (line.costPricePounds != null && line.costPricePounds! > 0)
                                                          ? '${line.costPricePounds!.toStringAsFixed(2)} ج.م'
                                                          : 'حدد السعر',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: (line.costPricePounds != null && line.costPricePounds! > 0)
                                                            ? AppColors.primary
                                                            : AppColors.warning,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Icon(
                                                      Icons.edit_outlined,
                                                      size: 14,
                                                      color: (line.costPricePounds != null && line.costPricePounds! > 0)
                                                          ? AppColors.secondary
                                                          : AppColors.warning,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            IconButton(
                                              icon: Icon(Icons.remove_circle_outline, color: AppColors.primary, size: 22),
                                              onPressed: () {
                                                setState(() {
                                                  if (line.quantity > 1) {
                                                    line.quantity--;
                                                  } else {
                                                    _lines.removeAt(idx);
                                                  }
                                                });
                                              },
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.grey.shade300),
                                              ),
                                              child: Text(
                                                '${line.quantity}',
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(Icons.add_circle_outline, color: AppColors.primary, size: 22),
                                              onPressed: () {
                                                setState(() {
                                                  line.quantity++;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                        SizedBox(
                                          width: _mobileImeiEnabled ? 96 : 50,
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              if (_mobileImeiEnabled)
                                                IconButton(
                                                  key: Key('line_imei_btn_${line.variantId}'),
                                                  icon: Icon(
                                                    Icons.qr_code_2_rounded,
                                                    color: line.imeis.isNotEmpty
                                                        ? AppColors.primary
                                                        : Colors.grey.shade600,
                                                  ),
                                                  tooltip: 'أرقام IMEI (${line.imeis.length})',
                                                  onPressed: () async {
                                                    final updated = await SerialUnitsEntryDialog.show(
                                                      context,
                                                      productName: line.productName,
                                                      targetQty: line.quantity,
                                                      initialImeis: line.imeis,
                                                    );
                                                    if (updated != null && mounted) {
                                                      setState(() => line.imeis = updated);
                                                    }
                                                  },
                                                ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                                tooltip: 'حذف من الشحنة',
                                                onPressed: () {
                                                  setState(() => _lines.removeAt(idx));
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    ),
    ),
    );
  }
}
