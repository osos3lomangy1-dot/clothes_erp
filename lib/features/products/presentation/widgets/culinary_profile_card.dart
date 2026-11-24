import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/services/food_cost_calculator.dart';

class CulinaryProfileCard extends StatelessWidget {
  final TextEditingController ingredientsController;
  final TextEditingController caloriesController;
  final TextEditingController prepTimeController;
  final Set<String> selectedAllergens;
  final String? selectedKitchenStation;
  final ValueChanged<String?> onKitchenStationChanged;
  final void Function(String allergen, bool selected) onAllergenToggled;
  final ValueChanged<int>? onPrepTimeSelected;
  final String? imagePath;
  final ValueChanged<String?>? onImagePathChanged;
  final List<RecipeItemData>? recipeItems;
  final ValueChanged<List<RecipeItemData>>? onRecipeItemsChanged;
  final List<ProductEntity>? availableRawMaterials;
  final Map<String, double>? rawMaterialUnitCosts;
  final int? salePricePiasters;
  final int? packagingCostPiasters;
  final String mealStockMode;
  final ValueChanged<String>? onMealStockModeChanged;
  final TextEditingController? dailyBatchCountController;
  final List<PaidModifierData>? paidModifiers;
  final ValueChanged<List<PaidModifierData>>? onPaidModifiersChanged;

  static const List<String> defaultAllergens = [
    'جلوتين / قمح',
    'لاكتوز / حليب',
    'مكسرات',
    'بيض',
    'سمك / مأكولات بحرية',
    'صويا',
    'سمسم',
  ];

  static const List<String> defaultKitchenStations = [
    'مطبخ ساخن (وجبات وجريل)',
    'بار المشروبات والعصائر',
    'فرن وبيتزا',
    'حلويات وسناكس',
  ];

  static const List<int> defaultPrepTimes = [10, 15, 20, 30];

  const CulinaryProfileCard({
    super.key,
    required this.ingredientsController,
    required this.caloriesController,
    required this.prepTimeController,
    required this.selectedAllergens,
    required this.selectedKitchenStation,
    required this.onKitchenStationChanged,
    required this.onAllergenToggled,
    this.onPrepTimeSelected,
    this.imagePath,
    this.onImagePathChanged,
    this.recipeItems,
    this.onRecipeItemsChanged,
    this.availableRawMaterials,
    this.rawMaterialUnitCosts,
    this.salePricePiasters,
    this.packagingCostPiasters,
    this.mealStockMode = 'onDemand',
    this.onMealStockModeChanged,
    this.dailyBatchCountController,
    this.paidModifiers,
    this.onPaidModifiersChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('culinary_profile_card'),
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
              Icon(Icons.restaurant_menu_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'بطاقة بيانات وتحضير الوجبة (القيم الغذائية والمطبخ)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 0. Food Image Selector
          const Text(
            'صورة الوجبة / المشروب:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 64,
                    height: 64,
                    color: Colors.grey.shade100,
                    child: (imagePath != null &&
                            imagePath!.trim().isNotEmpty &&
                            File(imagePath!).existsSync())
                        ? Image.file(
                            File(imagePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.restaurant_menu_rounded,
                              color: AppColors.onSurfaceVariant,
                            ),
                          )
                        : const Icon(
                            Icons.restaurant_menu_rounded,
                            color: AppColors.onSurfaceVariant,
                            size: 28,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (imagePath != null && imagePath!.trim().isNotEmpty)
                            ? 'تم تحديد صورة الوجبة'
                            : 'لم يتم تحديد صورة بعد',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: (imagePath != null && imagePath!.trim().isNotEmpty)
                              ? AppColors.primary
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'تظهر في شبكة كاشير المبيعات للتمييز السريع (JPG, PNG, WebP)',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (imagePath != null && imagePath!.trim().isNotEmpty) ...[
                  IconButton(
                    key: const Key('remove_culinary_image_btn'),
                    tooltip: 'حذف الصورة',
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                    onPressed: () => onImagePathChanged?.call(null),
                  ),
                ],
                ElevatedButton.icon(
                  key: const Key('pick_culinary_image_btn'),
                  onPressed: () async {
                    try {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                      );
                      if (result != null && result.files.isNotEmpty) {
                        final picked = result.files.single.path;
                        if (picked != null && picked.isNotEmpty) {
                          onImagePathChanged?.call(picked);
                        }
                      }
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label: Text(
                    (imagePath != null && imagePath!.trim().isNotEmpty)
                        ? 'تغيير'
                        : 'اختيار صورة',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 1. Ingredients
          TextFormField(
            key: const Key('culinary_ingredients_field'),
            controller: ingredientsController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'مكونات الوجبة / المشروب',
              hintText: 'مثال: لحم بقري 150جم، صوص مشروم، جبنة شيدر، طماطم، خس، خبز بريوش',
              prefixIcon: const Icon(Icons.dinner_dining_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),

          // 2. Calories & Preparation Time
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('culinary_calories_field'),
                  controller: caloriesController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'السعرات الحرارية (kcal)',
                    prefixIcon: const Icon(Icons.local_fire_department_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      key: const Key('culinary_prep_time_field'),
                      controller: prepTimeController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'وقت التحضير التقديري (بالدقائق)',
                        prefixIcon: const Icon(Icons.timer_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: defaultPrepTimes.map((mins) {
                        final isMatch = prepTimeController.text == '$mins';
                        return InkWell(
                          key: Key('prep_time_chip_$mins'),
                          onTap: () {
                            prepTimeController.text = '$mins';
                            onPrepTimeSelected?.call(mins);
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isMatch
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isMatch
                                    ? AppColors.primary
                                    : AppColors.outlineVariant,
                              ),
                            ),
                            child: Text(
                              '$mins دقائق',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isMatch
                                    ? AppColors.primary
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Kitchen Station Dropdown
          DropdownButtonFormField<String>(
            key: const Key('culinary_station_dropdown'),
            initialValue: defaultKitchenStations.contains(selectedKitchenStation)
                ? selectedKitchenStation
                : null,
            decoration: InputDecoration(
              labelText: 'محطة التحضير (المطبخ / البار)',
              prefixIcon: const Icon(Icons.soup_kitchen_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
            ),
            items: defaultKitchenStations.map((station) {
              return DropdownMenuItem<String>(
                value: station,
                child: Text(station, style: const TextStyle(fontSize: 13)),
              );
            }).toList(),
            onChanged: onKitchenStationChanged,
          ),
          const SizedBox(height: 14),

          // 4. Allergen Filter Chips
          const Text(
            'مسببات الحساسية (Allergens):',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          const Text(
            'اختر مسببات الحساسية للتحذير منها في كاشير المبيعات وبون تحضير المطبخ KOT',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: defaultAllergens.map((allergen) {
              final isSelected = selectedAllergens.contains(allergen);
              return FilterChip(
                key: Key('allergen_chip_$allergen'),
                label: Text(
                  allergen,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppColors.primary : Colors.black87,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                checkmarkColor: AppColors.primary,
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                  ),
                ),
                onSelected: (selected) => onAllergenToggled(allergen, selected),
              );
            }).toList(),
          ),

          // 5. Meal Stock Mode (On-Demand vs Daily Batch)
          const SizedBox(height: 14),
          const Text(
            'نمط رصيد الوجبة بالمطعم:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  key: const Key('stock_mode_ondemand_chip'),
                  onTap: () => onMealStockModeChanged?.call('onDemand'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: mealStockMode == 'onDemand'
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: mealStockMode == 'onDemand'
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                        width: mealStockMode == 'onDemand' ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.kitchen_rounded,
                          size: 16,
                          color: mealStockMode == 'onDemand'
                              ? AppColors.primary
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'تحضير فوري حسب الخامات',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: mealStockMode == 'onDemand'
                                ? AppColors.primary
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  key: const Key('stock_mode_dailybatch_chip'),
                  onTap: () => onMealStockModeChanged?.call('dailyBatch'),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: mealStockMode == 'dailyBatch'
                          ? AppColors.secondary.withValues(alpha: 0.15)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: mealStockMode == 'dailyBatch'
                            ? AppColors.secondary
                            : AppColors.outlineVariant,
                        width: mealStockMode == 'dailyBatch' ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_rounded,
                          size: 16,
                          color: mealStockMode == 'dailyBatch'
                              ? AppColors.secondary
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'كمية مجهزة لليوم (Batch)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: mealStockMode == 'dailyBatch'
                                ? AppColors.secondary
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (mealStockMode == 'dailyBatch' && dailyBatchCountController != null) ...[
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('culinary_daily_batch_field'),
              controller: dailyBatchCountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'عدد الوجبات المجهزة في بداية اليوم *',
                hintText: 'مثال: 20',
                prefixIcon: const Icon(Icons.pin_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ],

          // 6. Recipe BOM Builder Section (Addendum 30.10.1)
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.account_tree_outlined, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'خامات ومقادير الوجبة (Recipe BOM):',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                key: const Key('add_recipe_item_btn'),
                onPressed: () => _showAddRecipeItemDialog(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('إضافة خامة للوجبة', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (recipeItems == null || recipeItems!.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'لم يتم ربط مقادير خامات بهذه الوجبة. أضف الخامات لتتبع الاستهلاك الدقيق وحساب تكلفة الأغذية وهامش الربح.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                children: List.generate(recipeItems!.length, (idx) {
                  final item = recipeItems![idx];
                  final unitCost = rawMaterialUnitCosts?[item.rawMaterialId] ?? 0.0;
                  final costPiasters = (item.calculateIngredientCost(unitCost)).round();
                  final qtyDisplay = item.quantityNeeded.toStringAsFixed(
                    item.quantityNeeded.truncateToDouble() == item.quantityNeeded ? 0 : 2,
                  );

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      border: idx < recipeItems!.length - 1
                          ? Border(bottom: BorderSide(color: Colors.grey.shade200))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            item.rawMaterialName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$qtyDisplay ${item.unit}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        if (item.yieldLossPercentage > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'فاقد: ${item.yieldLossPercentage.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                        if (costPiasters > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '(${Money(costPiasters).toDisplay()} ج.م)',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ],
                        const Spacer(),
                        IconButton(
                          key: Key('delete_recipe_item_${item.rawMaterialId}'),
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                          tooltip: 'حذف الخامة',
                          onPressed: () {
                            final updated = List<RecipeItemData>.from(recipeItems!)..removeAt(idx);
                            onRecipeItemsChanged?.call(updated);
                          },
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],

          // 7. Paid Modifiers Section
          if (paidModifiers != null && onPaidModifiersChanged != null) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'خيارات الإضافات المدفوعة (Paid Modifiers):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: const Key('add_paid_modifier_btn'),
                  onPressed: () {
                    final nameCtrl = TextEditingController();
                    final priceCtrl = TextEditingController(text: '15');
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('إضافة خيار أو إضافة مدفوعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              key: const Key('paid_modifier_name_input'),
                              controller: nameCtrl,
                              decoration: const InputDecoration(labelText: 'اسم الإضافة (مثال: جبنة شيدر إضافية)'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              key: const Key('paid_modifier_price_input'),
                              controller: priceCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'السعر الإضافي (ج.م)'),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                          ElevatedButton(
                            key: const Key('confirm_paid_modifier_btn'),
                            onPressed: () {
                              final name = nameCtrl.text.trim();
                              final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                              if (name.isNotEmpty) {
                                final updated = List<PaidModifierData>.from(paidModifiers!)
                                  ..add(PaidModifierData(name: name, pricePiasters: (price * 100).round()));
                                onPaidModifiersChanged!(updated);
                              }
                              Navigator.pop(ctx);
                            },
                            child: const Text('إضافة'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('إضافة خيار مدفوع', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            if (paidModifiers!.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: paidModifiers!.map((mod) {
                  return Chip(
                    label: Text('${mod.name} (+${mod.pricePounds.toStringAsFixed(0)} ج)'),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () {
                      final updated = List<PaidModifierData>.from(paidModifiers!)..remove(mod);
                      onPaidModifiersChanged!(updated);
                    },
                  );
                }).toList(),
              ),
          ],

          // 7. Live Food Cost & Profitability Badge
          if (recipeItems != null &&
              recipeItems!.isNotEmpty &&
              salePricePiasters != null &&
              salePricePiasters! > 0) ...[
            const SizedBox(height: 14),
            _buildFoodCostBadge(
              FoodCostCalculator.calculate(
                recipeItems: recipeItems!,
                rawMaterialUnitCostsPiasters: rawMaterialUnitCosts ?? const {},
                salePricePiasters: salePricePiasters!,
                packagingCostPiasters: packagingCostPiasters ?? 0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFoodCostBadge(FoodCostAnalysis analysis) {
    return Container(
      key: const Key('food_cost_analysis_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: analysis.badgeColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: analysis.badgeTextColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            analysis.rating == FoodCostRating.high
                ? Icons.warning_amber_rounded
                : Icons.pie_chart_outline_rounded,
            size: 18,
            color: analysis.badgeTextColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '[ ${analysis.summaryText} ]',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: analysis.badgeTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<ProductEntity>> _fetchRawMaterials() async {
    if (availableRawMaterials != null && availableRawMaterials!.isNotEmpty) {
      return availableRawMaterials!;
    }
    try {
      if (getIt.isRegistered<ProductRepository>()) {
        final res = await getIt<ProductRepository>().getProducts();
        final list = res.getOrElse(() => []);
        final raw = list.where((p) => p.culinaryData.isRawMaterial).toList();
        if (raw.isNotEmpty) return raw;
      }
    } catch (_) {}
    try {
      if (getIt.isRegistered<AppDatabase>()) {
        final db = getIt<AppDatabase>();
        final prods = await (db.select(db.products)..where((p) => p.deletedAt.isNull())).get();
        final raw = prods
            .where((p) => RestaurantCulinaryData.parse(p.description).isRawMaterial)
            .map((p) => ProductEntity(
                  id: p.id,
                  name: p.name,
                  description: p.description ?? '',
                  categoryId: p.categoryId,
                  categoryName: '',
                  createdAt: p.createdAt,
                ))
            .toList();
        if (raw.isNotEmpty) return raw;
      }
    } catch (_) {}
    return availableRawMaterials ?? const [];
  }

  Future<void> _showAddRecipeItemDialog(BuildContext context) async {
    final rawMaterials = await _fetchRawMaterials();
    if (!context.mounted) return;

    if (rawMaterials.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('لا توجد خامات مسجلة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          content: const Text(
            'لم يتم العثور على خامات أو مستلزمات مسجلة بالمخزن.\nيرجى تسجيل المواد الخام أولاً في شاشة المنتجات أو المشتريات.',
            style: TextStyle(fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      return;
    }

    ProductEntity selectedRawMaterial = rawMaterials.first;
    final qtyCtrl = TextEditingController(text: '100');
    final yieldCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final unit = selectedRawMaterial.culinaryData.baseUnit?.trim().isNotEmpty == true
              ? selectedRawMaterial.culinaryData.baseUnit!.trim()
              : 'جرام';

          return AlertDialog(
            key: const Key('add_recipe_item_dialog'),
            title: const Text(
              'إضافة خامة لمقادير الوجبة (BOM)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<ProductEntity>(
                    key: const Key('select_recipe_raw_material_dropdown'),
                    isExpanded: true,
                    initialValue: selectedRawMaterial,
                    decoration: const InputDecoration(
                      labelText: 'اختر الخامة أو المستلزم *',
                      border: OutlineInputBorder(),
                    ),
                    items: rawMaterials.map((rm) {
                      final bUnit = rm.culinaryData.baseUnit?.trim().isNotEmpty == true
                          ? rm.culinaryData.baseUnit!.trim()
                          : 'جرام';
                      return DropdownMenuItem<ProductEntity>(
                        value: rm,
                        child: Text('${rm.name} (الوحدة الأساسية: $bUnit)'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedRawMaterial = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('recipe_item_qty_field'),
                    controller: qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'الكمية المطلوبة بالوجبة *',
                      suffixText: unit,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('recipe_item_yield_loss_field'),
                    controller: yieldCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'نسبة فاقد الطهي % (انكماش/هدر طبيعي)',
                      hintText: '0.0',
                      suffixText: '%',
                      border: OutlineInputBorder(),
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
              ElevatedButton(
                key: const Key('confirm_add_recipe_item_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0.0;
                  final yieldLoss = double.tryParse(yieldCtrl.text.trim()) ?? 0.0;
                  if (qty <= 0) return;

                  final item = RecipeItemData(
                    rawMaterialId: selectedRawMaterial.id,
                    rawMaterialName: selectedRawMaterial.name,
                    quantityNeeded: qty,
                    yieldLossPercentage: yieldLoss,
                    unit: unit,
                  );

                  final updated = List<RecipeItemData>.from(recipeItems ?? [])..add(item);
                  onRecipeItemsChanged?.call(updated);
                  Navigator.pop(ctx);
                },
                child: const Text('إضافة الخامة'),
              ),
            ],
          );
        },
      ),
    );
  }
}
