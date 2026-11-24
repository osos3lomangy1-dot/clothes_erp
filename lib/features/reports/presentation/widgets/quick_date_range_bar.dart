import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/services/date_range_presets.dart';

class QuickDateRangeBar extends StatelessWidget {
  final QuickDatePreset selectedPreset;
  final ValueChanged<QuickDatePreset> onPresetSelected;

  const QuickDateRangeBar({
    super.key,
    required this.selectedPreset,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: QuickDatePreset.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final preset = QuickDatePreset.values[index];
          final isSelected = preset == selectedPreset;
          return ChoiceChip(
            key: Key('quick_date_chip_${preset.name}'),
            label: Text(
              preset.label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                color: isSelected ? Colors.white : AppColors.primary,
              ),
            ),
            selected: isSelected,
            selectedColor: AppColors.primary,
            backgroundColor: Colors.white,
            side: BorderSide(
              color: isSelected ? AppColors.primary : AppColors.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            showCheckmark: false,
            onSelected: (_) => onPresetSelected(preset),
          );
        },
      ),
    );
  }
}
