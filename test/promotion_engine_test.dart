import 'package:clothes_erp/features/pos/domain/entities/sale_item_entity.dart';
import 'package:clothes_erp/features/promotions/domain/entities/promotion.dart';
import 'package:clothes_erp/features/promotions/domain/services/promotion_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final baseTime = DateTime(2026, 11, 15, 12, 0);

  Promotion createPromo({
    String id = 'promo-1',
    String branchId = 'b1',
    String name = 'Test Promo',
    String type = 'percent',
    String scope = 'all',
    String? targetId,
    int? valueBp,
    int? valuePiasters,
    int minQuantity = 1,
    DateTime? startsAt,
    DateTime? endsAt,
    bool isActive = true,
    int priority = 0,
    DateTime? deletedAt,
  }) {
    return Promotion(
      id: id,
      branchId: branchId,
      name: name,
      type: type,
      scope: scope,
      targetId: targetId,
      valueBp: valueBp,
      valuePiasters: valuePiasters,
      minQuantity: minQuantity,
      startsAt: startsAt ?? baseTime.subtract(const Duration(days: 1)),
      endsAt: endsAt ?? baseTime.add(const Duration(days: 1)),
      isActive: isActive,
      priority: priority,
      createdBy: 'admin',
      createdAt: baseTime.subtract(const Duration(days: 2)),
      updatedAt: baseTime.subtract(const Duration(days: 2)),
      deletedAt: deletedAt,
    );
  }

  SaleItemEntity createItem({
    String variantId = 'v1',
    String? productId = 'p1',
    String? categoryId = 'c1',
    String productName = 'Product 1',
    int price = 10000, // 100.00 EGP
    int quantity = 1,
    bool isReturn = false,
  }) {
    return SaleItemEntity(
      variantId: variantId,
      productId: productId,
      categoryId: categoryId,
      productName: productName,
      size: 'M',
      color: 'Blue',
      price: price,
      quantity: quantity,
      isReturn: isReturn,
    );
  }

  group('PromotionEngine — Core Calculation Scenarios', () {
    test('1. Type percent, minQuantity=1: 1000 bp (10%) on 10,000 = 1,000 piasters', () {
      final promo = createPromo(
        type: 'percent',
        valueBp: 1000,
        minQuantity: 1,
      );
      final item = createItem(price: 10000, quantity: 1);

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      expect(result.lineResults.length, 1);
      final line = result.lineResults[0];
      expect(line.discountPiasters, 1000);
      expect(line.finalSubtotal, 9000);
      expect(line.hasPromotion, isTrue);
      expect(line.appliedPromotion?.id, 'promo-1');
      expect(result.totalPromotionDiscountPiasters, 1000);
      expect(result.totalDiscountPiasters, 1000);
    });

    test('2. Type fixed, minQuantity=1: 500 piasters on 10,000 (qty 1) = 500 piasters', () {
      final promo = createPromo(
        type: 'fixed',
        valuePiasters: 500,
        minQuantity: 1,
      );
      final item = createItem(price: 10000, quantity: 1);

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      final line = result.lineResults[0];
      expect(line.discountPiasters, 500);
      expect(line.finalSubtotal, 9500);
      expect(line.hasPromotion, isTrue);
    });

    test('3. Type fixed, minQuantity=1: 500 piasters on 100 piasters -> capped at 100', () {
      final promo = createPromo(
        type: 'fixed',
        valuePiasters: 500,
        minQuantity: 1,
      );
      final item = createItem(price: 100, quantity: 1);

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      final line = result.lineResults[0];
      expect(line.discountPiasters, 100);
      expect(line.finalSubtotal, 0);
      expect(line.finalSubtotal >= 0, isTrue);
    });

    test('4. Type percent, minQuantity=3: qty=2 -> 0 (minQuantity not met)', () {
      final promo = createPromo(
        type: 'percent',
        valueBp: 2000,
        minQuantity: 3,
      );
      final item = createItem(price: 1000, quantity: 2);

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      final line = result.lineResults[0];
      expect(line.discountPiasters, 0);
      expect(line.finalSubtotal, 2000);
      expect(line.hasPromotion, isFalse);
    });

    test('5. Type percent, minQuantity=3: qty=3 -> discount on full line', () {
      final promo = createPromo(
        type: 'percent',
        valueBp: 2000, // 20%
        minQuantity: 3,
      );
      final item = createItem(price: 1000, quantity: 3); // lineSubtotal = 3000

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      final line = result.lineResults[0];
      // 20% of 3000 = 600
      expect(line.discountPiasters, 600);
      expect(line.finalSubtotal, 2400);
      expect(line.hasPromotion, isTrue);
    });

    test('6. Type percent, minQuantity=3: qty=4 -> discount on full line', () {
      final promo = createPromo(
        type: 'percent',
        valueBp: 2000, // 20%
        minQuantity: 3,
      );
      final item = createItem(price: 1000, quantity: 4); // lineSubtotal = 4000

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      final line = result.lineResults[0];
      // 20% of 4000 = 800
      expect(line.discountPiasters, 800);
      expect(line.finalSubtotal, 3200);
    });

    test('7. Type percent, minQuantity=3: qty=6 -> discount on full line', () {
      final promo = createPromo(
        type: 'percent',
        valueBp: 2000, // 20%
        minQuantity: 3,
      );
      final item = createItem(price: 1000, quantity: 6); // lineSubtotal = 6000

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      final line = result.lineResults[0];
      // 20% of 6000 = 1200
      expect(line.discountPiasters, 1200);
      expect(line.finalSubtotal, 4800);
    });

    test('8. Type fixed, minQuantity=3: qty=3 -> value * 3 discount', () {
      final promo = createPromo(
        type: 'fixed',
        valuePiasters: 200,
        minQuantity: 3,
      );
      final item = createItem(price: 1000, quantity: 3); // lineSubtotal = 3000

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      final line = result.lineResults[0];
      // 200 * 3 = 600
      expect(line.discountPiasters, 600);
      expect(line.finalSubtotal, 2400);
    });

    test('9. Expired promotion -> not applied', () {
      final promo = createPromo(
        type: 'percent',
        valueBp: 2000,
        startsAt: baseTime.subtract(const Duration(days: 5)),
        endsAt: baseTime.subtract(const Duration(days: 1)),
      );
      final item = createItem();

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      expect(result.lineResults[0].discountPiasters, 0);
      expect(result.lineResults[0].hasPromotion, isFalse);
    });

    test('10. Not-yet-started promotion -> not applied', () {
      final promo = createPromo(
        type: 'percent',
        valueBp: 2000,
        startsAt: baseTime.add(const Duration(days: 1)),
        endsAt: baseTime.add(const Duration(days: 5)),
      );
      final item = createItem();

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      expect(result.lineResults[0].discountPiasters, 0);
      expect(result.lineResults[0].hasPromotion, isFalse);
    });

    test('11. Inactive or deleted promotion -> not applied', () {
      final inactivePromo = createPromo(
        id: 'p-inact',
        isActive: false,
        valueBp: 2000,
      );
      final deletedPromo = createPromo(
        id: 'p-del',
        deletedAt: baseTime.subtract(const Duration(hours: 1)),
        valueBp: 2000,
      );
      final item = createItem();

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [inactivePromo, deletedPromo],
        now: baseTime,
      );

      expect(result.lineResults[0].discountPiasters, 0);
      expect(result.lineResults[0].hasPromotion, isFalse);
    });

    test('12. Scope product / category / all matching', () {
      final promoProduct = createPromo(
        id: 'promo-prod',
        scope: 'product',
        targetId: 'prod-target',
        valueBp: 1000,
      );
      final promoCategory = createPromo(
        id: 'promo-cat',
        scope: 'category',
        targetId: 'cat-target',
        valueBp: 1500,
      );
      final promoAll = createPromo(
        id: 'promo-all',
        scope: 'all',
        valueBp: 500,
      );

      final itemProd = createItem(variantId: 'v1', productId: 'prod-target', categoryId: 'other-cat');
      final itemCat = createItem(variantId: 'v2', productId: 'other-prod', categoryId: 'cat-target');
      final itemNone = createItem(variantId: 'v3', productId: 'other-prod', categoryId: 'other-cat');

      final result = PromotionEngine.apply(
        cart: [itemProd, itemCat, itemNone],
        activePromotions: [promoProduct, promoCategory, promoAll],
        now: baseTime,
      );

      expect(result.lineResults[0].appliedPromotion?.id, 'promo-prod');
      expect(result.lineResults[1].appliedPromotion?.id, 'promo-cat');
      expect(result.lineResults[2].appliedPromotion?.id, 'promo-all');
    });

    test('13. Category hierarchy with subcategories via categoryDescendants', () {
      final promo = createPromo(
        scope: 'category',
        targetId: 'parent-cat',
        valueBp: 1000,
      );
      final itemSub = createItem(categoryId: 'child-cat');

      final result = PromotionEngine.apply(
        cart: [itemSub],
        activePromotions: [promo],
        now: baseTime,
        categoryDescendants: {
          'parent-cat': {'parent-cat', 'child-cat', 'grandchild-cat'},
        },
      );

      expect(result.lineResults[0].hasPromotion, isTrue);
      expect(result.lineResults[0].appliedPromotion?.id, 'promo-1');
    });

    test('14. Conflict resolution: higher priority wins', () {
      final lowPriorityHighDiscount = createPromo(
        id: 'p-low',
        priority: 1,
        valueBp: 3000, // 30%
      );
      final highPriorityLowDiscount = createPromo(
        id: 'p-high',
        priority: 10,
        valueBp: 1000, // 10%
      );
      final item = createItem(price: 10000);

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [lowPriorityHighDiscount, highPriorityLowDiscount],
        now: baseTime,
      );

      expect(result.lineResults[0].appliedPromotion?.id, 'p-high');
      expect(result.lineResults[0].discountPiasters, 1000);
    });

    test('15. Conflict resolution: same priority -> higher discount wins', () {
      final promo20 = createPromo(
        id: 'p-20',
        priority: 5,
        valueBp: 2000,
      );
      final promo30 = createPromo(
        id: 'p-30',
        priority: 5,
        valueBp: 3000,
      );
      final item = createItem(price: 10000);

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo20, promo30],
        now: baseTime,
      );

      expect(result.lineResults[0].appliedPromotion?.id, 'p-30');
      expect(result.lineResults[0].discountPiasters, 3000);
    });

    test('16. Conflict resolution: same priority, same discount -> id ASC wins', () {
      final promoB = createPromo(
        id: 'promo-b',
        priority: 5,
        valueBp: 2000,
      );
      final promoA = createPromo(
        id: 'promo-a',
        priority: 5,
        valueBp: 2000,
      );
      final item = createItem(price: 10000);

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promoB, promoA],
        now: baseTime,
      );

      expect(result.lineResults[0].appliedPromotion?.id, 'promo-a');
    });

    test('17. Best-of: promotion vs customer discount (promotion wins strictly)', () {
      final promo = createPromo(
        valueBp: 2000, // 20%
      );
      final item = createItem(price: 10000);

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        customerDiscountPercent: 10, // 10%
        now: baseTime,
      );

      final line = result.lineResults[0];
      expect(line.discountPiasters, 2000);
      expect(line.hasPromotion, isTrue);
      expect(line.customerDiscountApplied, isFalse);
      expect(result.totalPromotionDiscountPiasters, 2000);
      expect(result.totalCustomerDiscountPiasters, 0);
    });

    test('18. Best-of Tie: customer discount wins on tie, no promotion application record', () {
      final promo = createPromo(
        valueBp: 1000, // 10%
      );
      final item = createItem(price: 10000);

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        customerDiscountPercent: 10, // 10% (TIE)
        now: baseTime,
      );

      final line = result.lineResults[0];
      // Tie breaker: customer discount wins!
      expect(line.discountPiasters, 1000);
      expect(line.hasPromotion, isFalse);
      expect(line.appliedPromotion, isNull);
      expect(line.customerDiscountApplied, isTrue);
      expect(result.totalPromotionDiscountPiasters, 0);
      expect(result.totalCustomerDiscountPiasters, 1000);
    });

    test('19. Discount capped at line subtotal (no negative final price)', () {
      final promo = createPromo(
        type: 'fixed',
        valuePiasters: 15000, // fixed 150.00 EGP
      );
      final item = createItem(price: 10000, quantity: 1); // 100.00 EGP

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      final line = result.lineResults[0];
      expect(line.discountPiasters, 10000);
      expect(line.finalSubtotal, 0);
    });

    test('20. 100% discount: line goes to 0, no negative price (Correction 11)', () {
      final promo = createPromo(
        type: 'percent',
        valueBp: 10000, // 100.00%
      );
      final item = createItem(price: 5432, quantity: 3); // 16296

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      final line = result.lineResults[0];
      expect(line.discountPiasters, 16296);
      expect(line.finalSubtotal, 0);
      expect(line.finalSubtotal >= 0, isTrue);
    });

    test('21. Integer rounding: (100 * 3333) ~/ 10000 = 33', () {
      final promo = createPromo(
        type: 'percent',
        valueBp: 3333, // 33.33%
      );
      final item = createItem(price: 100, quantity: 1);

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      expect(result.lineResults[0].discountPiasters, 33);
      expect(result.lineResults[0].finalSubtotal, 67);
    });

    test('22. Injected now determines active window', () {
      final promo = createPromo(
        startsAt: DateTime(2026, 6, 1),
        endsAt: DateTime(2026, 6, 30),
        valueBp: 1000,
      );
      final item = createItem();

      final inWindow = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: DateTime(2026, 6, 15),
      );
      expect(inWindow.lineResults[0].hasPromotion, isTrue);

      final outWindow = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: DateTime(2026, 7, 1),
      );
      expect(outWindow.lineResults[0].hasPromotion, isFalse);
    });

    test('23. Guard: scope product with targetId=null -> not applied (Correction 9)', () {
      final promo = createPromo(
        scope: 'product',
        targetId: null,
        valueBp: 2000,
      );
      final item = createItem(productId: 'prod-1');

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      expect(result.lineResults[0].hasPromotion, isFalse);
      expect(result.lineResults[0].discountPiasters, 0);
    });

    test('24. Guard: scope category with targetId=null -> not applied (Correction 9)', () {
      final promo = createPromo(
        scope: 'category',
        targetId: null,
        valueBp: 2000,
      );
      final item = createItem(categoryId: 'cat-1');

      final result = PromotionEngine.apply(
        cart: [item],
        activePromotions: [promo],
        now: baseTime,
      );

      expect(result.lineResults[0].hasPromotion, isFalse);
      expect(result.lineResults[0].discountPiasters, 0);
    });

    test('25. cartLineKey = index: duplicate variantIds in cart do not collide (Correction 8)', () {
      final promo = createPromo(
        valueBp: 1000, // 10%
      );
      // Two identical variants added as separate cart lines
      final line0 = createItem(variantId: 'v1', price: 10000, quantity: 1);
      final line1 = createItem(variantId: 'v1', price: 10000, quantity: 2);

      final result = PromotionEngine.apply(
        cart: [line0, line1],
        activePromotions: [promo],
        now: baseTime,
      );

      expect(result.lineResults.length, 2);
      expect(result.lineResults[0].cartLineIndex, 0);
      expect(result.lineResults[0].discountPiasters, 1000);
      expect(result.lineResults[0].finalSubtotal, 9000);

      expect(result.lineResults[1].cartLineIndex, 1);
      expect(result.lineResults[1].discountPiasters, 2000);
      expect(result.lineResults[1].finalSubtotal, 18000);

      expect(result.totalPromotionDiscountPiasters, 3000);
    });

    test('26. Return items do not receive promotions', () {
      final promo = createPromo(valueBp: 1000);
      final returnItem = createItem(isReturn: true, price: 10000, quantity: 1);

      final result = PromotionEngine.apply(
        cart: [returnItem],
        activePromotions: [promo],
        now: baseTime,
      );

      expect(result.lineResults[0].discountPiasters, 0);
      expect(result.lineResults[0].hasPromotion, isFalse);
    });
  });
}

