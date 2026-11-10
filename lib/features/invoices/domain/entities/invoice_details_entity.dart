import 'package:equatable/equatable.dart';
import 'invoice_item_details_entity.dart';

class InvoiceDetailsEntity extends Equatable {
  final String id;
  final String shortRef;
  final DateTime date;
  final String cashierId;
  final String cashierName;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final int subtotal; // in piasters
  final int discountAmount; // in piasters
  final int total; // in piasters
  final String paymentMethod;
  final String? shiftId;
  final String status;
  final List<InvoiceItemDetailsEntity> items;

  const InvoiceDetailsEntity({
    required this.id,
    required this.shortRef,
    required this.date,
    required this.cashierId,
    this.cashierName = '',
    this.customerId,
    this.customerName,
    this.customerPhone,
    required this.subtotal,
    this.discountAmount = 0,
    required this.total,
    required this.paymentMethod,
    this.shiftId,
    this.status = 'completed',
    required this.items,
  });

  int get totalItemsCount => items.fold<int>(0, (sum, i) => sum + i.qty);

  @override
  List<Object?> get props => [
        id,
        shortRef,
        date,
        cashierId,
        cashierName,
        customerId,
        customerName,
        customerPhone,
        subtotal,
        discountAmount,
        total,
        paymentMethod,
        shiftId,
        status,
        items,
      ];
}

