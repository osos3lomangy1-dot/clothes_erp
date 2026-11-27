import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/app_colors.dart';
import 'custom_date_range_dialog.dart';

/// Unified date-filter bar (`الكل | اليوم | آخر 7 أيام | هذا الشهر | تحديد تاريخ / فترة`)
/// used across list screens (invoices, returns, purchases, shifts) for a single consistent UX.
class StandardDateFilterChips extends StatelessWidget {
  final String activeFilter;
  final DateTimeRange? customRange;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<DateTimeRange> onCustomRangePicked;

  const StandardDateFilterChips({
    super.key,
    required this.activeFilter,
    required this.customRange,
    required this.onFilterChanged,
    required this.onCustomRangePicked,
  });

  /// Shared helper to check if [date] falls within [activeFilter] / [customRange].
  static bool matchesDate(
    DateTime date,
    String activeFilter,
    DateTimeRange? customRange,
  ) {
    if (activeFilter == 'all') return true;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    if (activeFilter == 'today') {
      return !date.isBefore(todayStart);
    }
    if (activeFilter == 'week') {
      final weekStart = todayStart.subtract(const Duration(days: 6));
      return !date.isBefore(weekStart);
    }
    if (activeFilter == 'month') {
      final monthStart = DateTime(now.year, now.month, 1);
      return !date.isBefore(monthStart);
    }
    if (activeFilter == 'custom' && customRange != null) {
      final start = DateTime(
        customRange.start.year,
        customRange.start.month,
        customRange.start.day,
      );
      final end = DateTime(
        customRange.end.year,
        customRange.end.month,
        customRange.end.day,
        23,
        59,
        59,
        999,
      );
      return !date.isBefore(start) && !date.isAfter(end);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _chip('الكل', 'all'),
        _chip('اليوم', 'today'),
        _chip('آخر 7 أيام', 'week'),
        _chip('هذا الشهر', 'month'),
        _customChip(context),
      ],
    );
  }

  Widget _chip(String label, String value) {
    final active = activeFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: active ? FontWeight.bold : FontWeight.w500,
          color: active ? Colors.white : AppColors.onSurface,
        ),
      ),
      selected: active,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceContainerLowest,
      side: BorderSide(
        color: active ? AppColors.primary : AppColors.outlineVariant,
      ),
      onSelected: (_) => onFilterChanged(value),
    );
  }

  Widget _customChip(BuildContext context) {
    final active = activeFilter == 'custom' && customRange != null;
    String label = 'تحديد تاريخ / فترة';
    if (active) {
      final s = customRange!.start;
      final e = customRange!.end;
      final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
      label = sameDay
          ? DateFormat('yyyy/MM/dd').format(s)
          : '${DateFormat('MM/dd').format(s)} - ${DateFormat('MM/dd').format(e)}';
    }
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: active ? FontWeight.bold : FontWeight.w500,
          color: active ? Colors.white : AppColors.onSurface,
        ),
      ),
      selected: active,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceContainerLowest,
      side: BorderSide(
        color: active ? AppColors.primary : AppColors.outlineVariant,
      ),
      onSelected: (_) async {
        final picked = await showCustomDateRangeDialog(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: customRange,
        );
        if (picked != null) {
          onCustomRangePicked(picked);
        }
      },
    );
  }
}
