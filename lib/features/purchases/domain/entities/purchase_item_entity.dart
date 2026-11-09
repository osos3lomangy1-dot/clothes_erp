import 'package:equatable/equatable.dart';

class PurchaseItemEntity extends Equatable {
  final String id;
  final String purchaseId;
  final String variantId;
  final String? productName;
  final String? sku;
  final String? color;
  final String? size;
  final int qty;
  final int costPrice; // in piasters
  final int totalCost; // in piasters
  final DateTime createdAt;

  const PurchaseItemEntity({
    required this.id,
    required this.purchaseId,
    required this.variantId,
    this.productName,
    this.sku,
    this.color,
    this.size,
    required this.qty,
    required this.costPrice,
    required this.totalCost,
    required this.createdAt,
  });

  double get costPricePounds => costPrice / 100.0;
  double get totalCostPounds => totalCost / 100.0;
  String get formattedCostPrice => '${costPricePounds.toStringAsFixed(2)} ج.م';
  String get formattedTotalCost => '${totalCostPounds.toStringAsFixed(2)} ج.م';

  @override
  List<Object?> get props => [
        id,
        purchaseId,
        variantId,
        productName,
        sku,
        color,
        size,
        qty,
        costPrice,
        totalCost,
        createdAt,
      ];
}

