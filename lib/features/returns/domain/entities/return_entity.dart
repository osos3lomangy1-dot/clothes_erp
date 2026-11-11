import 'package:equatable/equatable.dart';
import 'return_item_entity.dart';

class ReturnEntity extends Equatable {
  final String id;
  final String? saleId;
  final String? saleShortRef;
  final String cashierId;
  final String? cashierName;
  final String reason;
  final int refundAmount;
  final String paymentMethod;
  final DateTime date;
  final List<ReturnItemEntity> items;

  const ReturnEntity({
    required this.id,
    this.saleId,
    this.saleShortRef,
    required this.cashierId,
    this.cashierName,
    required this.reason,
    required this.refundAmount,
    this.paymentMethod = 'cash',
    required this.date,
    this.items = const [],
  });

  @override
  List<Object?> get props => [
        id,
        saleId,
        saleShortRef,
        cashierId,
        cashierName,
        reason,
        refundAmount,
        paymentMethod,
        date,
        items,
      ];
}
