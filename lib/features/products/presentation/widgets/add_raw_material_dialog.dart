import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clothes_erp/core/constants/app_colors.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/features/categories/domain/entities/category_entity.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/products/data/datasources/product_local_data_source.dart';
import 'package:clothes_erp/features/products/domain/entities/product_entity.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_cubit.dart';

class AddRawMaterialDialog extends StatefulWidget {
  const AddRawMaterialDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AddRawMaterialDialog(),
    );
  }

  @override
  State<AddRawMaterialDialog> createState() => _AddRawMaterialDialogState();
}

class _AddRawMaterialDialogState extends State<AddRawMaterialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _costCtrl = TextEditingController(text: '0.0');
  final _stockCtrl = TextEditingController(text: '100');
  final _minStockCtrl = TextEditingController(text: '10');

  String _selectedCategory = 'خامات ومستلزمات المطبخ';
  String _selectedBaseUnit = 'جرام';
  bool _isSaving = false;
  String? _errorMessage;

  static const List<String> _defaultCategories = [
    'خامات ومستلزمات المطبخ',
    'لحوم ودواجن',
    'ألبان وأجبان',
    'صوصات وتوابل',
    'خضار ومجمدات',
    'خامات جافة ومخبوزات',
    'تعبئة وتغليف',
    'خامات ومستلزمات البار',
  ];

  static const List<String> _availableUnits = [
    'جرام',
    'كيلوجرام',
    'ملليلتر',
    'لتر',
    'قطعة',
    'علبة',
    'كيس',
    'شريحة',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    _minStockCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final name = _nameCtrl.text.trim();
      final costPounds = double.tryParse(_costCtrl.text.trim()) ?? 0.0;
      final costPiasters = (costPounds * 100).round();
      final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;
      final minStock = int.tryParse(_minStockCtrl.text.trim()) ?? 5;

      final catRepo = getIt<CategoryRepository>();
      final prodRepo = getIt<ProductRepository>();

      // Ensure category exists
      final catRes = await catRepo.getCategories();
      final cats = catRes.fold((_) => <CategoryEntity>[], (c) => c);
      CategoryEntity? matchedCat = cats.cast<CategoryEntity?>().firstWhere(
            (c) => c?.name.trim() == _selectedCategory.trim(),
            orElse: () => null,
          );

      if (matchedCat == null) {
        final newCat = CategoryEntity(
          id: 'cat_${DateTime.now().microsecondsSinceEpoch}',
          name: _selectedCategory,
          description: 'قسم $_selectedCategory لنشاط المطاعم والكافيهات',
          createdAt: DateTime.now(),
        );
        await catRepo.addCategory(newCat);
        matchedCat = newCat;
      }

      final culData = RestaurantCulinaryData(
        isRawMaterial: true,
        baseUnit: _selectedBaseUnit,
        purchaseUnit: _selectedBaseUnit,
        conversionFactor: 1.0,
      );

      final rawId = 'raw_${DateTime.now().microsecondsSinceEpoch}';
      final product = ProductEntity(
        id: rawId,
        name: name,
        description: culData.toEncodedString(),
        categoryId: matchedCat.id,
        categoryName: matchedCat.name,
        minStock: minStock,
        createdAt: DateTime.now(),
        activityType: ActivityType.restaurantsCafes.name,
      );

      final variant = VariantInput(
        sku: 'RAW-${DateTime.now().millisecondsSinceEpoch % 1000000}',
        color: '-',
        size: '-',
        costPrice: costPiasters,
        sellPrice: 0,
        quantity: stock,
      );

      final res = await prodRepo.addProductWithVariants(product, [variant]);

      res.fold(
        (failure) {
          if (mounted) {
            setState(() {
              _isSaving = false;
              _errorMessage = 'فشل حفظ المادة الخام: ${failure.message}';
            });
          }
        },
        (_) {
          if (mounted) {
            try {
              context.read<ProductCubit>().getProducts();
            } catch (_) {}
            Navigator.of(context).pop(true);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'حدث خطأ غير متوقع: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.kitchen_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'إضافة مادة خام أو مستلزم جديد',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'تسجيل خامة أو عبوة تعبئة لاستخدامها في مقادير الوجبات (BOM)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 18),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: AppColors.error, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Raw Material Name Field
                  TextFormField(
                    key: const Key('add_raw_material_name_field'),
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم المادة الخام أو المستلزم *',
                      hintText: 'مثال: لحم بقري مفروم، حليب كامل الدسم، علبة برجر',
                      prefixIcon: const Icon(Icons.label_outline_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'يرجى إدخال اسم المادة الخام';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 14),

                  // Category & Base Unit Dropdowns Row
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const Key('add_raw_material_category_dropdown'),
                          initialValue: _selectedCategory,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'تصنيف الخامة *',
                            prefixIcon: const Icon(Icons.category_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          items: _defaultCategories.map((c) {
                            return DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedCategory = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const Key('add_raw_material_unit_dropdown'),
                          initialValue: _selectedBaseUnit,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'وحدة الصرف الأساسية *',
                            prefixIcon: const Icon(Icons.straighten_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          items: _availableUnits.map((u) {
                            return DropdownMenuItem(value: u, child: Text(u));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedBaseUnit = val);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Cost per base unit & Initial Stock Row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const Key('add_raw_material_cost_field'),
                          controller: _costCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'تكلفة الوحدة (ج.م) *',
                            hintText: '0.0',
                            prefixIcon: const Icon(Icons.attach_money_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'أدخل التكلفة';
                            if (double.tryParse(v.trim()) == null) return 'رقم غير صحيح';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: const Key('add_raw_material_stock_field'),
                          controller: _stockCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'الرصيد الافتتاحي بالمخزن *',
                            hintText: '100',
                            prefixIcon: const Icon(Icons.inventory_2_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'أدخل الرصيد';
                            if (int.tryParse(v.trim()) == null) return 'رقم صحيح مطلوب';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Min stock alert
                  TextFormField(
                    key: const Key('add_raw_material_min_stock_field'),
                    controller: _minStockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'حد تنبيه النواقص بالمخزن',
                      hintText: '10',
                      prefixIcon: const Icon(Icons.warning_amber_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Actions Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                        child: const Text('إلغاء'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        key: const Key('save_raw_material_btn'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isSaving ? null : _handleSave,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                        label: Text(
                          _isSaving ? 'جارِ الحفظ...' : 'حفظ المادة الخام',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
