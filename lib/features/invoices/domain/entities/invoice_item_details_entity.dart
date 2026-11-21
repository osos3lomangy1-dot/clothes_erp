import 'package:equatable/equatable.dart';

class InvoiceItemDetailsEntity extends Equatable {
  final String id;
  final String variantId;
  final String productName;
  final String color;
  final String size;
  final int qty;
  final int price; // in piasters
  final int costPrice; // in piasters (cost snapshot)
  final int lineDiscount; // in piasters
  final int promotionDiscount; // in piasters
  final int lineTotal; // in piasters

  const InvoiceItemDetailsEntity({
    required this.id,
    required this.variantId,
    required this.productName,
    required this.color,
    required this.size,
    required this.qty,
    required this.price,
    this.costPrice = 0,
    this.lineDiscount = 0,
    this.promotionDiscount = 0,
    required this.lineTotal,
  });

  /// Net line profit in piasters: lineTotal - (costPrice * qty)
  int get profitPiasters => lineTotal - (costPrice * qty);

  /// Profit margin percentage: profit / lineTotal
  double get profitMarginPercent =>
      lineTotal > 0 ? (profitPiasters / lineTotal) * 100 : 0.0;

  @override
  List<Object?> get props => [
        id,
        variantId,
        productName,
        color,
        size,
        qty,
        price,
        costPrice,
        lineDiscount,
        promotionDiscount,
        lineTotal,
      ];
}

