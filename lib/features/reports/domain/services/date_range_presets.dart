import 'package:flutter/material.dart';

enum QuickDatePreset {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  lastMonth,
  last30Days,
  thisYear,
  custom,
}

extension QuickDatePresetX on QuickDatePreset {
  String get label {
    switch (this) {
      case QuickDatePreset.today:
        return 'اليوم';
      case QuickDatePreset.yesterday:
        return 'أمس';
      case QuickDatePreset.thisWeek:
        return 'هذا الأسبوع';
      case QuickDatePreset.thisMonth:
        return 'هذا الشهر';
      case QuickDatePreset.lastMonth:
        return 'الشهر السابق';
      case QuickDatePreset.last30Days:
        return 'آخر 30 يوم';
      case QuickDatePreset.thisYear:
        return 'هذه السنة';
      case QuickDatePreset.custom:
        return 'فترة مخصصة';
    }
  }
}

class DateRangeEngine {
  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 0, 0, 0);
  static DateTime _endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  /// Resolves a [QuickDatePreset] to an exact [DateTimeRange] from 00:00:00 to 23:59:59.999.
  static DateTimeRange resolveRange(QuickDatePreset preset, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final todayStart = _startOfDay(n);
    final todayEnd = _endOfDay(n);

    switch (preset) {
      case QuickDatePreset.today:
        return DateTimeRange(start: todayStart, end: todayEnd);
      case QuickDatePreset.yesterday:
        final y = todayStart.subtract(const Duration(days: 1));
        return DateTimeRange(start: _startOfDay(y), end: _endOfDay(y));
      case QuickDatePreset.thisWeek:
        // Week starts on Saturday for Egyptian retail
        final daysSinceSaturday = (n.weekday - DateTime.saturday + 7) % 7;
        final weekStart = todayStart.subtract(Duration(days: daysSinceSaturday));
        return DateTimeRange(start: _startOfDay(weekStart), end: todayEnd);
      case QuickDatePreset.thisMonth:
        final monthStart = DateTime(n.year, n.month, 1);
        return DateTimeRange(start: _startOfDay(monthStart), end: todayEnd);
      case QuickDatePreset.lastMonth:
        final prevMonthStart = DateTime(n.year, n.month - 1, 1);
        final prevMonthEnd = DateTime(n.year, n.month, 0);
        return DateTimeRange(
          start: _startOfDay(prevMonthStart),
          end: _endOfDay(prevMonthEnd),
        );
      case QuickDatePreset.last30Days:
        final start = todayStart.subtract(const Duration(days: 29));
        return DateTimeRange(start: _startOfDay(start), end: todayEnd);
      case QuickDatePreset.thisYear:
        final yearStart = DateTime(n.year, 1, 1);
        return DateTimeRange(start: _startOfDay(yearStart), end: todayEnd);
      case QuickDatePreset.custom:
        return DateTimeRange(start: todayStart, end: todayEnd);
    }
  }

  /// Computes the comparable previous period of equal duration immediately before [start].
  /// If [start]..[end] is an exact full calendar month, returns the full previous calendar month.
  static DateTimeRange previousComparableRange(DateTime start, DateTime end) {
    final s = _startOfDay(start);
    final e = _startOfDay(end);

    // Full calendar month special case
    final lastDayOfStartMonth = DateTime(s.year, s.month + 1, 0).day;
    if (s.year == e.year &&
        s.month == e.month &&
        s.day == 1 &&
        e.day == lastDayOfStartMonth) {
      final prevStart = DateTime(s.year, s.month - 1, 1);
      final prevEnd = DateTime(s.year, s.month, 0);
      return DateTimeRange(start: _startOfDay(prevStart), end: _endOfDay(prevEnd));
    }

    final daysCount = e.difference(s).inDays + 1;
    final effectiveDays = daysCount < 1 ? 1 : daysCount;
    final prevEndDay = s.subtract(const Duration(days: 1));
    final prevStartDay = prevEndDay.subtract(Duration(days: effectiveDays - 1));
    return DateTimeRange(
      start: _startOfDay(prevStartDay),
      end: _endOfDay(prevEndDay),
    );
  }
}

