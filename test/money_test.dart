import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/utils/money.dart';

void main() {
  group('Money', () {
    test('fromString parses whole number', () {
      expect(Money.fromString('100').piasters, 10000);
    });

    test('fromString parses decimal', () {
      expect(Money.fromString('10.50').piasters, 1050);
    });

    test('fromString handles missing cents', () {
      expect(Money.fromString('10.5').piasters, 1050);
    });

    test('toDisplay formats correctly', () {
      expect(const Money(1050).toDisplay(), '10.50');
    });

    test('percentDiscount uses integer math', () {
      final total = const Money(10000); // 100.00
      final discount = Money.percentDiscount(total, 10); // 10%
      expect(discount.piasters, 1000); // 10.00
    });

    test('percentDiscount rounds down', () {
      final total = const Money(10001); // 100.01
      final discount = Money.percentDiscount(total, 33); // 33%
      expect(discount.piasters, 3300); // 33.00 (3300.33 -> 3300)
    });

    test('fixedDiscount caps at total', () {
      final total = const Money(1000);
      final discount = Money.fixedDiscount(total, const Money(2000));
      expect(discount.piasters, 1000);
    });

    test('addition works', () {
      expect((const Money(100) + const Money(200)).piasters, 300);
    });

    test('subtraction works', () {
      expect((const Money(500) - const Money(200)).piasters, 300);
    });

    test('multiplication works', () {
      expect((const Money(100) * 3).piasters, 300);
    });

    test('fromString handles empty string', () {
      expect(Money.fromString('').piasters, 0);
    });

    test('fromString handles negative amount', () {
      expect(Money.fromString('-10.50').piasters, -1050);
    });


  });
}


