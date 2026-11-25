import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/presentation/screens/category_form_screen.dart';
import '../../../product_variants/data/datasources/variant_local_data_source.dart';
import '../../data/datasources/product_local_data_source.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../cubits/product_form_cubit.dart';
import '../cubits/product_form_state.dart';
import '../../../settings/data/services/activity_settings_service.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/services/food_cost_calculator.dart';
import 'culinary_profile_card.dart';
import '../screens/product_form_screen.dart';

class SimpleProductFormDialog extends StatelessWidget {
  final ProductEntity? product;
  final String? initialQuery;
  final ActivityType? initialActivityType;

  const SimpleProductFormDialog({
    super.key,
    this.product,
    this.initialQuery,
    this.initialActivityType,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
        child: BlocProvider(
          create: (context) => getIt<ProductFormCubit>()..init(product),
          child: _SimpleProductFormInternal(
            product: product,
            initialQuery: initialQuery,
            initialActivityType: initialActivityType,
          ),
        ),
      ),
    );
  }
}

class _SimpleProductFormInternal extends StatefulWidget {
  final ProductEntity? product;
  final String? initialQuery;
  final ActivityType? initialActivityType;

  const _SimpleProductFormInternal({
    this.product,
    this.initialQuery,
    this.initialActivityType,
  });

  @override
  State<_SimpleProductFormInternal> createState() =>
      _SimpleProductFormInternalState();
}

class _SimpleProductFormInternalState extends State<_SimpleProductFormInternal> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _barcodeCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _sellCtrl;
  late TextEditingController _wholesaleCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _minStockCtrl;
  late TextEditingController _descCtrl;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _barcodeFocus = FocusNode();
  final FocusNode _costFocus = FocusNode();
  final FocusNode _sellFocus = FocusNode();
  final FocusNode _wholesaleFocus = FocusNode();
  final FocusNode _qtyFocus = FocusNode();
  final FocusNode _minStockFocus = FocusNode();
  final FocusNode _descFocus = FocusNode();
  List<CategoryEntity> _lastCategories = const [];

  String? _selectedCategoryId;
  String? _existingVariantId;
  bool _loadingVariant = false;
  bool _isSaving = false;

  late ActivityType _activityType;
  late TextEditingController _warrantyCtrl;
  late TextEditingController _brandOrModelCtrl;
  late TextEditingController _imeiCtrl;
  late TextEditingController _expiryCtrl;
  String _measurementUnit = 'piece'; // 'piece', 'weight'
  late bool _isInstallmentEligible;
  bool _isRollMode = false;
  late TextEditingController _rollWidthCtrl;

  late TextEditingController _ingredientsCtrl;
  late TextEditingController _caloriesCtrl;
  late TextEditingController _prepTimeCtrl;
  String? _kitchenStation;
  final Set<String> _selectedAllergens = {};
  String? _foodImagePath;

  List<RecipeItemData> _recipeItems = [];
  List<ProductEntity> _availableRawMaterials = [];
  Map<String, double> _rawMaterialUnitCosts = {};
  String _mealStockMode = 'onDemand';
  final TextEditingController _dailyBatchCountCtrl = TextEditingController();
  List<PaidModifierData> _paidModifiers = [];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (widget.initialActivityType != null) {
      _activityType = widget.initialActivityType!;
      _isRollMode = false;
      _rollWidthCtrl = TextEditingController(text: '1.0 م');
    } else if (p != null) {
      _activityType = p.activityTypeEnum;
      _isRollMode = p.sellMode == 'meter';
      _rollWidthCtrl = TextEditingController(text: p.rollWidth ?? '1.0 م');
    } else {
      _isRollMode = false;
      _rollWidthCtrl = TextEditingController(text: '1.0 م');
      if (getIt.isRegistered<ActivitySettingsService>()) {
        final cached = getIt<ActivitySettingsService>().cachedEnabledActivities;
        if (cached.contains(ActivityType.restaurantsCafes)) {
          _activityType = ActivityType.restaurantsCafes;
        } else if (cached.isNotEmpty) {
          _activityType = cached.first;
        } else {
          _activityType = ActivityType.clothing;
        }
      } else {
        _activityType = ActivityType.clothing;
      }
    }
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _barcodeCtrl = TextEditingController();
    _costCtrl = TextEditingController(text: '0.00');
    _sellCtrl = TextEditingController(text: '0.00');
    _wholesaleCtrl = TextEditingController(text: '0.00');
    _qtyCtrl = TextEditingController(text: _activityType == ActivityType.restaurantsCafes ? '999' : '0');
    _minStockCtrl = TextEditingController(text: '${p?.minStock ?? 5}');
    final cul = p?.culinaryData;
    _ingredientsCtrl = TextEditingController(text: cul?.ingredients ?? '');
    _caloriesCtrl = TextEditingController(
        text: cul?.calories != null ? '${cul!.calories}' : '');
    _prepTimeCtrl = TextEditingController(
        text: cul?.prepTimeMinutes != null ? '${cul!.prepTimeMinutes}' : '');
    _kitchenStation = cul?.kitchenStation;
    _foodImagePath = p?.foodImagePath;
    if (cul != null && cul.allergens.isNotEmpty) {
      _selectedAllergens.addAll(cul.allergens);
    }
    if (p != null) {
      _recipeItems = List<RecipeItemData>.from(p.restaurantRecipeItems);
      _mealStockMode = p.mealStockMode;
      if (p.dailyBatchCount != null) {
        _dailyBatchCountCtrl.text = '${p.dailyBatchCount}';
      }
      _paidModifiers = List<PaidModifierData>.from(p.paidModifiers);
    }
    _sellCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _descCtrl = TextEditingController(text: p?.cleanDescription ?? '');
    _warrantyCtrl = TextEditingController(text: p?.warrantyPeriod ?? '');
    _brandOrModelCtrl = TextEditingController(text: p?.brandOrModel ?? '');
    _imeiCtrl = TextEditingController();
    _expiryCtrl = TextEditingController();
    _isInstallmentEligible = p?.isInstallmentEligible ?? true;
    _selectedCategoryId = p?.categoryId;

    _loadRawMaterials();

    if (p != null) {
      _loadExistingVariant(p.id);
    } else {
      if (getIt.isRegistered<ActivitySettingsService>() && widget.initialActivityType == null) {
        getIt<ActivitySettingsService>().getEnabledActivities().then((acts) {
          if (mounted && acts.isNotEmpty) {
            final target = acts.contains(ActivityType.restaurantsCafes)
                ? ActivityType.restaurantsCafes
                : acts.first;
            if (target != _activityType) {
              setState(() {
                _activityType = target;
                if (_activityType == ActivityType.restaurantsCafes) {
                  if (_qtyCtrl.text == '0' || _qtyCtrl.text.isEmpty) {
                    _qtyCtrl.text = '999';
                  }
                  if (_barcodeCtrl.text.isEmpty || _barcodeCtrl.text.startsWith('200')) {
                    _generateBarcode();
                  }
                }
              });
            }
          }
        });
      }
      final query = widget.initialQuery?.trim();
      if (query != null && query.isNotEmpty) {
        if (RegExp(r'^[0-9]+$').hasMatch(query)) {
          _barcodeCtrl.text = query;
        } else {
          _nameCtrl.text = query;
          _generateBarcode();
        }
      } else {
        _generateBarcode();
      }
    }
  }

  Future<void> _loadExistingVariant(String productId) async {
    setState(() => _loadingVariant = true);
    try {
      if (getIt.isRegistered<VariantLocalDataSource>()) {
        final ds = getIt<VariantLocalDataSource>();
        final variants = await ds.getVariants(productId);
        if (variants.isNotEmpty && mounted) {
          final v = variants.first;
          _existingVariantId = v.id;
          _barcodeCtrl.text = v.sku;
          _costCtrl.text = Money(v.costPrice).toDisplay();
          _sellCtrl.text = Money(v.sellPrice).toDisplay();
          _wholesaleCtrl.text = Money(v.wholesalePrice).toDisplay();
          _qtyCtrl.text = '${v.quantity}';
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loadingVariant = false);
    }
  }

  void _generateBarcode() {
    if (_activityType == ActivityType.restaurantsCafes) {
      _barcodeCtrl.text = 'REST-${DateTime.now().millisecondsSinceEpoch % 1000000}';
    } else {
      final rand = Random().nextInt(899999) + 100000;
      _barcodeCtrl.text = '200$rand';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _costCtrl.dispose();
    _sellCtrl.dispose();
    _wholesaleCtrl.dispose();
    _qtyCtrl.dispose();
    _minStockCtrl.dispose();
    _descCtrl.dispose();
    _nameFocus.dispose();
    _barcodeFocus.dispose();
    _costFocus.dispose();
    _sellFocus.dispose();
    _wholesaleFocus.dispose();
    _qtyFocus.dispose();
    _minStockFocus.dispose();
    _descFocus.dispose();
    _ingredientsCtrl.dispose();
    _caloriesCtrl.dispose();
    _prepTimeCtrl.dispose();
    _warrantyCtrl.dispose();
    _brandOrModelCtrl.dispose();
    _imeiCtrl.dispose();
    _expiryCtrl.dispose();
    _rollWidthCtrl.dispose();
    _dailyBatchCountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRawMaterials() async {
    try {
      List<ProductEntity> rawMaterials = [];
      final Map<String, double> unitCosts = {};

      if (getIt.isRegistered<ProductRepository>()) {
        final res = await getIt<ProductRepository>().getProducts();
        final list = res.getOrElse(() => []);
        rawMaterials = list.where((p) => p.culinaryData.isRawMaterial).toList();
      }

      if (rawMaterials.isEmpty && getIt.isRegistered<AppDatabase>()) {
        final db = getIt<AppDatabase>();
        final prods = await (db.select(db.products)..where((p) => p.deletedAt.isNull())).get();
        rawMaterials = prods
            .where((p) => RestaurantCulinaryData.parse(p.description).isRawMaterial)
            .map((p) => ProductEntity(
                  id: p.id,
                  name: p.name,
                  description: p.description ?? '',
                  categoryId: p.categoryId,
                  categoryName: '',
                  createdAt: p.createdAt,
                  activityType: p.activityType,
                ))
            .toList();
      }

      if (getIt.isRegistered<AppDatabase>()) {
        final db = getIt<AppDatabase>();
        final rawIds = rawMaterials.map((r) => r.id).toSet();
        if (rawIds.isNotEmpty) {
          final allVariants = await (db.select(db.productVariants)
                ..where((v) => v.productId.isIn(rawIds))
                ..where((v) => v.deletedAt.isNull()))
              .get();
          for (final raw in rawMaterials) {
            final matches = allVariants.where((v) => v.productId == raw.id);
            if (matches.isNotEmpty) {
              final purchaseCostPiasters = matches.first.costPrice;
              unitCosts[raw.id] = raw.costPerBaseUnit(purchaseCostPiasters);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _availableRawMaterials = rawMaterials;
          _rawMaterialUnitCosts = unitCosts;
        });
      }
    } catch (_) {}
  }

  int _parsePiasters(String text) {
    final cleaned = text.trim().replaceAll(',', '');
    final val = double.tryParse(cleaned) ?? 0.0;
    return (val * 100).round();
  }

  Future<void> _handleSave(List<CategoryEntity> categories) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null && categories.isNotEmpty) {
      _selectedCategoryId = categories.first.id;
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

    setState(() => _isSaving = true);

    final cleanName = _nameCtrl.text.trim();
    var cleanBarcode = _barcodeCtrl.text.trim();
    if (cleanBarcode.isEmpty) {
      if (_activityType == ActivityType.restaurantsCafes) {
        cleanBarcode = 'REST-${DateTime.now().millisecondsSinceEpoch % 1000000}';
      } else {
        cleanBarcode = 'SKU-${DateTime.now().millisecondsSinceEpoch % 1000000}';
      }
    }
    final costPiasters = _parsePiasters(_costCtrl.text);
    final sellPiasters = _parsePiasters(_sellCtrl.text);
    final wholesalePiasters = _parsePiasters(_wholesaleCtrl.text);
    final defaultQty = _activityType == ActivityType.restaurantsCafes ? 999 : 0;
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? defaultQty;
    final minStock = int.tryParse(_minStockCtrl.text.trim()) ?? 5;
    final String? finalDesc;
    if (_activityType == ActivityType.restaurantsCafes) {
      final cul = RestaurantCulinaryData(
        ingredients: _ingredientsCtrl.text.trim().isEmpty ? null : _ingredientsCtrl.text.trim(),
        calories: int.tryParse(_caloriesCtrl.text.trim()),
        allergens: _selectedAllergens.toList(),
        prepTimeMinutes: int.tryParse(_prepTimeCtrl.text.trim()),
        kitchenStation: _kitchenStation,
        userDescription: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        imagePath: _foodImagePath,
        recipeItems: _recipeItems,
        mealStockMode: _mealStockMode,
        dailyBatchCount: int.tryParse(_dailyBatchCountCtrl.text.trim()),
        paidModifiers: _paidModifiers,
      );
      finalDesc = cul.toEncodedString();
    } else {
      finalDesc = _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
    }

    final formCubit = context.read<ProductFormCubit>();
    final authState = context.read<AuthCubit>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : 'admin';

    try {
      if (widget.product == null) {
        // Adding new simple product
        final catMatch = categories.firstWhere(
          (c) => c.id == _selectedCategoryId,
          orElse: () => CategoryEntity(
            id: _selectedCategoryId!,
            name: '',
            description: '',
            createdAt: DateTime.now(),
          ),
        );

        formCubit.onNameChanged(cleanName);
        formCubit.onCategoryChanged(_selectedCategoryId!, catMatch.name);
        formCubit.onDescriptionChanged(finalDesc ?? '');
        formCubit.onMinStockChanged(minStock);
        formCubit.onActivityTypeChanged(_activityType.code);
        formCubit.onWarrantyPeriodChanged(_warrantyCtrl.text.trim().isEmpty ? null : _warrantyCtrl.text.trim());
        formCubit.onBrandOrModelChanged(_brandOrModelCtrl.text.trim().isEmpty ? null : _brandOrModelCtrl.text.trim());
        formCubit.onInstallmentEligibleChanged(_isInstallmentEligible);

        final variant = VariantInput(
          size: _isRollMode ? 'رول ${_rollWidthCtrl.text.trim()}' : '-',
          color: '-',
          sku: cleanBarcode,
          costPrice: costPiasters,
          sellPrice: sellPiasters,
          quantity: qty,
        );

        await formCubit.submitWithVariants(variants: [variant]);

        if (!mounted) return;
        final state = formCubit.state;
        if (state.status == ProductFormStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage ?? 'حدث خطأ أثناء حفظ الصنف'),
              backgroundColor: AppColors.error,
            ),
          );
          setState(() => _isSaving = false);
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة الصنف "$cleanName" بنجاح'),
            backgroundColor: Colors.green.shade800,
          ),
        );
        Navigator.of(context).pop(cleanBarcode);
      } else {
        // Editing existing simple product
        final prod = widget.product!;
        final updatedProduct = ProductEntity(
          id: prod.id,
          name: cleanName,
          categoryId: _selectedCategoryId!,
          categoryName: prod.categoryName,
          description: finalDesc ?? '',
          minStock: minStock,
          createdAt: prod.createdAt,
          updatedAt: DateTime.now(),
          activityType: _activityType.code,
          warrantyPeriod: _warrantyCtrl.text.trim().isEmpty ? null : _warrantyCtrl.text.trim(),
          brandOrModel: _brandOrModelCtrl.text.trim().isEmpty ? null : _brandOrModelCtrl.text.trim(),
          isInstallmentEligible: _isInstallmentEligible,
        );

        final productRepo = getIt<ProductRepository>();
        final res = await productRepo.updateProduct(updatedProduct);
        final err = res.fold((f) => f.message, (_) => null);
        if (err != null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err), backgroundColor: AppColors.error),
          );
          setState(() => _isSaving = false);
          return;
        }

        // Update single variant if exists
        if (_existingVariantId != null &&
            getIt.isRegistered<VariantLocalDataSource>()) {
          final ds = getIt<VariantLocalDataSource>();
          await ds.updateVariant(
            _existingVariantId!,
            costPrice: costPiasters,
            sellPrice: sellPiasters,
            wholesalePrice: wholesalePiasters,
            quantity: qty,
            sku: cleanBarcode,
            userId: userId,
          );
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تعديل بيانات الصنف "$cleanName" بنجاح'),
            backgroundColor: Colors.green.shade800,
          ),
        );
        Navigator.of(context).pop(cleanBarcode);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
      setState(() => _isSaving = false);
    }
  }

  void _openAddCategoryQuick() async {
    final newCat = await showDialog<CategoryEntity?>(
      context: context,
      builder: (_) => const CategoryFormDialog(),
    );
    if (newCat != null && mounted) {
      setState(() {
        _selectedCategoryId = newCat.id;
      });
      context.read<ProductFormCubit>().reloadCategories(selectCategoryId: newCat.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;

    return BlocConsumer<ProductFormCubit, ProductFormState>(
      listener: (context, state) {
        if (state.categories.isNotEmpty && _selectedCategoryId == null) {
          setState(() {
            _selectedCategoryId = state.categories.first.id;
          });
        }
      },
      builder: (context, state) {
        if (_loadingVariant || state.status == ProductFormStatus.loading) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final categories = state.categories;
        _lastCategories = categories;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
              if (!_isSaving) _handleSave(_lastCategories);
            },
            const SingleActivator(LogicalKeyboardKey.f12): () {
              if (!_isSaving) _handleSave(_lastCategories);
            },
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (!_isSaving) Navigator.of(context).pop();
            },
          },
          child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isEdit ? Icons.edit_note_rounded : Icons.add_box_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isEdit ? 'تعديل بيانات الصنف' : 'إضافة صنف جديد (منتج مفرد)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Audit metadata card for editing mode
                      if (isEdit && widget.product != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.history_rounded,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Wrap(
                                  spacing: 16,
                                  runSpacing: 4,
                                  children: [
                                    Text(
                                      'أُضيف: ${widget.product!.createdAt.year}/${widget.product!.createdAt.month.toString().padLeft(2, '0')}/${widget.product!.createdAt.day.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                    if (widget.product!.updatedAt != null)
                                      Text(
                                        'آخر تعديل: ${widget.product!.updatedAt!.year}/${widget.product!.updatedAt!.month.toString().padLeft(2, '0')}/${widget.product!.updatedAt!.day.toString().padLeft(2, '0')} (${widget.product!.updatedAt!.hour.toString().padLeft(2, '0')}:${widget.product!.updatedAt!.minute.toString().padLeft(2, '0')})',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Activity Type Selector
                      const Text(
                        'نوع النشاط / القسم الرئيسي',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<List<ActivityType>>(
                        stream: getIt.isRegistered<ActivitySettingsService>()
                            ? getIt<ActivitySettingsService>().watchEnabledActivities()
                            : Stream.value(ActivityType.values),
                        builder: (context, snapshot) {
                          final enabledActs = snapshot.data ?? ActivityType.values;
                          final list = {...enabledActs, _activityType}.toList();

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: list.map((act) {
                                final isSelected = _activityType == act;
                                return Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _activityType = act;
                                        if (act == ActivityType.restaurantsCafes) {
                                          if (_qtyCtrl.text == '0' || _qtyCtrl.text.isEmpty) {
                                            _qtyCtrl.text = '999';
                                          }
                                          if (_barcodeCtrl.text.isEmpty || _barcodeCtrl.text.startsWith('200')) {
                                            _generateBarcode();
                                          }
                                        }
                                      });
                                      context.read<ProductFormCubit>().onActivityTypeChanged(act.code);
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
                      const SizedBox(height: 16),

                      // Name & Barcode
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _nameCtrl,
                              focusNode: _nameFocus,
                              autofocus: true,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _barcodeFocus.requestFocus(),
                              decoration: InputDecoration(
                                labelText: 'اسم الصنف / المنتج *',
                                hintText: _activityType == ActivityType.restaurantsCafes
                                    ? 'مثال: برجر دبل تشيز / بيتزا مارجريتا / كابتشينو'
                                    : 'مثال: طقم حلل جرانيت 10 قطع / شيبسي جبنة',
                                prefixIcon: Icon(
                                  _activityType == ActivityType.restaurantsCafes
                                      ? Icons.restaurant_menu_rounded
                                      : Icons.inventory_2_outlined,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'اسم الصنف مطلوب';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _barcodeCtrl,
                              focusNode: _barcodeFocus,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _costFocus.requestFocus(),
                              decoration: InputDecoration(
                                labelText: _activityType == ActivityType.restaurantsCafes
                                    ? 'الباركود / الكود (SKU) (اختياري)'
                                    : 'الباركود / الكود (SKU) *',
                                prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                                suffixIcon: IconButton(
                                  tooltip: 'توليد باركود تلقائي',
                                  icon: const Icon(Icons.autorenew_rounded),
                                  onPressed: _generateBarcode,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (v) {
                                if (_activityType != ActivityType.restaurantsCafes) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'الباركود مطلوب';
                                  }
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Category selector
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: categories.any((c) => c.id == _selectedCategoryId)
                                  ? _selectedCategoryId
                                  : (categories.isNotEmpty ? categories.first.id : null),
                              decoration: InputDecoration(
                                labelText: 'القسم / التصنيف *',
                                prefixIcon: const Icon(Icons.category_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              items: categories
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
                              validator: (v) {
                                if (_selectedCategoryId == null && v == null) {
                                  return 'يرجى اختيار القسم';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('قسم جديد'),
                            onPressed: _openAddCategoryQuick,
                          ),
                        ],
                      ),

                      if (_activityType == ActivityType.restaurantsCafes) ...[
                        const SizedBox(height: 16),
                        CulinaryProfileCard(
                          ingredientsController: _ingredientsCtrl,
                          caloriesController: _caloriesCtrl,
                          prepTimeController: _prepTimeCtrl,
                          selectedAllergens: _selectedAllergens,
                          selectedKitchenStation: _kitchenStation,
                          imagePath: _foodImagePath,
                          recipeItems: _recipeItems,
                          availableRawMaterials: _availableRawMaterials,
                          rawMaterialUnitCosts: _rawMaterialUnitCosts,
                          salePricePiasters: _parsePiasters(_sellCtrl.text),
                          mealStockMode: _mealStockMode,
                          onMealStockModeChanged: (mode) =>
                              setState(() => _mealStockMode = mode),
                          dailyBatchCountController: _dailyBatchCountCtrl,
                          paidModifiers: _paidModifiers,
                          onPaidModifiersChanged: (mods) =>
                              setState(() => _paidModifiers = mods),
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
                          onRecipeItemsChanged: (items) {
                            setState(() {
                              _recipeItems = items;
                              // تحديث سعر التكلفة التلقائي للوجبة بناء على مقاديرها:
                              final totalCost =
                                  FoodCostCalculator.calculateTotalRecipeCostPiasters(
                                recipeItems: items,
                                rawMaterialUnitCostsPiasters: _rawMaterialUnitCosts,
                              );
                              if (totalCost > 0) {
                                _costCtrl.text =
                                    (totalCost / 100.0).toStringAsFixed(2);
                              }
                            });
                          },
                        ),
                      ],

                      if (_activityType.supportsBrandOrModel ||
                          _activityType.supportsWarranty ||
                          _activityType.supportsIMEI ||
                          _activityType.supportsWeight ||
                          _activityType.supportsExpiry ||
                          _activityType.supportsInstallment ||
                          _activityType.supportsCutToLength) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(_activityType.icon, size: 18, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'خصائص ${_activityType.labelArabic}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_activityType.supportsBrandOrModel || _activityType.supportsWarranty)
                                Row(
                                  children: [
                                    if (_activityType.supportsBrandOrModel)
                                      Expanded(
                                        child: TextFormField(
                                          controller: _brandOrModelCtrl,
                                          decoration: InputDecoration(
                                            labelText: 'الماركة أو الموديل (اختياري)',
                                            hintText: 'مثال: توشيبا، تيفال، سوني',
                                            prefixIcon: const Icon(Icons.branding_watermark_outlined),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            filled: true,
                                            fillColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    if (_activityType.supportsBrandOrModel && _activityType.supportsWarranty)
                                      const SizedBox(width: 10),
                                    if (_activityType.supportsWarranty)
                                      Expanded(
                                        child: TextFormField(
                                          controller: _warrantyCtrl,
                                          decoration: InputDecoration(
                                            labelText: 'فترة الضمان بالشهور (اختياري)',
                                            hintText: 'مثال: 12 شهر، 24 شهر',
                                            prefixIcon: const Icon(Icons.verified_user_outlined),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            filled: true,
                                            fillColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              if (_activityType.supportsIMEI || _activityType.supportsExpiry) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    if (_activityType.supportsIMEI)
                                      Expanded(
                                        child: TextFormField(
                                          controller: _imeiCtrl,
                                          decoration: InputDecoration(
                                            labelText: 'السيريال / IMEI (اختياري)',
                                            hintText: 'مثال: 356938035643809',
                                            prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            filled: true,
                                            fillColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    if (_activityType.supportsIMEI && _activityType.supportsExpiry)
                                      const SizedBox(width: 10),
                                    if (_activityType.supportsExpiry)
                                      Expanded(
                                        child: TextFormField(
                                          controller: _expiryCtrl,
                                          decoration: InputDecoration(
                                            labelText: 'تاريخ الصلاحية / التشغيلة (اختياري)',
                                            hintText: 'مثال: 2026/12/31',
                                            prefixIcon: const Icon(Icons.event_busy_rounded),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            filled: true,
                                            fillColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              if (_activityType.supportsWeight) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.scale_rounded, size: 18, color: Color(0xFF64748B)),
                                        SizedBox(width: 8),
                                        Text(
                                          'نوع القياس والبيع:',
                                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    ChoiceChip(
                                      label: const Text('بالقطعة'),
                                      selected: _measurementUnit == 'piece',
                                      onSelected: (val) => setState(() => _measurementUnit = 'piece'),
                                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                    ),
                                    ChoiceChip(
                                      label: const Text('بالوزن (كيلو / جرام / ميزان)'),
                                      selected: _measurementUnit == 'weight',
                                      onSelected: (val) => setState(() => _measurementUnit = 'weight'),
                                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                    ),
                                  ],
                                ),
                              ],
                              if (_activityType.supportsInstallment) ...[
                                const SizedBox(height: 10),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('متاح للبيع بالتقسيط', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                  subtitle: const Text('يمكن إدراج هذا الصنف في خطط وعقود التقسيط', style: TextStyle(fontSize: 11)),
                                  value: _isInstallmentEligible,
                                  activeThumbColor: AppColors.primary,
                                  onChanged: (val) => setState(() => _isInstallmentEligible = val),
                                ),
                              ],
                              if (_activityType.supportsCutToLength) ...[
                                const SizedBox(height: 10),
                                Container(
                                  key: const Key('simple_carpet_roll_mode'),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.outlineVariant),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('بيع بالمتر (توب / رول مقصوص)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                        subtitle: const Text('تفعيل بيع الأمتار الطولية بالكسور العشرية في الكاشير', style: TextStyle(fontSize: 11)),
                                        value: _isRollMode,
                                        activeThumbColor: AppColors.primary,
                                        onChanged: (val) => setState(() => _isRollMode = val),
                                      ),
                                      if (_isRollMode) ...[
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          key: const Key('simple_roll_width_field'),
                                          controller: _rollWidthCtrl,
                                          decoration: InputDecoration(
                                            labelText: 'عرض الرول / المشاية *',
                                            hintText: 'مثال: 1.0 م أو 4.0 م',
                                            prefixIcon: const Icon(Icons.format_size_rounded),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            filled: true,
                                            fillColor: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (_activityType == ActivityType.textilesDecor) ...[
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      key: const Key('open_textiles_matrix_btn'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.primary,
                                        side: BorderSide(color: AppColors.primary),
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.grid_view_rounded, size: 18),
                                      label: const Text(
                                        'إضافة بعدة مقاسات وألوان (مصفوفة المفروشات)',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      onPressed: () {
                                        final nav = Navigator.of(context);
                                        nav.pop();
                                        showDialog(
                                          context: nav.context,
                                          barrierDismissible: false,
                                          builder: (_) => ProductFormDialog(product: widget.product),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),
                      const Divider(),
                      const SizedBox(height: 10),

                      const Text(
                        'الأسعار والمخزون',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Prices Row
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _costCtrl,
                              focusNode: _costFocus,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _sellFocus.requestFocus(),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'سعر التكلفة (ج.م) *',
                                prefixIcon: const Icon(Icons.monetization_on_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'مطلوب';
                                }
                                final p = double.tryParse(v.trim());
                                if (p == null || p < 0) return 'سعر غير صالح';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _sellCtrl,
                              focusNode: _sellFocus,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _wholesaleFocus.requestFocus(),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'سعر البيع قطاعي (ج.م) *',
                                prefixIcon: const Icon(Icons.point_of_sale_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'مطلوب';
                                }
                                final p = double.tryParse(v.trim());
                                if (p == null || p < 0) return 'سعر غير صالح';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _wholesaleCtrl,
                              focusNode: _wholesaleFocus,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _qtyFocus.requestFocus(),
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'سعر الجملة (اختياري)',
                                prefixIcon: const Icon(Icons.storefront_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Quantity & Min stock
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _qtyCtrl,
                              focusNode: _qtyFocus,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _minStockFocus.requestFocus(),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: isEdit
                                    ? 'الرصيد الحالي بالمخزن'
                                    : 'الكمية الأولية بالمخزن *',
                                prefixIcon: const Icon(Icons.warehouse_outlined),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'مطلوب';
                                final q = int.tryParse(v.trim());
                                if (q == null || q < 0) return 'رقم غير صالح';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _minStockCtrl,
                              focusNode: _minStockFocus,
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _descFocus.requestFocus(),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'حد الأمان / الطلب *',
                                prefixIcon: const Icon(Icons.warning_amber_rounded),
                                helperText: 'تنبيه عند انخفاض الرصيد عن هذا الحد',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'مطلوب';
                                final q = int.tryParse(v.trim());
                                if (q == null || q < 0) return 'رقم غير صالح';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Description
                      TextFormField(
                        controller: _descCtrl,
                        focusNode: _descFocus,
                        maxLines: 2,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_isSaving) _handleSave(categories);
                        },
                        decoration: InputDecoration(
                          labelText: 'ملاحظات / وصف إضافي (اختياري)',
                          prefixIcon: const Icon(Icons.notes_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Actions Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      key: const Key('simple_product_save_btn'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isSaving ? null : () => _handleSave(categories),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_rounded, color: Colors.white),
                      label: Text(
                        _isSaving
                            ? 'جاري الحفظ...'
                            : (isEdit ? 'حفظ التعديلات' : 'إضافة الصنف للمخزن'),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }
}
