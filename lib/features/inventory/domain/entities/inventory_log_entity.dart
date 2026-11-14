import 'package:equatable/equatable.dart';

class InventoryLogEntity extends Equatable {
  final String id;
  final String productId;
  final String? variantId;
  final String? productName;
  final String? variantSize;
  final String? variantColor;
  final String? userName;
  final String type; // 'in', 'out', 'receive', 'sale', 'return', 'adjustment'
  final int quantity;
  final DateTime date;
  final String userId;

  const InventoryLogEntity({
    required this.id,
    required this.productId,
    this.variantId,
    this.productName,
    this.variantSize,
    this.variantColor,
    this.userName,
    required this.type,
    required this.quantity,
    required this.date,
    required this.userId,
  });

  @override
  List<Object?> get props => [
        id,
        productId,
        variantId,
        productName,
        variantSize,
        variantColor,
        userName,
        type,
        quantity,
        date,
        userId,
      ];
}
