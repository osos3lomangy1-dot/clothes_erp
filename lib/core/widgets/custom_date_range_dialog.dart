import 'package:flutter/material.dart';

/// Shows a modern, Arabic RTL-native date range picker modal dialog tailored
/// for desktop and mobile ERP screens instead of Flutter's full-screen picker.
Future<DateTimeRange?> showCustomDateRangeDialog({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String title = 'تحديد الفترة الزمنية',
}) {
  return showDialog<DateTimeRange>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _CustomDateRangeDialog(
      firstDate: DateTime(firstDate.year, firstDate.month, firstDate.day),
      lastDate: DateTime(lastDate.year, lastDate.month, lastDate.day),
      initialDateRange: initialDateRange,
      title: title,
    ),
  );
}

class _CustomDateRangeDialog extends StatefulWidget {
  const _CustomDateRangeDialog({
    required this.firstDate,
    required this.lastDate,
    required this.title,
    this.initialDateRange,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialDateRange;
  final String title;

  @override
  State<_CustomDateRangeDialog> createState() => _CustomDateRangeDialogState();
}

class _CustomDateRangeDialogState extends State<_CustomDateRangeDialog> {
  static const _monthsAr = <String>[
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  // Saturday -> Friday order (standard in Egypt / Arab retail)
  static const _weekdaysAr = <String>[
    'سبت',
    'أحد',
    'إثنين',
    'ثلاثاء',
    'أربعاء',
    'خميس',
    'جمعة',
  ];

  late DateTime _displayedMonth;
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDateRange;
    if (initial != null) {
      _start = _dateOnly(initial.start);
      _end = _dateOnly(initial.end);
    } else {
      final today = _clamp(_dateOnly(DateTime.now()));
      _start = today;
      _end = today;
    }
    final anchor = _end ?? _start ?? _clamp(_dateOnly(DateTime.now()));
    _displayedMonth = DateTime(anchor.year, anchor.month);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _clamp(DateTime d) {
    if (d.isBefore(widget.firstDate)) return widget.firstDate;
    if (d.isAfter(widget.lastDate)) return widget.lastDate;
    return d;
  }

  bool _isDisabled(DateTime d) =>
      d.isBefore(widget.firstDate) || d.isAfter(widget.lastDate);

  bool _isSameDay(DateTime? a, DateTime? b) =>
      a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

  void _onDayTapped(DateTime day) {
    if (_isDisabled(day)) return;
    setState(() {
      if (_start == null || (_start != null && _end != null)) {
        _start = day;
        _end = null;
      } else {
        if (day.isBefore(_start!)) {
          _end = _start;
          _start = day;
        } else {
          _end = day;
        }
      }
    });
  }

  void _applyPreset(DateTime start, DateTime end) {
    final clampedStart = _clamp(_dateOnly(start));
    final clampedEnd = _clamp(_dateOnly(end));
    setState(() {
      _start = clampedStart.isAfter(clampedEnd) ? clampedEnd : clampedStart;
      _end = clampedStart.isAfter(clampedEnd) ? clampedStart : clampedEnd;
      _displayedMonth = DateTime(_end!.year, _end!.month);
    });
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_displayedMonth.year, _displayedMonth.month + delta);
    final minMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final maxMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (next.isBefore(minMonth) || next.isAfter(maxMonth)) return;
    setState(() => _displayedMonth = next);
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'اختر التاريخ';
    final day = d.day.toString().padLeft(2, '0');
    final month = _monthsAr[d.month - 1];
    return '$day $month ${d.year}';
  }

  int get _selectedDaysCount {
    if (_start == null) return 0;
    final e = _end ?? _start!;
    return e.difference(_start!).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 680;

    final today = _dateOnly(DateTime.now());
    final presets = <(String, VoidCallback)>[
      ('اليوم', () => _applyPreset(today, today)),
      (
        'أمس',
        () {
          final y = today.subtract(const Duration(days: 1));
          _applyPreset(y, y);
        },
      ),
      ('آخر 7 أيام', () => _applyPreset(today.subtract(const Duration(days: 6)), today)),
      ('آخر 30 يوم', () => _applyPreset(today.subtract(const Duration(days: 29)), today)),
      ('هذا الشهر', () => _applyPreset(DateTime(today.year, today.month, 1), today)),
      (
        'الشهر الماضي',
        () {
          final firstPrev = DateTime(today.year, today.month - 1, 1);
          final lastPrev = DateTime(today.year, today.month, 0);
          _applyPreset(firstPrev, lastPrev);
        },
      ),
      ('من بداية السنة', () => _applyPreset(DateTime(today.year, 1, 1), today)),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: cs.surface,
        elevation: 10,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.6),
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isCompact ? 420 : 620,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.date_range_rounded, color: cs.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'اختر فترة جاهزة أو حدد من التقويم مباشرة',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Selected Range Summary Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.35 : 0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _DatePill(
                          label: 'من تاريخ',
                          value: _formatDate(_start),
                          isActive: _start != null,
                          color: cs.primary,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_back_rounded, size: 18, color: cs.onSurfaceVariant),
                      ),
                      Expanded(
                        child: _DatePill(
                          label: 'إلى تاريخ',
                          value: _formatDate(_end ?? _start),
                          isActive: _end != null,
                          color: cs.primary,
                        ),
                      ),
                      if (_selectedDaysCount > 0) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _selectedDaysCount == 1
                                ? 'يوم واحد'
                                : '$_selectedDaysCount يوم',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Main Content: Presets + Calendar
                if (isCompact) ...[
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: presets.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, idx) {
                        final (label, onTap) = presets[idx];
                        return ActionChip(
                          label: Text(label, style: const TextStyle(fontSize: 12)),
                          onPressed: onTap,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCalendar(context, cs, theme),
                ] else
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 152,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  child: Text(
                                    'فترات سريعة',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                for (final (label, onTap) in presets)
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: onTap,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        label,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: _buildCalendar(context, cs, theme)),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Footer Buttons
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        final t = _clamp(today);
                        setState(() {
                          _start = t;
                          _end = t;
                          _displayedMonth = DateTime(t.year, t.month);
                        });
                      },
                      child: const Text('تاريخ اليوم'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _start == null
                          ? null
                          : () {
                              final range = DateTimeRange(
                                start: _start!,
                                end: _end ?? _start!,
                              );
                              Navigator.of(context).pop(range);
                            },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('تطبيق الفترة'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar(BuildContext context, ColorScheme cs, ThemeData theme) {
    final firstOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    // Dart weekday: Mon=1..Sat=6, Sun=7. For Sat-first grid: Sat->0, Sun->1, Mon->2..Fri->6
    final leadingEmpty = (firstOfMonth.weekday % 7 + 1) % 7;
    final totalCells = leadingEmpty + daysInMonth;
    final rowCount = (totalCells / 7).ceil();
    final today = _dateOnly(DateTime.now());

    final minMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final maxMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    final canPrev = _displayedMonth.isAfter(minMonth);
    final canNext = _displayedMonth.isBefore(maxMonth);

    final years = <int>[
      for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) y,
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month & Year Header
          Row(
            children: [
              IconButton(
                tooltip: 'الشهر السابق',
                onPressed: canPrev ? () => _shiftMonth(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 22),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _monthsAr[_displayedMonth.month - 1],
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _displayedMonth.year,
                        isDense: true,
                        borderRadius: BorderRadius.circular(10),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                        items: years
                            .map(
                              (y) => DropdownMenuItem<int>(
                                value: y,
                                child: Text('$y'),
                              ),
                            )
                            .toList(),
                        onChanged: (y) {
                          if (y == null) return;
                          setState(() {
                            var m = _displayedMonth.month;
                            final candidate = DateTime(y, m);
                            if (candidate.isBefore(minMonth)) m = minMonth.month;
                            if (candidate.isAfter(maxMonth)) m = maxMonth.month;
                            _displayedMonth = DateTime(y, m);
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'الشهر التالي',
                onPressed: canNext ? () => _shiftMonth(1) : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Weekday Headers
          Row(
            children: [
              for (final w in _weekdaysAr)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Days Grid
          for (var r = 0; r < rowCount; r++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: _buildDayCell(
                        r * 7 + c - leadingEmpty + 1,
                        daysInMonth,
                        today,
                        cs,
                        theme,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    int dayNumber,
    int daysInMonth,
    DateTime today,
    ColorScheme cs,
    ThemeData theme,
  ) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 36);
    }
    final date = DateTime(_displayedMonth.year, _displayedMonth.month, dayNumber);
    final disabled = _isDisabled(date);
    final isStart = _isSameDay(date, _start);
    final isEnd = _isSameDay(date, _end ?? _start);
    final effectiveEnd = _end ?? _start;
    final inRange = _start != null &&
        effectiveEnd != null &&
        !date.isBefore(_start!) &&
        !date.isAfter(effectiveEnd);
    final isToday = _isSameDay(date, today);

    final isEndpoint = isStart || isEnd;

    return GestureDetector(
      onTap: disabled ? null : () => _onDayTapped(date),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: inRange && !isEndpoint
              ? cs.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            right: isStart ? const Radius.circular(18) : Radius.zero,
            left: isEnd ? const Radius.circular(18) : Radius.zero,
          ),
        ),
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isEndpoint ? cs.primary : Colors.transparent,
              shape: BoxShape.circle,
              border: isToday && !isEndpoint
                  ? Border.all(color: cs.primary, width: 1.4)
                  : null,
            ),
            child: Center(
              child: Text(
                '$dayNumber',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: disabled
                      ? cs.onSurface.withValues(alpha: 0.28)
                      : isEndpoint
                          ? cs.onPrimary
                          : isToday
                              ? cs.primary
                              : cs.onSurface,
                  fontWeight: isEndpoint || isToday ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({
    required this.label,
    required this.value,
    required this.isActive,
    required this.color,
  });

  final String label;
  final String value;
  final bool isActive;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: isActive ? color : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
