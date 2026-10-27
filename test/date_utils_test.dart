import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/utils/date_utils.dart';

void main() {
  test('dayKey formats correctly', () {
    final dt = DateTime(2026, 3, 15, 10, 30);
    expect(AppDateUtils.dayKey(dt), '2026-03-15');
  });

  test('sale at 23:59 and 00:01 land on different days', () {
    final late = DateTime(2026, 3, 15, 23, 59);
    final early = DateTime(2026, 3, 16, 0, 1);
    expect(AppDateUtils.dayKey(late), '2026-03-15');
    expect(AppDateUtils.dayKey(early), '2026-03-16');
    expect(AppDateUtils.dayKey(late) != AppDateUtils.dayKey(early), true);
  });

  test('pads single digit month and day', () {
    final dt = DateTime(2026, 1, 5);
    expect(AppDateUtils.dayKey(dt), '2026-01-05');
  });

  test('sale at 23:59 and 00:01 land on different dayKeys', () {
    final late = DateTime(2026, 3, 15, 23, 59);
    final early = DateTime(2026, 3, 16, 0, 1);
    expect(AppDateUtils.dayKey(late), '2026-03-15');
    expect(AppDateUtils.dayKey(early), '2026-03-16');
  });

  test('midnight boundary', () {
    final midnight = DateTime(2026, 3, 16, 0, 0);
    expect(AppDateUtils.dayKey(midnight), '2026-03-16');
  });

  test('sale at 23:30 local uses local day not UTC', () {
    final local = DateTime(2026, 3, 15, 23, 30);
    expect(AppDateUtils.dayKey(local), '2026-03-15');
  });
}

