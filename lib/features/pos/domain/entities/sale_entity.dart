import 'package:equatable/equatable.dart';
import 'sale_item_entity.dart';

class SaleEntity extends Equatable {
  final String id;
  final List<SaleItemEntity> items;
  final double totalAmount;
  final String paymentMethod;
  final String cashierId;
  final String cashierName;
  final DateTime timestamp;
  final String syncStatus;

  const SaleEntity({
    required this.id,
    required this.items,
    required this.totalAmount,
    required this.paymentMethod,
    required this.cashierId,
    required this.cashierName,
    required this.timestamp,
    this.syncStatus = 'synced',
  });

  @override
  List<Object?> get props => [
        id,
        items,
        totalAmount,
        paymentMethod,
        cashierId,
        cashierName,
        timestamp,
        syncStatus,
      ];
}
