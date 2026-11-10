import 'package:equatable/equatable.dart';

class TopProductReportEntity extends Equatable {
  final String variantId;
  final String productName;
  final String sku;
  final String color;
  final String size;
  final int quantitySold;
  final int totalRevenue; // in piasters

  const TopProductReportEntity({
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.color,
    required this.size,
    required this.quantitySold,
    required this.totalRevenue,
  });

  @override
  List<Object?> get props => [
        variantId,
        productName,
        sku,
        color,
        size,
        quantitySold,
        totalRevenue,
      ];
}

