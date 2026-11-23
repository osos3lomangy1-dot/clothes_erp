import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

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
        ],
      ),
    );
  }
}
