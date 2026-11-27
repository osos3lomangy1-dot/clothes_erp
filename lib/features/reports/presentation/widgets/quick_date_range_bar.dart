import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/services/date_range_presets.dart';

class QuickDateRangeBar extends StatelessWidget {
  final QuickDatePreset selectedPreset;
  final ValueChanged<QuickDatePreset> onPresetSelected;
  final DateTimeRange? customRange;

  const QuickDateRangeBar({
    super.key,
    required this.selectedPreset,
    required this.onPresetSelected,
    this.customRange,
  });

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _chipLabel(QuickDatePreset preset) {
    if (preset == QuickDatePreset.custom &&
        selectedPreset == QuickDatePreset.custom &&
        customRange != null) {
      final s = customRange!.start;
      final e = customRange!.end;
      if (s.year == e.year && s.month == e.month && s.day == e.day) {
        return _fmtDate(s);
      }
      return '${_fmtDate(s)} ← ${_fmtDate(e)}';
    }
    return preset.label;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: QuickDatePreset.values.map((preset) {
        final isSelected = preset == selectedPreset;
        return ChoiceChip(
          key: Key('quick_date_chip_${preset.name}'),
          label: Text(
            _chipLabel(preset),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: isSelected ? Colors.white : AppColors.primary,
            ),
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          visualDensity: VisualDensity.compact,
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
      }).toList(),
    );
  }
}
