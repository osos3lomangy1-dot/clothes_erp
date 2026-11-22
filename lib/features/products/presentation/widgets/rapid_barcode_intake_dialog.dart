import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/presentation/cubits/category_cubit.dart';
import '../../../categories/presentation/cubits/category_state.dart';
import '../../../product_variants/data/datasources/variant_local_data_source.dart';
import '../../data/datasources/product_local_data_source.dart';

class ScannedSessionItem {
  final String name;
  final String barcode;
  final int sellPrice;
  final int addedQty;
  final bool isExisting;
  final DateTime timestamp;

  const ScannedSessionItem({
    required this.name,
    required this.barcode,
    required this.sellPrice,
    required this.addedQty,
    required this.isExisting,
    required this.timestamp,
  });
}

class RapidBarcodeIntakeDialog extends StatefulWidget {
  const RapidBarcodeIntakeDialog({super.key});

  @override
  State<RapidBarcodeIntakeDialog> createState() =>
      _RapidBarcodeIntakeDialogState();
}

class _RapidBarcodeIntakeDialogState extends State<RapidBarcodeIntakeDialog> {
  final TextEditingController _barcodeCtrl = TextEditingController();
  final FocusNode _barcodeFocus = FocusNode();

  final TextEditingController _nameCtrl = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  final TextEditingController _costCtrl = TextEditingController(text: '0.00');
  final FocusNode _costFocus = FocusNode();

  final TextEditingController _sellCtrl = TextEditingController(text: '0.00');
  final FocusNode _sellFocus = FocusNode();

  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final FocusNode _qtyFocus = FocusNode();

  bool _isLinkToExistingMode = false;
  List<Product> _existingProducts = [];
  Product? _selectedProduct;
  final TextEditingController _linkSizeCtrl = TextEditingController(text: 'L');
  final TextEditingController _linkColorCtrl = TextEditingController(text: 'افتراضي');
  final TextEditingController _linkCostCtrl = TextEditingController(text: '100.00');
  final TextEditingController _linkSellCtrl = TextEditingController(text: '150.00');
  final TextEditingController _linkQtyCtrl = TextEditingController(text: '10');

  String? _selectedCategoryId;
  bool _isChecking = false;
  bool _isSaving = false;
  bool _showNewProductForm = false;
  String _currentBarcode = '';

  final List<ScannedSessionItem> _sessionItems = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _barcodeFocus.dispose();
    _nameCtrl.dispose();
    _nameFocus.dispose();
    _costCtrl.dispose();
    _costFocus.dispose();
    _sellCtrl.dispose();
    _sellFocus.dispose();
    _qtyCtrl.dispose();
    _qtyFocus.dispose();
    _linkSizeCtrl.dispose();
    _linkColorCtrl.dispose();
    _linkCostCtrl.dispose();
    _linkSellCtrl.dispose();
    _linkQtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingProducts() async {
    final db = getIt<AppDatabase>();
    final products = await (db.select(db.products)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.name)]))
        .get();
    if (!mounted) return;
    setState(() {
      _existingProducts = products;
      if (products.isNotEmpty && (_selectedProduct == null || !products.any((p) => p.id == _selectedProduct?.id))) {
        _selectedProduct = products.first;
      }
    });
  }

  Future<void> _saveLinkedVariant() async {
    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار المنتج المسجل أولاً'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final size = _linkSizeCtrl.text.trim();
    if (size.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('المقاس أو البعد مطلوب'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final cost = _parsePiasters(_linkCostCtrl.text);
    final sell = _parsePiasters(_linkSellCtrl.text);
    final qty = int.tryParse(_linkQtyCtrl.text.trim()) ?? 1;

    setState(() => _isSaving = true);
    try {
      final db = getIt<AppDatabase>();
      final newId = const Uuid().v4();
      final p = _selectedProduct!;
      final color = _linkColorCtrl.text.trim().isEmpty ? 'افتراضي' : _linkColorCtrl.text.trim();

      await db.into(db.productVariants).insert(
        ProductVariantsCompanion.insert(
          id: newId,
          branchId: p.branchId,
          productId: p.id,
          sku: _currentBarcode,
          size: size,
          color: color,
          costPrice: cost,
          sellPrice: sell,
          quantity: Value(qty),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      if (!mounted) return;
      setState(() {
        _sessionItems.insert(
          0,
          ScannedSessionItem(
            name: '${p.name} ($size)',
            barcode: _currentBarcode,
            sellPrice: sell,
            addedQty: qty,
            isExisting: false,
            timestamp: DateTime.now(),
          ),
        );
        _showNewProductForm = false;
        _isSaving = false;
        _barcodeCtrl.clear();
        _barcodeFocus.requestFocus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء حفظ المقاس: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  int _parsePiasters(String text) {
    final cleaned = text.trim().replaceAll(',', '');
    final val = double.tryParse(cleaned) ?? 0.0;
    return (val * 100).round();
  }

  Future<void> _handleBarcodeScan(String rawBarcode) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty) return;

    setState(() {
      _isChecking = true;
      _showNewProductForm = false;
      _currentBarcode = barcode;
    });

    try {
      if (getIt.isRegistered<VariantLocalDataSource>()) {
        final variantDs = getIt<VariantLocalDataSource>();
        final all = await variantDs.getAllVariants();
        ProductVariant? matchedVariant;
        for (final v in all) {
          if (v.sku.trim() == barcode) {
            matchedVariant = v;
            break;
          }
        }

        if (matchedVariant != null) {
          // Existing product: Quick stock increment
          if (!mounted) return;
          final authState = context.read<AuthCubit>().state;
          final userId =
              authState is AuthAuthenticated ? authState.user.id : 'admin';

          final newQty = matchedVariant.quantity + 1;
          await variantDs.updateVariant(
            matchedVariant.id,
            quantity: newQty,
            userId: userId,
          );

          String productName = matchedVariant.sku;
          if (getIt.isRegistered<ProductLocalDataSource>()) {
            final p = await getIt<ProductLocalDataSource>().getProduct(matchedVariant.productId);
            if (p != null && p.name.isNotEmpty) {
              productName = p.name;
            }
          }

          if (!mounted) return;
          setState(() {
            _sessionItems.insert(
              0,
              ScannedSessionItem(
                name: productName,
                barcode: matchedVariant!.sku,
                sellPrice: matchedVariant.sellPrice,
                addedQty: 1,
                isExisting: true,
                timestamp: DateTime.now(),
              ),
            );
            _barcodeCtrl.clear();
            _isChecking = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(milliseconds: 1400),
              backgroundColor: Colors.teal.shade800,
              content: Text(
                'تم زيادة رصيد: "$productName" (+1) -> الإجمالي: $newQty',
              ),
            ),
          );

          _barcodeFocus.requestFocus();
          return;
        }
      }

      // New product: Show quick entry fields
      setState(() {
        _isChecking = false;
        _showNewProductForm = true;
        _nameCtrl.clear();
        _costCtrl.text = '0.00';
        _sellCtrl.text = '0.00';
        _qtyCtrl.text = '1';
      });

      _nameFocus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isChecking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ أثناء فحص الباركود: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      _barcodeFocus.requestFocus();
    }
  }

  Future<void> _saveNewProduct() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اسم المنتج مطلوب'),
          backgroundColor: AppColors.error,
        ),
      );
      _nameFocus.requestFocus();
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار قسم أو تصنيف للصنف'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final cost = _parsePiasters(_costCtrl.text);
    final sell = _parsePiasters(_sellCtrl.text);
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;

    setState(() => _isSaving = true);

    try {
      final productDs = getIt<ProductLocalDataSource>();
      final authState = context.read<AuthCubit>().state;
      final userId =
          authState is AuthAuthenticated ? authState.user.id : 'admin';

      await productDs.createProductWithVariants(
        name: name,
        categoryId: _selectedCategoryId!,
        minStock: 5,
        userId: userId,
        variants: [
          VariantInput(
            size: '-',
            color: '-',
            sku: _currentBarcode,
            costPrice: cost,
            sellPrice: sell,
            quantity: qty,
          ),
        ],
      );

      if (!mounted) return;

      setState(() {
        _sessionItems.insert(
          0,
          ScannedSessionItem(
            name: name,
            barcode: _currentBarcode,
            sellPrice: sell,
            addedQty: qty,
            isExisting: false,
            timestamp: DateTime.now(),
          ),
        );
        _showNewProductForm = false;
        _isSaving = false;
        _barcodeCtrl.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green.shade800,
          content: Text('تمت إضافة الصنف الجديد: "$name" بالباركود: $_currentBarcode'),
        ),
      );

      _barcodeFocus.requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final msg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Color(0xFF2E7D32),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner_rounded,
                      color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المسح السريع للمنتجات (نمط السوبر ماركت والبقالة)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'امسح الباركود بالماسح الضوئي: إن كان مسجلاً يُضاف للرصيد فوراً، وإن كان جديداً تدخله في ثوانٍ',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ),

            // Scan Input Bar
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextField(
                    controller: _barcodeCtrl,
                    focusNode: _barcodeFocus,
                    textInputAction: TextInputAction.go,
                    onSubmitted: _handleBarcodeScan,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: 'امسح باركود المنتج بالسكانر (أو اكتبه واضغط Enter)',
                      hintText: 'مثال: 6223000543210',
                      prefixIcon: const Icon(Icons.scanner_rounded, color: Color(0xFF2E7D32), size: 28),
                      suffixIcon: _isChecking
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF2E7D32)),
                              tooltip: 'فحص الباركود',
                              onPressed: () => _handleBarcodeScan(_barcodeCtrl.text),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
                      ),
                    ),
                  ),

                  // New Product Inline Form
                  if (_showNewProductForm) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E7D32),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'باركود جديد: $_currentBarcode',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'صنف غير مسجل، يرجى إدخال البيانات السريعة:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('منتج جديد تماماً'),
                                selected: !_isLinkToExistingMode,
                                onSelected: (val) {
                                  if (val) setState(() => _isLinkToExistingMode = false);
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                key: const Key('link_to_existing_product_mode'),
                                label: const Text('ربط بموديل موجود كـ مقاس جديد'),
                                selected: _isLinkToExistingMode,
                                onSelected: (val) {
                                  if (val) {
                                    setState(() => _isLinkToExistingMode = true);
                                    _loadExistingProducts();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (!_isLinkToExistingMode) ...[
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _nameCtrl,
                                  focusNode: _nameFocus,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => _sellFocus.requestFocus(),
                                  decoration: InputDecoration(
                                    labelText: 'اسم الصنف *',
                                    hintText: 'مثال: شيبسي بالجبنة 50 جم',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Category
                              Expanded(
                                flex: 2,
                                child: BlocBuilder<CategoryCubit, CategoryState>(
                                  builder: (context, catState) {
                                    final cats = catState is CategoryLoaded
                                        ? catState.categories
                                        : <CategoryEntity>[];
                                    if (cats.isNotEmpty &&
                                        _selectedCategoryId == null) {
                                      _selectedCategoryId = cats.first.id;
                                    }
                                    return DropdownButtonFormField<String>(
                                      initialValue: cats.any(
                                              (c) => c.id == _selectedCategoryId)
                                          ? _selectedCategoryId
                                          : null,
                                      decoration: InputDecoration(
                                        labelText: 'القسم *',
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      items: cats
                                          .map(
                                            (c) => DropdownMenuItem(
                                              value: c.id,
                                              child: Text(c.name),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (val) {
                                        setState(() => _selectedCategoryId = val);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _sellCtrl,
                                  focusNode: _sellFocus,
                                  keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true),
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => _costFocus.requestFocus(),
                                  decoration: InputDecoration(
                                    labelText: 'سعر البيع (ج.م) *',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _costCtrl,
                                  focusNode: _costFocus,
                                  keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true),
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => _qtyFocus.requestFocus(),
                                  decoration: InputDecoration(
                                    labelText: 'سعر التكلفة (ج.م) *',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _qtyCtrl,
                                  focusNode: _qtyFocus,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _saveNewProduct(),
                                  decoration: InputDecoration(
                                    labelText: 'الكمية المستلمة *',
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2E7D32),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _isSaving ? null : _saveNewProduct,
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(Icons.check_rounded,
                                        color: Colors.white),
                                label: const Text(
                                  'حفظ وإضافة',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<Product>(
                                    key: const Key('select_existing_product_dropdown'),
                                    initialValue: _existingProducts.any((p) => p.id == _selectedProduct?.id)
                                        ? _selectedProduct
                                        : (_existingProducts.isNotEmpty ? _existingProducts.first : null),
                                    decoration: InputDecoration(
                                      labelText: 'الموديل / المنتج المسجل *',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    items: _existingProducts
                                        .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                                        .toList(),
                                    onChanged: (val) {
                                      setState(() => _selectedProduct = val);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    key: const Key('intake_variant_size_field'),
                                    controller: _linkSizeCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'المقاس / البعد *',
                                      hintText: '2×3 م، 42، XL',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    key: const Key('intake_variant_color_field'),
                                    controller: _linkColorCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'اللون',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const Key('intake_variant_sell_field'),
                                    controller: _linkSellCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'سعر البيع (ج.م) *',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    key: const Key('intake_variant_cost_field'),
                                    controller: _linkCostCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'سعر التكلفة (ج.م) *',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    key: const Key('intake_variant_qty_field'),
                                    controller: _linkQtyCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'الكمية المستلمة *',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton.icon(
                                  key: const Key('confirm_link_variant_btn'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2E7D32),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: _isSaving ? null : _saveLinkedVariant,
                                  icon: _isSaving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.check_rounded, color: Colors.white),
                                  label: const Text(
                                    'حفظ وربط الباركود',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const Divider(height: 1),

            // Session History Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, size: 20, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'أصناف تم مسحها وتحديثها في هذه الجلسة (${_sessionItems.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),

            // Session Items List
            Expanded(
              child: _sessionItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.barcode_reader,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'امسح أول منتج للبدء...',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      itemCount: _sessionItems.length,
                      separatorBuilder: (ctx, idx) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final item = _sessionItems[idx];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: item.isExisting
                                ? Colors.teal.shade50
                                : Colors.green.shade50,
                            child: Icon(
                              item.isExisting
                                  ? Icons.add_rounded
                                  : Icons.new_label_rounded,
                              color: item.isExisting
                                  ? Colors.teal.shade800
                                  : Colors.green.shade800,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'كود: ${item.barcode} | السعر: ${Money(item.sellPrice).toDisplay()} ج.م',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '+${item.addedQty} قطعة',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'إجمالي الأصناف الممسوحة: ${_sessionItems.fold<int>(0, (s, i) => s + i.addedQty)} قطعة',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('إغلاق والعودة للمنتجات',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
