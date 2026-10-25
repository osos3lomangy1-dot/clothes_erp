import 'package:equatable/equatable.dart';

class InventoryLogEntity extends Equatable {
  final String id;
  final String productId;
  final String? variantId;
  final String type; // 'in' or 'out'
  final int quantity;
  final DateTime date;
  final String userId;

  const InventoryLogEntity({
    required this.id,
    required this.productId,
    this.variantId,
    required this.type,
    required this.quantity,
    required this.date,
    required this.userId,
  });

  @override
  List<Object?> get props => [id, productId, variantId, type, quantity, date, userId];
}
