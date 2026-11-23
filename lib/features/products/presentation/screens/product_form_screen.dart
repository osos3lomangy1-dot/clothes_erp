import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../../../../core/utils/barcode_helper.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/presentation/screens/category_form_screen.dart';
import '../../data/datasources/product_local_data_source.dart';
import '../../domain/entities/product_entity.dart';
import '../cubits/product_form_cubit.dart';
import '../cubits/product_form_state.dart';
import '../../../settings/data/services/activity_settings_service.dart';
import '../widgets/culinary_profile_card.dart';

class ProductFormScreen extends StatelessWidget {
  final ProductEntity? product;

  const ProductFormScreen({super.key, this.product});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          product != null ? 'تعديل المنتج' : 'إضافة منتج ومقاسات جديدة',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ProductFormView(product: product, isDialog: false),
    );
  }
}

class ProductFormDialog extends StatelessWidget {
  final ProductEntity? product;

  const ProductFormDialog({super.key, this.product});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 780),
        child: ProductFormView(product: product, isDialog: true),
      ),
    );
  }
}

class ProductFormView extends StatelessWidget {
  final ProductEntity? product;
  final bool isDialog;

  const ProductFormView({super.key, this.product, this.isDialog = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<ProductFormCubit>()..init(product),
      child: _ProductFormInternal(product: product, isDialog: isDialog),
    );
  }
}

class _ProductFormInternal extends StatefulWidget {
  final ProductEntity? product;
  final bool isDialog;

  const _ProductFormInternal({this.product, this.isDialog = false});

  @override
  State<_ProductFormInternal> createState() => _ProductFormInternalState();
}

class _VariantRowModel {
  final TextEditingController sizeCtrl;
  final TextEditingController colorCtrl;
  final TextEditingController skuCtrl;
  final TextEditingController costCtrl;
  final TextEditingController sellCtrl;
  final TextEditingController qtyCtrl;

  final FocusNode sizeFocus = FocusNode();
  final FocusNode colorFocus = FocusNode();
  final FocusNode skuFocus = FocusNode();
  final FocusNode costFocus = FocusNode();
  final FocusNode sellFocus = FocusNode();
  final FocusNode qtyFocus = FocusNode();

  _VariantRowModel({
    required String size,
    required String color,
    required String sku,
    required String cost,
    required String sell,
    required String qty,
  })  : sizeCtrl = TextEditingController(text: size),
        colorCtrl = TextEditingController(text: color),
        skuCtrl = TextEditingController(text: sku),
        costCtrl = TextEditingController(text: cost),
        sellCtrl = TextEditingController(text: sell),
        qtyCtrl = TextEditingController(text: qty);

  void dispose() {
    sizeCtrl.dispose();
    colorCtrl.dispose();
    skuCtrl.dispose();
    costCtrl.dispose();
    sellCtrl.dispose();
    qtyCtrl.dispose();

    sizeFocus.dispose();
    colorFocus.dispose();
    skuFocus.dispose();
    costFocus.dispose();
    sellFocus.dispose();
    qtyFocus.dispose();
  }
}

class _ProductFormInternalState extends State<_ProductFormInternal> {
  final List<_VariantRowModel> _rows = [];
  final TextEditingController _batchCostCtrl = TextEditingController(text: '100');
  final TextEditingController _batchSellCtrl = TextEditingController(text: '150');
  final TextEditingController _batchQtyCtrl = TextEditingController(text: '10');

  // Single-item controllers for adaptive forms (accessories, home appliances, general)
  late final TextEditingController _singleSkuCtrl;
  final TextEditingController _singleCostCtrl = TextEditingController(text: '100');
  final TextEditingController _singleSellCtrl = TextEditingController(text: '150');
  final TextEditingController _singleQtyCtrl = TextEditingController(text: '10');

  // Adaptive product attributes
  late TextEditingController _warrantyCtrl;
  late TextEditingController _brandOrModelCtrl;
  late TextEditingController _imeiCtrl;
  late TextEditingController _expiryCtrl;
  String _measurementUnit = 'piece'; // 'piece', 'weight'
  late bool _isInstallmentEligible;
  String _sellMode = 'piece'; // 'piece', 'meter'
  late TextEditingController _rollWidthCtrl;

  late TextEditingController _ingredientsCtrl;
  late TextEditingController _caloriesCtrl;
  late TextEditingController _prepTimeCtrl;
  String? _kitchenStation;
  final Set<String> _selectedAllergens = {};
  String? _foodImagePath;

  String? _validationError;

  @override
  void initState() {
    super.initState();
    if (getIt.isRegistered<ActivitySettingsService>()) {
      final cached = getIt<ActivitySettingsService>().cachedEnabledActivities;
      if (cached.contains(ActivityType.restaurantsCafes)) {
        _singleQtyCtrl.text = '999';
      }
    }
    _singleSkuCtrl = TextEditingController(text: _generateSingleBarcode());
    _warrantyCtrl = TextEditingController(text: widget.product?.warrantyPeriod ?? '');
    _brandOrModelCtrl = TextEditingController(text: widget.product?.brandOrModel ?? '');
    _imeiCtrl = TextEditingController();
    _expiryCtrl = TextEditingController();
    _isInstallmentEligible = widget.product?.isInstallmentEligible ?? true;
    _sellMode = widget.product?.sellMode ?? 'piece';
    _rollWidthCtrl = TextEditingController(text: widget.product?.rollWidth ?? '1.0 م');

    final cul = widget.product?.culinaryData;
    _ingredientsCtrl = TextEditingController(text: cul?.ingredients ?? '');
    _caloriesCtrl = TextEditingController(
        text: cul?.calories != null ? '${cul!.calories}' : '');
    _prepTimeCtrl = TextEditingController(
        text: cul?.prepTimeMinutes != null ? '${cul!.prepTimeMinutes}' : '');
    _kitchenStation = cul?.kitchenStation;
    _foodImagePath = widget.product?.foodImagePath;
    if (cul != null && cul.allergens.isNotEmpty) {
      _selectedAllergens.addAll(cul.allergens);
    }

    if (widget.product == null) {
      _initDefaultRows();
    }
  }

  String _generateSingleBarcode() {
    if (getIt.isRegistered<ActivitySettingsService>()) {
      final cached = getIt<ActivitySettingsService>().cachedEnabledActivities;
      if (cached.contains(ActivityType.restaurantsCafes)) {
        return 'REST-${DateTime.now().millisecondsSinceEpoch % 1000000}';
      }
    }
    final millis = DateTime.now().millisecondsSinceEpoch.toString();
    return 'SKU-${millis.substring(millis.length - 6)}';
  }

  void _initDefaultRows() {
    _rows.add(_VariantRowModel(size: 'M', color: 'أسود', sku: _makeSku('M', 1), cost: '100', sell: '150', qty: '10'));
    _rows.add(_VariantRowModel(size: 'L', color: 'أسود', sku: _makeSku('L', 2), cost: '100', sell: '150', qty: '10'));
    _rows.add(_VariantRowModel(size: 'XL', color: 'أسود', sku: _makeSku('XL', 3), cost: '100', sell: '150', qty: '10'));
  }

  String _makeSku(String size, int index) {
    return BarcodeHelper.generateSku(size: size, index: index);
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _batchCostCtrl.dispose();
    _batchSellCtrl.dispose();
    _batchQtyCtrl.dispose();
    _singleSkuCtrl.dispose();
    _singleCostCtrl.dispose();
    _singleSellCtrl.dispose();
    _singleQtyCtrl.dispose();
    _ingredientsCtrl.dispose();
    _caloriesCtrl.dispose();
    _prepTimeCtrl.dispose();
    _warrantyCtrl.dispose();
    _brandOrModelCtrl.dispose();
    _imeiCtrl.dispose();
    _expiryCtrl.dispose();
    _rollWidthCtrl.dispose();
    super.dispose();
  }

  FocusNode _getVariantFocusNode(int rowIdx, int colIdx, bool isCashier) {
    if (rowIdx < 0 || rowIdx >= _rows.length) return _rows[0].sizeFocus;
    final r = _rows[rowIdx];
    switch (colIdx) {
      case 0:
        return r.sizeFocus;
      case 1:
        return r.colorFocus;
      case 2:
        return r.skuFocus;
      case 3:
        return isCashier ? r.sellFocus : r.costFocus;
      case 4:
        return isCashier ? r.qtyFocus : r.sellFocus;
      case 5:
        return r.qtyFocus;
      default:
        return r.sizeFocus;
    }
  }

  int _maxGridCols(bool isCashier) => isCashier ? 4 : 5;

  KeyEventResult _handleGridKeyNavigation(
    KeyEvent event,
    int rowIdx,
    int colIdx,
    ActivityType? activityType,
    bool isCashier,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (rowIdx < _rows.length - 1) {
        _getVariantFocusNode(rowIdx + 1, colIdx, isCashier).requestFocus();
      } else {
        _addRow(activityType);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _rows.length > rowIdx + 1) {
            _getVariantFocusNode(rowIdx + 1, colIdx, isCashier).requestFocus();
          }
        });
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (rowIdx > 0) {
        _getVariantFocusNode(rowIdx - 1, colIdx, isCashier).requestFocus();
      }
      return KeyEventResult.handled;
    }

    final maxCol = _maxGridCols(isCashier);

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (colIdx < maxCol) {
        _getVariantFocusNode(rowIdx, colIdx + 1, isCashier).requestFocus();
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (colIdx > 0) {
        _getVariantFocusNode(rowIdx, colIdx - 1, isCashier).requestFocus();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _addRow([ActivityType? activityType]) {
    setState(() {
      final last = _rows.isNotEmpty ? _rows.last : null;
      final nextIdx = _rows.length + 1;

      String nextSize = 'L';
      if (activityType != null) {
        final existingSizes = _rows.map((r) => r.sizeCtrl.text.trim()).toSet();
        final unadded = activityType.standardSizes.where((s) => !existingSizes.contains(s)).toList();
        if (unadded.isNotEmpty) {
          nextSize = unadded.first;
        } else if (activityType.standardSizes.isNotEmpty) {
          nextSize = activityType.standardSizes.last;
        }
      }

      final newRow = _VariantRowModel(
        size: nextSize,
        color: last?.colorCtrl.text ?? 'أسود',
        sku: _makeSku(nextSize, nextIdx),
        cost: last?.costCtrl.text ?? '100',
        sell: last?.sellCtrl.text ?? '150',
        qty: last?.qtyCtrl.text ?? '10',
      );
      _rows.add(newRow);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          newRow.sizeFocus.requestFocus();
        }
      });
    });
  }

  void _loadStandardSizes(ActivityType activityType) {
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows.clear();

      final sizes = activityType.standardSizes;

      final cost = _batchCostCtrl.text.isNotEmpty ? _batchCostCtrl.text : '100';
      final sell = _batchSellCtrl.text.isNotEmpty ? _batchSellCtrl.text : '150';
      final qty = _batchQtyCtrl.text.isNotEmpty ? _batchQtyCtrl.text : '10';

      for (int i = 0; i < sizes.length; i++) {
        _rows.add(_VariantRowModel(
          size: sizes[i],
          color: 'افتراضي',
          sku: _makeSku(sizes[i], i + 1),
          cost: cost,
          sell: sell,
          qty: qty,
        ));
      }
    });
  }

  void _openCustomDimensionDialog() {
    final widthCtrl = TextEditingController(text: '2');
    final lengthCtrl = TextEditingController(text: '3');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('توليد مقاس مخصص هندسي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('custom_dim_width_field'),
              controller: widthCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'العرض بالمتر',
                suffixText: 'م',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('custom_dim_length_field'),
              controller: lengthCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'الطول بالمتر',
                suffixText: 'م',
                border: OutlineInputBorder(),
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
            key: const Key('confirm_custom_dimension_btn'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              final w = widthCtrl.text.trim();
              final l = lengthCtrl.text.trim();
              if (w.isNotEmpty && l.isNotEmpty) {
                final dim = '$w×$l م';
                final cost = _batchCostCtrl.text.isNotEmpty ? _batchCostCtrl.text : '100';
                final sell = _batchSellCtrl.text.isNotEmpty ? _batchSellCtrl.text : '150';
                final qty = _batchQtyCtrl.text.isNotEmpty ? _batchQtyCtrl.text : '10';
                setState(() {
                  _rows.add(_VariantRowModel(
                    size: dim,
                    color: 'افتراضي',
                    sku: _makeSku(dim, _rows.length + 1),
                    cost: cost,
                    sell: sell,
                    qty: qty,
                  ));
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('إضافة المقاس', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _applyBatchValues() {
    setState(() {
      final cost = _batchCostCtrl.text.trim();
      final sell = _batchSellCtrl.text.trim();
      final qty = _batchQtyCtrl.text.trim();
      for (final r in _rows) {
        if (cost.isNotEmpty) r.costCtrl.text = cost;
        if (sell.isNotEmpty) r.sellCtrl.text = sell;
        if (qty.isNotEmpty) r.qtyCtrl.text = qty;
      }
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  String? _skuErrorForRow(int idx, ProductFormState state) {
    final sku = _rows[idx].skuCtrl.text.trim();
    if (sku.isEmpty) return null;
    final lower = sku.toLowerCase();
    if (state.existingSkus.contains(lower)) {
      return 'الكود مسجل مسبقاً';
    }
    for (int j = 0; j < _rows.length; j++) {
      if (j == idx) continue;
      if (_rows[j].skuCtrl.text.trim().toLowerCase() == lower) {
        return 'الكود مكرر بالجدول';
      }
    }
    return null;
  }

  Future<void> _openAddCategoryQuick(BuildContext context) async {
    final newCat = await showDialog<CategoryEntity?>(
      context: context,
      builder: (_) => const CategoryFormDialog(),
    );
    if (newCat != null && mounted) {
      if (!context.mounted) return;
      context.read<ProductFormCubit>().reloadCategories(selectCategoryId: newCat.id);
    }
  }

  Future<void> _handleSubmit(BuildContext context, ProductFormState state) async {
    setState(() => _validationError = null);

    if (state.name.trim().isEmpty) {
      setState(() => _validationError = 'يرجى إدخال اسم المنتج');
      return;
    }
    if (state.categoryId == null || state.categoryId!.isEmpty) {
      setState(() => _validationError = 'يرجى اختيار تصنيف للمنتج');
      return;
    }

    if (state.hasDuplicate) {
      setState(() => _validationError =
          'عفواً، يوجد منتج مسجل بالفعل بهذا الاسم ("${state.exactDuplicateProduct!.name}"). لا يمكن تكرار إضافة المنتج.');
      return;
    }

    if (state.hasSimilar) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
              SizedBox(width: 8),
              Text('تنبيه: تشابه مع منتجات مسجلة'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'تم رصد منتجات بأسم مشابهة مسجلة بالفعل في النظام:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...state.similarProducts.take(4).map((p) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text('• ${p.name} (${p.categoryName})'),
                  )),
              const SizedBox(height: 12),
              const Text(
                'لتفادي تكرار المنتجات بالخطأ، هل أنت متأكد من رغبتك في حفظ هذا المنتج باسمه الحالي؟',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء ومراجعة الاسم'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد الحفظ'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!context.mounted) return;
    }

    final cubit = context.read<ProductFormCubit>();
    cubit.onWarrantyPeriodChanged(_warrantyCtrl.text.trim().isEmpty ? null : _warrantyCtrl.text.trim());
    cubit.onBrandOrModelChanged(_brandOrModelCtrl.text.trim().isEmpty ? null : _brandOrModelCtrl.text.trim());
    cubit.onInstallmentEligibleChanged(_isInstallmentEligible);

    if (state.activityTypeEnum == ActivityType.restaurantsCafes) {
      final cul = RestaurantCulinaryData(
        ingredients: _ingredientsCtrl.text.trim().isEmpty ? null : _ingredientsCtrl.text.trim(),
        calories: int.tryParse(_caloriesCtrl.text.trim()),
        allergens: _selectedAllergens.toList(),
        prepTimeMinutes: int.tryParse(_prepTimeCtrl.text.trim()),
        kitchenStation: _kitchenStation,
        userDescription: state.description.isEmpty ? null : state.description,
        imagePath: _foodImagePath,
      );
      cubit.onDescriptionChanged(cul.toEncodedString());
    }

    if (state.isEdit) {
      cubit.submit(widget.product?.id);
      return;
    }

    final isSingleItem = state.activityTypeEnum.isSingleItem;
    final List<VariantInput> variants = [];

    if (isSingleItem) {
      var sku = _singleSkuCtrl.text.trim();
      final costPounds = double.tryParse(_singleCostCtrl.text.trim()) ?? 0.0;
      final sellPounds = double.tryParse(_singleSellCtrl.text.trim()) ?? 0.0;
      final defaultQty = state.activityTypeEnum == ActivityType.restaurantsCafes ? 999 : 0;
      final qty = int.tryParse(_singleQtyCtrl.text.trim()) ?? defaultQty;

      if (sku.isEmpty) {
        if (state.activityTypeEnum == ActivityType.restaurantsCafes) {
          sku = 'REST-${DateTime.now().millisecondsSinceEpoch % 1000000}';
        } else {
          setState(() => _validationError = 'كود الصنف (الباركود) مطلوب');
          return;
        }
      }

      if (state.existingSkus.contains(sku.toLowerCase())) {
        setState(() => _validationError = 'الكود ("$sku") مسجل بالفعل لصنف آخر في النظام.');
        return;
      }

      variants.add(VariantInput(
        sku: sku,
        color: '-',
        size: '-',
        costPrice: (costPounds * 100).toInt(),
        sellPrice: (sellPounds * 100).toInt(),
        quantity: qty,
      ));
    } else {
      if (_rows.isEmpty) {
        setState(() => _validationError = 'يرجى إضافة سطر واحد على الأقل في جدول المقاسات');
        return;
      }

      final Set<String> seenSkus = {};
      for (int i = 0; i < _rows.length; i++) {
        final r = _rows[i];
        final size = r.sizeCtrl.text.trim();
        final color = r.colorCtrl.text.trim();
        final sku = r.skuCtrl.text.trim();
        final costPounds = double.tryParse(r.costCtrl.text.trim()) ?? 0.0;
        final sellPounds = double.tryParse(r.sellCtrl.text.trim()) ?? 0.0;
        final qty = int.tryParse(r.qtyCtrl.text.trim()) ?? 0;

        if (size.isEmpty || color.isEmpty || sku.isEmpty) {
          setState(() => _validationError = 'السطر رقم ${i + 1}: المقاس واللون والكود حقول مطلوبة');
          return;
        }

        final skuLower = sku.toLowerCase();
        if (state.existingSkus.contains(skuLower)) {
          setState(() => _validationError =
              'السطر رقم ${i + 1}: عفواً، الكود ("$sku") مسجل بالفعل في النظام لصنف آخر. لا يمكن تكرار الأكواد.');
          return;
        }
        if (!seenSkus.add(skuLower)) {
          setState(() => _validationError =
              'السطر رقم ${i + 1}: عفواً، الكود ("$sku") مكرر أكثر من مرة داخل جدول المقاسات.');
          return;
        }

        variants.add(VariantInput(
          sku: sku,
          color: color,
          size: size,
          costPrice: (costPounds * 100).toInt(),
          sellPrice: (sellPounds * 100).toInt(),
          quantity: qty,
        ));
      }
    }

    cubit.submitWithVariants(
      id: widget.product?.id,
      variants: variants,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProductFormCubit, ProductFormState>(
      listener: (context, state) {
        if (state.status == ProductFormStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade800,
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    state.isEdit ? 'تم تحديث بيانات المنتج بنجاح' : 'تم إضافة المنتج وجميع المقاسات والكميات بنجاح',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
          AppNavigator.pop(context);
        } else if (state.status == ProductFormStatus.error && state.errorMessage != null) {
          setState(() => _validationError = state.errorMessage);
        }
      },
      builder: (context, state) {
        if (state.status == ProductFormStatus.loading && state.categories.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f3): () => _addRow(state.activityTypeEnum),
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => _handleSubmit(context, state),
          },
          child: Focus(
            autofocus: true,
            child: Padding(
              padding: EdgeInsets.all(widget.isDialog ? 20.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // Dialog Header if dialog
              if (widget.isDialog) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.add_business_rounded, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.isEdit ? 'تعديل المنتج' : 'إضافة منتج وجدول المقاسات',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                          ),
                          Text(
                            'تسجيل المنتج الجديد والمقاسات والأسعار والأرصدة الأولية دفعة واحدة',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: state.status == ProductFormStatus.loading ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
              ],

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Audit Metadata Information Card at top of form in edit mode
                      if (state.isEdit)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.verified_outlined,
                                  size: 20,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Wrap(
                                  spacing: 20,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (widget.product?.id != null)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'معرّف الصنف: ',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                          Text(
                                            widget.product!.id.length > 8
                                                ? widget.product!.id.substring(0, 8)
                                                : widget.product!.id,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (state.createdAt != null)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.calendar_today_outlined,
                                            size: 13,
                                            color: Color(0xFF64748B),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'أُضيف: ${state.createdAt!.year}/${state.createdAt!.month.toString().padLeft(2, '0')}/${state.createdAt!.day.toString().padLeft(2, '0')} (${state.createdAt!.hour.toString().padLeft(2, '0')}:${state.createdAt!.minute.toString().padLeft(2, '0')})',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF334155),
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (state.updatedAt != null)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.update_rounded,
                                            size: 14,
                                            color: Color(0xFF64748B),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'آخر تعديل: ${state.updatedAt!.year}/${state.updatedAt!.month.toString().padLeft(2, '0')}/${state.updatedAt!.day.toString().padLeft(2, '0')} (${state.updatedAt!.hour.toString().padLeft(2, '0')}:${state.updatedAt!.minute.toString().padLeft(2, '0')})',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Section 1: Basic Product Information Card
                      Card(
                        elevation: 0.5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'البيانات الأساسية للمنتج',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  if (state.isEdit && state.createdAt != null) ...[
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.history_rounded, size: 13, color: Color(0xFF475569)),
                                          const SizedBox(width: 4),
                                          Text(
                                            'أُضيف: ${state.createdAt!.year}/${state.createdAt!.month.toString().padLeft(2, '0')}/${state.createdAt!.day.toString().padLeft(2, '0')}',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                          ),
                                          if (state.updatedAt != null &&
                                              state.updatedAt!.difference(state.createdAt!).inMinutes.abs() > 1) ...[
                                            const SizedBox(width: 8),
                                            const Icon(Icons.update_rounded, size: 13, color: Color(0xFF475569)),
                                            const SizedBox(width: 3),
                                            Text(
                                              'آخر تعديل: ${state.updatedAt!.year}/${state.updatedAt!.month.toString().padLeft(2, '0')}/${state.updatedAt!.day.toString().padLeft(2, '0')}',
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Activity Type Selector
                              const Text(
                                'نوع النشاط / نمط المنتج:',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 8),
                              StreamBuilder<List<ActivityType>>(
                                stream: getIt.isRegistered<ActivitySettingsService>()
                                    ? getIt<ActivitySettingsService>().watchEnabledActivities()
                                    : Stream.value(ActivityType.values),
                                builder: (context, snapshot) {
                                  final enabledActs = snapshot.data ?? ActivityType.values;
                                  final list = {...enabledActs, state.activityTypeEnum}.toList();

                                  return SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: list.map((act) {
                                        final isSelected = state.activityTypeEnum == act;
                                        return Padding(
                                          padding: const EdgeInsets.only(left: 8.0),
                                          child: InkWell(
                                            onTap: () {
                                              context.read<ProductFormCubit>().onActivityTypeChanged(act.code);
                                              if (act == ActivityType.restaurantsCafes) {
                                                if (_singleQtyCtrl.text == '0' || _singleQtyCtrl.text.isEmpty) {
                                                  _singleQtyCtrl.text = '999';
                                                }
                                                if (_singleSkuCtrl.text.isEmpty || _singleSkuCtrl.text.startsWith('SKU-')) {
                                                  _singleSkuCtrl.text = 'REST-${DateTime.now().millisecondsSinceEpoch % 1000000}';
                                                }
                                              }
                                            },
                                            borderRadius: BorderRadius.circular(10),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                                                  width: isSelected ? 1.5 : 1.0,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    act.icon,
                                                    size: 18,
                                                    color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    act.labelArabic,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                      color: isSelected ? AppColors.primary : AppColors.onSurface,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 14),

                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      initialValue: state.name,
                                      decoration: InputDecoration(
                                        labelText: 'اسم المنتج *',
                                        hintText: state.activityTypeEnum == ActivityType.restaurantsCafes
                                            ? 'مثال: برجر دبل تشيز / بيتزا مارجريتا / كابتشينو'
                                            : 'مثال: بنطلون جينز سليم فيت',
                                        prefixIcon: Icon(
                                          state.activityTypeEnum == ActivityType.restaurantsCafes
                                              ? Icons.restaurant_menu_rounded
                                              : Icons.checkroom,
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onChanged: (value) => context.read<ProductFormCubit>().onNameChanged(value),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            key: const Key('product_category_dropdown'),
                                            isExpanded: true,
                                            initialValue: state.categories.any((c) => c.id == state.categoryId)
                                                ? state.categoryId
                                                : (state.categories.isNotEmpty && state.activityTypeEnum == ActivityType.restaurantsCafes ? state.categories.first.id : null),
                                            decoration: InputDecoration(
                                              labelText: 'التصنيف *',
                                              prefixIcon: const Icon(Icons.category),
                                              filled: true,
                                              fillColor: Colors.grey.shade50,
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            items: state.categories.map((category) {
                                              return DropdownMenuItem(
                                                value: category.id,
                                                child: Text(category.name),
                                              );
                                            }).toList(),
                                            onChanged: (value) {
                                              if (value != null) {
                                                final category = state.categories.firstWhere((c) => c.id == value);
                                                context.read<ProductFormCubit>().onCategoryChanged(category.id, category.name);
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          key: const Key('add_category_quick_btn'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          icon: const Icon(Icons.add_rounded, size: 18),
                                          label: const Text('قسم جديد', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                                          onPressed: () => _openAddCategoryQuick(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (state.hasDuplicate) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.red.shade300),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.error_outline, color: Colors.red.shade800, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'تنبيه: يوجد منتج مسجل بالفعل بهذا الاسم ("${state.exactDuplicateProduct!.name}") ضمن تصنيف "${state.exactDuplicateProduct!.categoryName}". لا يمكن تكرار إضافة المنتج.',
                                          style: TextStyle(
                                            color: Colors.red.shade900,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (state.hasSimilar) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.shade400),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 18),
                                          const SizedBox(width: 6),
                                          Text(
                                            'منتجات مشابهة مسجلة مسبقاً (يرجى التأكد من عدم التكرار):',
                                            style: TextStyle(
                                              color: Colors.amber.shade900,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: state.similarProducts.take(5).map((p) {
                                          return Chip(
                                            visualDensity: VisualDensity.compact,
                                            backgroundColor: Colors.white,
                                            side: BorderSide(color: Colors.amber.shade300),
                                            avatar: Icon(Icons.checkroom, size: 14, color: AppColors.primary),
                                            label: Text(
                                              '${p.name} (${p.categoryName})',
                                              style: const TextStyle(fontSize: 11),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      initialValue: state.description,
                                      decoration: InputDecoration(
                                        labelText: 'وصف أو ملاحظات (اختياري)',
                                        hintText: 'مثال: خامة قطن 100% تصنيع محلي',
                                        prefixIcon: const Icon(Icons.description_outlined),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onChanged: (value) => context.read<ProductFormCubit>().onDescriptionChanged(value),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: TextFormField(
                                      initialValue: '${state.minStock}',
                                      decoration: InputDecoration(
                                        labelText: 'حد الأمان (التنبيه)',
                                        hintText: '5',
                                        prefixIcon: const Icon(Icons.notifications_active_outlined),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (value) => context.read<ProductFormCubit>().onMinStockChanged(int.tryParse(value) ?? 5),
                                    ),
                                  ),
                                ],
                              ),

                              if (state.activityTypeEnum == ActivityType.restaurantsCafes) ...[
                                const SizedBox(height: 16),
                                CulinaryProfileCard(
                                  ingredientsController: _ingredientsCtrl,
                                  caloriesController: _caloriesCtrl,
                                  prepTimeController: _prepTimeCtrl,
                                  selectedAllergens: _selectedAllergens,
                                  selectedKitchenStation: _kitchenStation,
                                  imagePath: _foodImagePath,
                                  onImagePathChanged: (val) =>
                                      setState(() => _foodImagePath = val),
                                  onKitchenStationChanged: (val) =>
                                      setState(() => _kitchenStation = val),
                                  onAllergenToggled: (allergen, selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedAllergens.add(allergen);
                                      } else {
                                        _selectedAllergens.remove(allergen);
                                      }
                                    });
                                  },
                                ),
                              ],

                              if (state.activityTypeEnum.supportsBrandOrModel ||
                                  state.activityTypeEnum.supportsWarranty ||
                                  state.activityTypeEnum.supportsIMEI ||
                                  state.activityTypeEnum.supportsWeight ||
                                  state.activityTypeEnum.supportsExpiry ||
                                  state.activityTypeEnum.supportsInstallment ||
                                  state.activityTypeEnum.supportsCutToLength ||
                                  state.activityTypeEnum == ActivityType.textilesDecor) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainer.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.outlineVariant),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(state.activityTypeEnum.icon, size: 18, color: AppColors.primary),
                                          const SizedBox(width: 6),
                                          Text(
                                            'خصائص ${state.activityTypeEnum.labelArabic}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      if (state.activityTypeEnum.supportsBrandOrModel || state.activityTypeEnum.supportsWarranty)
                                        Row(
                                          children: [
                                            if (state.activityTypeEnum.supportsBrandOrModel)
                                              Expanded(
                                                child: TextFormField(
                                                  controller: _brandOrModelCtrl,
                                                  decoration: InputDecoration(
                                                    labelText: 'الماركة أو الموديل (اختياري)',
                                                    hintText: 'مثال: توشيبا، تيفال، سوني',
                                                    prefixIcon: const Icon(Icons.branding_watermark_outlined),
                                                    filled: true,
                                                    fillColor: Colors.white,
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                ),
                                              ),
                                            if (state.activityTypeEnum.supportsBrandOrModel && state.activityTypeEnum.supportsWarranty)
                                              const SizedBox(width: 12),
                                            if (state.activityTypeEnum.supportsWarranty)
                                              Expanded(
                                                child: TextFormField(
                                                  controller: _warrantyCtrl,
                                                  decoration: InputDecoration(
                                                    labelText: 'فترة الضمان بالشهور (اختياري)',
                                                    hintText: 'مثال: 12 شهر، 24 شهر',
                                                    prefixIcon: const Icon(Icons.verified_user_outlined),
                                                    filled: true,
                                                    fillColor: Colors.white,
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      if (state.activityTypeEnum.supportsIMEI || state.activityTypeEnum.supportsExpiry) ...[
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            if (state.activityTypeEnum.supportsIMEI)
                                              Expanded(
                                                child: TextFormField(
                                                  controller: _imeiCtrl,
                                                  decoration: InputDecoration(
                                                    labelText: 'السيريال / كود IMEI (اختياري)',
                                                    hintText: 'مثال: 356938035643809',
                                                    prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                                                    filled: true,
                                                    fillColor: Colors.white,
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                ),
                                              ),
                                            if (state.activityTypeEnum.supportsIMEI && state.activityTypeEnum.supportsExpiry)
                                              const SizedBox(width: 12),
                                            if (state.activityTypeEnum.supportsExpiry)
                                              Expanded(
                                                child: TextFormField(
                                                  controller: _expiryCtrl,
                                                  decoration: InputDecoration(
                                                    labelText: 'تاريخ الصلاحية / التشغيلة (اختياري)',
                                                    hintText: 'مثال: 2026/12/31',
                                                    prefixIcon: const Icon(Icons.event_busy_rounded),
                                                    filled: true,
                                                    fillColor: Colors.white,
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                      if (state.activityTypeEnum.supportsWeight) ...[
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            const Icon(Icons.scale_rounded, size: 18, color: Color(0xFF64748B)),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'نوع القياس والبيع:',
                                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(width: 12),
                                            ChoiceChip(
                                              label: const Text('بالقطعة'),
                                              selected: _measurementUnit == 'piece',
                                              onSelected: (val) => setState(() => _measurementUnit = 'piece'),
                                              selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                            ),
                                            const SizedBox(width: 8),
                                            ChoiceChip(
                                              label: const Text('بالوزن (كيلو / جرام / ميزان)'),
                                              selected: _measurementUnit == 'weight',
                                              onSelected: (val) => setState(() => _measurementUnit = 'weight'),
                                              selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (state.activityTypeEnum.supportsInstallment) ...[
                                        const SizedBox(height: 8),
                                        SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text('متاح للبيع بالتقسيط', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                          subtitle: const Text('يمكن إدراج هذا الصنف في خطط وعقود التقسيط', style: TextStyle(fontSize: 11)),
                                          value: _isInstallmentEligible,
                                          activeThumbColor: AppColors.primary,
                                          onChanged: (val) => setState(() => _isInstallmentEligible = val),
                                        ),
                                      ],
                                      if (state.activityTypeEnum.supportsCutToLength || state.activityTypeEnum == ActivityType.textilesDecor) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: AppColors.outlineVariant),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'نمط بيع السجاد والموكيت والأقمشة:',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                              ),
                                              const SizedBox(height: 8),
                                              SegmentedButton<String>(
                                                key: const Key('carpet_sell_mode_selector'),
                                                segments: const [
                                                  ButtonSegment(
                                                    value: 'piece',
                                                    label: Text('قطعة جاهزة بمقاس ثابت'),
                                                    icon: Icon(Icons.crop_square_rounded, size: 16),
                                                  ),
                                                  ButtonSegment(
                                                    value: 'meter',
                                                    label: Text('توب / رول مقصوص بالمتر'),
                                                    icon: Icon(Icons.straighten_rounded, size: 16),
                                                  ),
                                                ],
                                                selected: {_sellMode},
                                                onSelectionChanged: (newVal) {
                                                  setState(() {
                                                    _sellMode = newVal.first;
                                                  });
                                                },
                                              ),
                                              if (_sellMode == 'meter') ...[
                                                const SizedBox(height: 10),
                                                TextFormField(
                                                  key: const Key('roll_width_field'),
                                                  controller: _rollWidthCtrl,
                                                  decoration: InputDecoration(
                                                    labelText: 'عرض الرول / التوب *',
                                                    hintText: 'مثال: 1.0 م أو 4.0 م',
                                                    prefixIcon: const Icon(Icons.format_size_rounded),
                                                    filled: true,
                                                    fillColor: Colors.white,
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Section 2: Adaptive Product Entry (Single-item card or Variants table)
                      if (!state.isEdit) ...[
                        if (state.activityTypeEnum.isSingleItem) ...[
                          Card(
                            elevation: 0.5,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 20),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'بيانات الصنف الفوري (سعر وتكلفة وباركود)',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceContainer,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text('صنف أحادي بدون مقاسات', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: TextFormField(
                                          controller: _singleSkuCtrl,
                                          decoration: InputDecoration(
                                            labelText: state.activityTypeEnum == ActivityType.restaurantsCafes
                                                ? 'الباركود / كود المنتج (SKU) (اختياري)'
                                                : 'الباركود / كود المنتج (SKU) *',
                                            prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                                            suffixIcon: IconButton(
                                              tooltip: 'توليد باركود تلقائي',
                                              icon: const Icon(Icons.autorenew_rounded),
                                              onPressed: () => setState(() {
                                                _singleSkuCtrl.text = state.activityTypeEnum == ActivityType.restaurantsCafes
                                                    ? 'REST-${DateTime.now().millisecondsSinceEpoch % 1000000}'
                                                    : _generateSingleBarcode();
                                              }),
                                            ),
                                            filled: true,
                                            fillColor: Colors.grey.shade50,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: _singleQtyCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: 'الكمية الأولية بالمخزن *',
                                            prefixIcon: const Icon(Icons.warehouse_outlined),
                                            filled: true,
                                            fillColor: Colors.grey.shade50,
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Builder(
                                    builder: (context) {
                                      final authState = context.watch<AuthCubit>().state;
                                      final isCashier = authState is AuthAuthenticated && authState.user.role.toLowerCase() == 'cashier';
                                      return Row(
                                        children: [
                                          if (!isCashier) ...[
                                            Expanded(
                                              child: TextFormField(
                                                controller: _singleCostCtrl,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                decoration: InputDecoration(
                                                  labelText: 'سعر التكلفة (ج.م) *',
                                                  prefixIcon: const Icon(Icons.monetization_on_outlined),
                                                  filled: true,
                                                  fillColor: Colors.grey.shade50,
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                          ],
                                          Expanded(
                                            child: TextFormField(
                                              controller: _singleSellCtrl,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              decoration: InputDecoration(
                                                labelText: 'سعر البيع قطاعي (ج.م) *',
                                                prefixIcon: const Icon(Icons.point_of_sale_rounded),
                                                filled: true,
                                                fillColor: Colors.grey.shade50,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          Card(
                            elevation: 0.5,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.table_chart_outlined, color: AppColors.primary, size: 20),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'جدول المقاسات والألوان والأسعار والكميات',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                            icon: const Icon(Icons.flash_on, size: 16),
                                            label: Text(
                                              state.activityTypeEnum == ActivityType.footwearBags
                                                  ? 'نمر قياسية (38-45)'
                                                  : state.activityTypeEnum == ActivityType.textilesDecor
                                                      ? 'مقاسات سجاد قياسية'
                                                      : state.activityTypeEnum == ActivityType.perfumesCosmetics
                                                          ? 'أحجام عطور قياسية'
                                                          : state.activityTypeEnum == ActivityType.electronicsMobiles
                                                              ? 'سعات قياسية'
                                                              : 'مقاسات قياسية (S-3XL)',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                            onPressed: () => _loadStandardSizes(state.activityTypeEnum),
                                          ),
                                          if (state.activityTypeEnum.supportsCutToLength || state.activityTypeEnum == ActivityType.textilesDecor) ...[
                                            const SizedBox(width: 8),
                                            OutlinedButton.icon(
                                              key: const Key('generate_custom_dimension_btn'),
                                              style: OutlinedButton.styleFrom(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                              ),
                                              icon: const Icon(Icons.straighten, size: 16),
                                              label: const Text('توليد مقاس مخصص', style: TextStyle(fontSize: 12)),
                                              onPressed: _openCustomDimensionDialog,
                                            ),
                                          ],
                                          const SizedBox(width: 8),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.surfaceContainer,
                                              foregroundColor: AppColors.primary,
                                              elevation: 0,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            ),
                                            icon: const Icon(Icons.add, size: 16),
                                            label: const Text('إضافة سطر جديد (F3)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                            onPressed: () => _addRow(state.activityTypeEnum),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                // Batch Pricing Helper Bar
                                Builder(
                                  builder: (context) {
                                    final authState = context.watch<AuthCubit>().state;
                                    final isCashier = authState is AuthAuthenticated && authState.user.role.toLowerCase() == 'cashier';

                                    return Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceContainer.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.tune, size: 18, color: AppColors.primary),
                                          const SizedBox(width: 8),
                                          const Text('تطبيق موحد:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          const SizedBox(width: 12),
                                          if (!isCashier) ...[
                                            SizedBox(
                                              width: 100,
                                              child: TextField(
                                                controller: _batchCostCtrl,
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(
                                                  isDense: true,
                                                  labelText: 'التكلفة (ج.م)',
                                                  border: OutlineInputBorder(),
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          SizedBox(
                                            width: 100,
                                            child: TextField(
                                              controller: _batchSellCtrl,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                labelText: 'البيع (ج.م)',
                                                border: OutlineInputBorder(),
                                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 80,
                                            child: TextField(
                                              controller: _batchQtyCtrl,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                labelText: 'الكمية',
                                                border: OutlineInputBorder(),
                                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          TextButton.icon(
                                            icon: const Icon(Icons.done_all, size: 16),
                                            label: const Text('تطبيق على كل المقاسات', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                            onPressed: _applyBatchValues,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                                const SizedBox(height: 14),

                                // Table Header
                                Builder(
                                  builder: (context) {
                                    final authState = context.watch<AuthCubit>().state;
                                    final isCashier = authState is AuthAuthenticated && authState.user.role.toLowerCase() == 'cashier';

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          const SizedBox(width: 28, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          const Expanded(flex: 2, child: Text('المقاس', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          const SizedBox(width: 8),
                                          const Expanded(flex: 2, child: Text('اللون', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          const SizedBox(width: 8),
                                          const Expanded(flex: 3, child: Text('كود الصنف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          if (!isCashier) ...[
                                            const SizedBox(width: 8),
                                            const Expanded(flex: 2, child: Text('التكلفة (ج.م)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          ],
                                          const SizedBox(width: 8),
                                          const Expanded(flex: 2, child: Text('سعر البيع (ج.م)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          const SizedBox(width: 8),
                                          const Expanded(flex: 2, child: Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          const SizedBox(width: 40),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 6),

                                // Table Rows
                                Builder(
                                  builder: (context) {
                                    final authState = context.watch<AuthCubit>().state;
                                    final isCashier = authState is AuthAuthenticated && authState.user.role.toLowerCase() == 'cashier';
                                    final sizeHint = switch (state.activityTypeEnum) {
                                      ActivityType.textilesDecor => '2×3 م',
                                      ActivityType.footwearBags => '42',
                                      ActivityType.perfumesCosmetics => '100 مل',
                                      ActivityType.electronicsMobiles => '128GB',
                                      _ => 'L',
                                    };

                                    return ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: _rows.length,
                                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                                      itemBuilder: (context, idx) {
                                        final r = _rows[idx];
                                        r.sizeFocus.onKeyEvent = (node, event) =>
                                            _handleGridKeyNavigation(event, idx, 0, state.activityTypeEnum, isCashier);
                                        r.colorFocus.onKeyEvent = (node, event) =>
                                            _handleGridKeyNavigation(event, idx, 1, state.activityTypeEnum, isCashier);
                                        r.skuFocus.onKeyEvent = (node, event) =>
                                            _handleGridKeyNavigation(event, idx, 2, state.activityTypeEnum, isCashier);
                                        if (!isCashier) {
                                          r.costFocus.onKeyEvent = (node, event) =>
                                              _handleGridKeyNavigation(event, idx, 3, state.activityTypeEnum, isCashier);
                                          r.sellFocus.onKeyEvent = (node, event) =>
                                              _handleGridKeyNavigation(event, idx, 4, state.activityTypeEnum, isCashier);
                                          r.qtyFocus.onKeyEvent = (node, event) =>
                                              _handleGridKeyNavigation(event, idx, 5, state.activityTypeEnum, isCashier);
                                        } else {
                                          r.sellFocus.onKeyEvent = (node, event) =>
                                              _handleGridKeyNavigation(event, idx, 3, state.activityTypeEnum, isCashier);
                                          r.qtyFocus.onKeyEvent = (node, event) =>
                                              _handleGridKeyNavigation(event, idx, 4, state.activityTypeEnum, isCashier);
                                        }
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.shade200),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 28,
                                                child: Text('', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: r.sizeCtrl,
                                                  focusNode: r.sizeFocus,
                                                  textInputAction: TextInputAction.next,
                                                  onFieldSubmitted: (_) => r.colorFocus.requestFocus(),
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    hintText: sizeHint,
                                                    border: const OutlineInputBorder(),
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: r.colorCtrl,
                                                  focusNode: r.colorFocus,
                                                  textInputAction: TextInputAction.next,
                                                  onFieldSubmitted: (_) {
                                                    if (isCashier) {
                                                      r.sellFocus.requestFocus();
                                                    } else {
                                                      r.costFocus.requestFocus();
                                                    }
                                                  },
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    hintText: 'أسود',
                                                    border: OutlineInputBorder(),
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 3,
                                                child: Builder(
                                                  builder: (_) {
                                                    final skuErr = _skuErrorForRow(idx, state);
                                                    return TextFormField(
                                                      controller: r.skuCtrl,
                                                      focusNode: r.skuFocus,
                                                      textInputAction: TextInputAction.next,
                                                      onFieldSubmitted: (_) {
                                                        if (isCashier) {
                                                          r.sellFocus.requestFocus();
                                                        } else {
                                                          r.costFocus.requestFocus();
                                                        }
                                                      },
                                                      onChanged: (_) => setState(() {}),
                                                      decoration: InputDecoration(
                                                        isDense: true,
                                                        hintText: 'كود الصنف',
                                                        errorText: skuErr,
                                                        errorStyle: const TextStyle(fontSize: 10, height: 1.1),
                                                        border: const OutlineInputBorder(),
                                                        focusedBorder: skuErr != null
                                                            ? const OutlineInputBorder(
                                                                borderSide: BorderSide(color: Colors.red, width: 1.5),
                                                              )
                                                            : null,
                                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                              if (!isCashier) ...[
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  flex: 2,
                                                  child: TextFormField(
                                                    controller: r.costCtrl,
                                                    focusNode: r.costFocus,
                                                    keyboardType: TextInputType.number,
                                                    textInputAction: TextInputAction.next,
                                                    onFieldSubmitted: (_) => r.sellFocus.requestFocus(),
                                                    decoration: const InputDecoration(
                                                      isDense: true,
                                                      hintText: 'التكلفة',
                                                      border: OutlineInputBorder(),
                                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: r.sellCtrl,
                                                  focusNode: r.sellFocus,
                                                  keyboardType: TextInputType.number,
                                                  textInputAction: TextInputAction.next,
                                                  onFieldSubmitted: (_) => r.qtyFocus.requestFocus(),
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    hintText: 'البيع',
                                                    border: OutlineInputBorder(),
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: r.qtyCtrl,
                                                  focusNode: r.qtyFocus,
                                                  keyboardType: TextInputType.number,
                                                  textInputAction: TextInputAction.next,
                                                  onFieldSubmitted: (_) => _addRow(state.activityTypeEnum),
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    hintText: 'الكمية',
                                                    border: OutlineInputBorder(),
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                                tooltip: 'حذف هذا السطر',
                                                onPressed: _rows.length > 1 ? () => _removeRow(idx) : null,
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],

                      if (_validationError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _validationError!,
                                  style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: state.status == ProductFormStatus.loading ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    key: const Key('product_form_save_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: state.status == ProductFormStatus.loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 20),
                    label: Text(
                      state.status == ProductFormStatus.loading
                          ? 'جاري الحفظ...'
                          : (state.isEdit
                              ? 'تحديث المنتج'
                              : (state.activityTypeEnum.isSingleItem
                                  ? 'حفظ الصنف'
                                  : 'حفظ المنتج وجدول المقاسات')),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: state.status == ProductFormStatus.loading ? null : () => _handleSubmit(context, state),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  },
    );
  }
}
