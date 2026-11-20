import 'package:equatable/equatable.dart';

class ReorderSuggestionEntity extends Equatable {
  final String variantId;
  final String productId;
  final String productName;
  final String sku;
  final String categoryName;
  final String color;
  final String size;
  final int currentStock;
  final int minStock;
  final int soldLast30Days;
  final double dailySalesRate;
  final int suggestedReorderQty;
  final int costPricePiasters;
  final int totalEstimatedCostPiasters;

  const ReorderSuggestionEntity({
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.categoryName,
    required this.color,
    required this.size,
    required this.currentStock,
    required this.minStock,
    required this.soldLast30Days,
    required this.dailySalesRate,
    required this.suggestedReorderQty,
    required this.costPricePiasters,
    required this.totalEstimatedCostPiasters,
  });

  @override
  List<Object?> get props => [
        variantId,
        productId,
        productName,
        sku,
        categoryName,
        color,
        size,
        currentStock,
        minStock,
        soldLast30Days,
        dailySalesRate,
        suggestedReorderQty,
        costPricePiasters,
        totalEstimatedCostPiasters,
      ];
}

class DeadStockItemEntity extends Equatable {
  final String variantId;
  final String productId;
  final String productName;
  final String sku;
  final String categoryName;
  final String color;
  final String size;
  final int currentStock;
  final int costPricePiasters;
  final int sellPricePiasters;
  final int frozenCapitalPiasters;
  final int lostRevenuePotentialPiasters;
  final DateTime? lastSoldDate;
  final int daysWithoutSale;

  const DeadStockItemEntity({
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.categoryName,
    required this.color,
    required this.size,
    required this.currentStock,
    required this.costPricePiasters,
    required this.sellPricePiasters,
    required this.frozenCapitalPiasters,
    required this.lostRevenuePotentialPiasters,
    this.lastSoldDate,
    required this.daysWithoutSale,
  });

  @override
  List<Object?> get props => [
        variantId,
        productId,
        productName,
        sku,
        categoryName,
        color,
        size,
        currentStock,
        costPricePiasters,
        sellPricePiasters,
        frozenCapitalPiasters,
        lostRevenuePotentialPiasters,
        lastSoldDate,
        daysWithoutSale,
      ];
}

class StockMovementCardItemEntity extends Equatable {
  final String logId;
  final DateTime date;
  final String type;
  final String typeLabel;
  final int qtyDelta;
  final int runningBalance;
  final String? refType;
  final String? refId;
  final String? reason;
  final String userName;

  const StockMovementCardItemEntity({
    required this.logId,
    required this.date,
    required this.type,
    required this.typeLabel,
    required this.qtyDelta,
    required this.runningBalance,
    this.refType,
    this.refId,
    this.reason,
    required this.userName,
  });

  @override
  List<Object?> get props => [
        logId,
        date,
        type,
        typeLabel,
        qtyDelta,
        runningBalance,
        refType,
        refId,
        reason,
        userName,
      ];
}

