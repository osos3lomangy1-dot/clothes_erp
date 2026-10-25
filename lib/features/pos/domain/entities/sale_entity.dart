import 'package:equatable/equatable.dart';
import 'sale_item_entity.dart';

class SaleEntity extends Equatable {
  final String id;
  final DateTime date;
  final String cashierId;
  final String cashierName;
  final List<SaleItemEntity> items;
  final double subtotal;
  final double discount;
  final double total;
  final String paymentMethod;
  final String? customerId;
  final String syncStatus;

  const SaleEntity({
    required this.id,
    required this.date,
    required this.cashierId,
    this.cashierName = '',
    required this.items,
    this.subtotal = 0.0,
    this.discount = 0.0,
    this.total = 0.0,
    required this.paymentMethod,
    this.customerId,
    this.syncStatus = 'synced',
  });

  @override
  List<Object?> get props => [
        id,
        date,
        cashierId,
        cashierName,
        items,
        subtotal,
        discount,
        total,
        paymentMethod,
        customerId,
        syncStatus,
      ];
}
