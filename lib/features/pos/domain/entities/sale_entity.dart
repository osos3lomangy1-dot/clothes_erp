import 'package:equatable/equatable.dart';
import 'payment_split.dart';
import 'sale_item_entity.dart';

class SaleEntity extends Equatable {
  final String id;
  final DateTime date;
  final String cashierId;
  final String cashierName;
  final List<SaleItemEntity> items;
  final int subtotal;
  final int discount;
  final int total;
  final String paymentMethod;
  final String? customerId;
  final String syncStatus;
  final List<PaymentSplit>? splits;

  const SaleEntity({
    required this.id,
    required this.date,
    required this.cashierId,
    this.cashierName = '',
    required this.items,
    this.subtotal = 0,
    this.discount = 0,
    this.total = 0,
    required this.paymentMethod,
    this.customerId,
    this.syncStatus = 'synced',
    this.splits,
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
        splits,
      ];
}
