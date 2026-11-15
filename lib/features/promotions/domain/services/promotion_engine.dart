import 'dart:math';

import '../../../pos/domain/entities/sale_item_entity.dart';
import '../entities/promotion.dart';

class PromotionEngine {
  PromotionEngine._();

  /// Evaluates and applies promotions to a cart of [SaleItemEntity].
  ///
  /// [cart]: List of items in cart.
  /// [activePromotions]: Candidate promotions to evaluate.
  /// [customerDiscountPercent]: Optional customer discount percentage (e.g., 10 for 10%).
  /// [now]: Injected reference date/time for time window evaluation (defaults to DateTime.now()).
  /// [categoryDescendants]: Optional map of categoryId -> set of descendant category IDs (including self or subcategories).
  static PromotionEvaluationResult apply({
    required List<SaleItemEntity> cart,
    required List<Promotion> activePromotions,
    int? customerDiscountPercent,
    DateTime? now,
    Map<String, Set<String>>? categoryDescendants,
  }) {
    final evalTime = now ?? DateTime.now();

    // 1. Filter promotions that are active, not deleted, and within time window
    final effectivePromotions = activePromotions
        .where((p) => p.isEffectiveAt(evalTime))
        .toList();

    final lineResults = <LineDiscountResult>[];
    int totalPromotionDiscount = 0;
    int totalCustomerDiscount = 0;

    for (int index = 0; index < cart.length; index++) {
      final line = cart[index];
      final lineSubtotal = line.price * line.quantity;

      // Returns or invalid quantities get zero discount
      if (line.isReturn || lineSubtotal <= 0 || line.quantity <= 0) {
        lineResults.add(LineDiscountResult(
          cartLineIndex: index,
          originalSubtotal: max(0, lineSubtotal),
          discountPiasters: 0,
          finalSubtotal: max(0, lineSubtotal),
          appliedPromotion: null,
          customerDiscountApplied: false,
        ));
        continue;
      }

      // 2. Find all eligible promotions for this line
      final candidates = <_PromoCandidate>[];

      for (final promo in effectivePromotions) {
        if (!_isScopeMatch(promo, line, categoryDescendants)) {
          continue;
        }

        if (line.quantity < promo.minQuantity) {
          continue;
        }

        final discount = _calculatePromoDiscount(promo, line, lineSubtotal);
        if (discount > 0) {
          candidates.add(_PromoCandidate(
            promotion: promo,
            discountPiasters: discount,
          ));
        }
      }

      // 3. Conflict resolution among eligible promotions:
      // Higher priority wins -> Higher discount wins -> id ASC wins (deterministic)
      _PromoCandidate? winningPromoCandidate;
      if (candidates.isNotEmpty) {
        candidates.sort((a, b) {
          final pDiff = b.promotion.priority.compareTo(a.promotion.priority);
          if (pDiff != 0) return pDiff;

          final dDiff = b.discountPiasters.compareTo(a.discountPiasters);
          if (dDiff != 0) return dDiff;

          return a.promotion.id.compareTo(b.promotion.id);
        });
        winningPromoCandidate = candidates.first;
      }

      // 4. Calculate customer discount for this line
      final custPercent = customerDiscountPercent ?? 0;
      int customerDiscountPiasters = 0;
      if (custPercent > 0) {
        final custBp = custPercent * 100;
        final rawCustDiscount = (lineSubtotal * custBp) ~/ 10000;
        customerDiscountPiasters = min(rawCustDiscount, lineSubtotal);
      }

      // 5. Best-of comparison: max(promotion, customer_discount).
      // Tie-breaker: customer discount wins on tie (no promotion application recorded).
      final winningPromoDiscount = winningPromoCandidate?.discountPiasters ?? 0;

      if (winningPromoDiscount > customerDiscountPiasters) {
        // Promotion wins strictly
        final finalDiscount = min(winningPromoDiscount, lineSubtotal);
        final finalSub = max(0, lineSubtotal - finalDiscount);

        lineResults.add(LineDiscountResult(
          cartLineIndex: index,
          originalSubtotal: lineSubtotal,
          discountPiasters: finalDiscount,
          finalSubtotal: finalSub,
          appliedPromotion: winningPromoCandidate!.promotion,
          customerDiscountApplied: false,
        ));
        totalPromotionDiscount += finalDiscount;
      } else if (customerDiscountPiasters > 0) {
        // Customer discount wins (or ties promotion)
        final finalDiscount = min(customerDiscountPiasters, lineSubtotal);
        final finalSub = max(0, lineSubtotal - finalDiscount);

        lineResults.add(LineDiscountResult(
          cartLineIndex: index,
          originalSubtotal: lineSubtotal,
          discountPiasters: finalDiscount,
          finalSubtotal: finalSub,
          appliedPromotion: null,
          customerDiscountApplied: true,
        ));
        totalCustomerDiscount += finalDiscount;
      } else {
        // Neither applies
        lineResults.add(LineDiscountResult(
          cartLineIndex: index,
          originalSubtotal: lineSubtotal,
          discountPiasters: 0,
          finalSubtotal: lineSubtotal,
          appliedPromotion: null,
          customerDiscountApplied: false,
        ));
      }
    }

    return PromotionEvaluationResult(
      lineResults: lineResults,
      totalPromotionDiscountPiasters: totalPromotionDiscount,
      totalCustomerDiscountPiasters: totalCustomerDiscount,
      totalDiscountPiasters: totalPromotionDiscount + totalCustomerDiscount,
    );
  }

  static bool _isScopeMatch(
    Promotion promo,
    SaleItemEntity item,
    Map<String, Set<String>>? categoryDescendants,
  ) {
    switch (promo.scope) {
      case 'all':
        return true;

      case 'product':
        // Correction 9: targetId guard
        if (promo.targetId == null || promo.targetId!.isEmpty) {
          return false;
        }
        return item.productId == promo.targetId ||
            item.variantId == promo.targetId;

      case 'category':
        // Correction 9: targetId guard
        if (promo.targetId == null || promo.targetId!.isEmpty) {
          return false;
        }
        if (item.categoryId == null) {
          return false;
        }
        if (item.categoryId == promo.targetId) {
          return true;
        }
        if (categoryDescendants != null) {
          final descendants = categoryDescendants[promo.targetId];
          if (descendants != null && descendants.contains(item.categoryId)) {
            return true;
          }
        }
        return false;

      default:
        return false;
    }
  }

  static int _calculatePromoDiscount(
    Promotion promo,
    SaleItemEntity item,
    int lineSubtotal,
  ) {
    int discount = 0;
    if (promo.type == 'percent') {
      final bp = promo.valueBp ?? 0;
      if (bp > 0) {
        discount = (lineSubtotal * bp) ~/ 10000;
      }
    } else if (promo.type == 'fixed') {
      final perPiece = promo.valuePiasters ?? 0;
      if (perPiece > 0) {
        discount = perPiece * item.quantity;
      }
    }

    // Ensure discount is non-negative and capped at lineSubtotal (100% cap safeguard)
    return max(0, min(discount, lineSubtotal));
  }
}

class _PromoCandidate {
  final Promotion promotion;
  final int discountPiasters;

  const _PromoCandidate({
    required this.promotion,
    required this.discountPiasters,
  });
}
