import 'package:equatable/equatable.dart';

class Promotion extends Equatable {
  final String id;
  final String branchId;
  final String name;
  final String? description;
  final String type; // 'percent' | 'fixed'
  final String scope; // 'product' | 'category' | 'all'
  final List<String> targetIds; // NEW: list of product OR category IDs
  final String? targetId; // DEPRECATED: kept for backward compat
  final int? valueBp; // basis points (1000 = 10%)
  final int? valuePiasters; // fixed discount per piece in piasters
  final int minQuantity;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;
  final int priority;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Promotion({
    required this.id,
    required this.branchId,
    required this.name,
    this.description,
    required this.type,
    required this.scope,
    this.targetIds = const [],
    this.targetId,
    this.valueBp,
    this.valuePiasters,
    this.minQuantity = 1,
    required this.startsAt,
    required this.endsAt,
    this.isActive = true,
    this.priority = 0,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  bool isEffectiveAt(DateTime time) {
    if (!isActive || deletedAt != null) return false;
    return (time.isAfter(startsAt) || time.isAtSameMomentAs(startsAt)) &&
        (time.isBefore(endsAt) || time.isAtSameMomentAs(endsAt));
  }

  bool appliesToProduct(String variantId) =>
      scope == 'product' &&
      (targetIds.contains(variantId) || targetId == variantId);

  bool appliesToCategory(String categoryId) =>
      scope == 'category' &&
      (targetIds.contains(categoryId) || targetId == categoryId);

  Promotion copyWith({
    String? id,
    String? branchId,
    String? name,
    String? description,
    String? type,
    String? scope,
    List<String>? targetIds,
    String? targetId,
    int? valueBp,
    int? valuePiasters,
    int? minQuantity,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? isActive,
    int? priority,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Promotion(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      scope: scope ?? this.scope,
      targetIds: targetIds ?? this.targetIds,
      targetId: targetId ?? this.targetId,
      valueBp: valueBp ?? this.valueBp,
      valuePiasters: valuePiasters ?? this.valuePiasters,
      minQuantity: minQuantity ?? this.minQuantity,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      isActive: isActive ?? this.isActive,
      priority: priority ?? this.priority,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        name,
        description,
        type,
        scope,
        targetIds,
        targetId,
        valueBp,
        valuePiasters,
        minQuantity,
        startsAt,
        endsAt,
        isActive,
        priority,
        createdBy,
        createdAt,
        updatedAt,
        deletedAt,
      ];
}

class AppliedPromotion extends Equatable {
  final String id;
  final String branchId;
  final String promotionId;
  final String promotionName;
  final String saleId;
  final String saleItemId;
  final int cartLineIndex;
  final int discountPiasters;
  final DateTime createdAt;
  final DateTime? deletedAt;

  const AppliedPromotion({
    required this.id,
    required this.branchId,
    required this.promotionId,
    required this.promotionName,
    required this.saleId,
    required this.saleItemId,
    required this.cartLineIndex,
    required this.discountPiasters,
    required this.createdAt,
    this.deletedAt,
  });

  AppliedPromotion copyWith({
    String? id,
    String? branchId,
    String? promotionId,
    String? promotionName,
    String? saleId,
    String? saleItemId,
    int? cartLineIndex,
    int? discountPiasters,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) {
    return AppliedPromotion(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      promotionId: promotionId ?? this.promotionId,
      promotionName: promotionName ?? this.promotionName,
      saleId: saleId ?? this.saleId,
      saleItemId: saleItemId ?? this.saleItemId,
      cartLineIndex: cartLineIndex ?? this.cartLineIndex,
      discountPiasters: discountPiasters ?? this.discountPiasters,
      createdAt: createdAt ?? this.createdAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        promotionId,
        promotionName,
        saleId,
        saleItemId,
        cartLineIndex,
        discountPiasters,
        createdAt,
        deletedAt,
      ];
}

class LineDiscountResult extends Equatable {
  final int cartLineIndex;
  final int originalSubtotal;
  final int discountPiasters;
  final int finalSubtotal;
  final Promotion? appliedPromotion;
  final bool customerDiscountApplied;

  const LineDiscountResult({
    required this.cartLineIndex,
    required this.originalSubtotal,
    required this.discountPiasters,
    required this.finalSubtotal,
    this.appliedPromotion,
    this.customerDiscountApplied = false,
  });

  bool get hasPromotion => appliedPromotion != null;
  int get promotionDiscountPiasters => hasPromotion ? discountPiasters : 0;
  int get customerDiscountPiasters => customerDiscountApplied ? discountPiasters : 0;
  int get appliedDiscountPiasters => discountPiasters;

  @override
  List<Object?> get props => [
        cartLineIndex,
        originalSubtotal,
        discountPiasters,
        finalSubtotal,
        appliedPromotion,
        customerDiscountApplied,
      ];
}

class PromotionEvaluationResult extends Equatable {
  final List<LineDiscountResult> lineResults;
  final int totalPromotionDiscountPiasters;
  final int totalCustomerDiscountPiasters;
  final int totalDiscountPiasters;

  const PromotionEvaluationResult({
    required this.lineResults,
    required this.totalPromotionDiscountPiasters,
    required this.totalCustomerDiscountPiasters,
    required this.totalDiscountPiasters,
  });

  List<LineDiscountResult> get lines => lineResults;
  int get totalPromotionDiscount => totalPromotionDiscountPiasters;
  int get totalCustomerDiscount => totalCustomerDiscountPiasters;
  int get totalApplied => totalDiscountPiasters;

  @override
  List<Object?> get props => [
        lineResults,
        totalPromotionDiscountPiasters,
        totalCustomerDiscountPiasters,
        totalDiscountPiasters,
      ];
}

typedef PromotionEntity = Promotion;
typedef AppliedPromotionEntity = AppliedPromotion;
