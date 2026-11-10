import 'package:equatable/equatable.dart';

class InvoiceItemDetailsEntity extends Equatable {
  final String id;
  final String variantId;
  final String productName;
  final String color;
  final String size;
  final int qty;
  final int price; // in piasters
  final int lineDiscount; // in piasters
  final int lineTotal; // in piasters

  const InvoiceItemDetailsEntity({
    required this.id,
    required this.variantId,
    required this.productName,
    required this.color,
    required this.size,
    required this.qty,
    required this.price,
    this.lineDiscount = 0,
    required this.lineTotal,
  });

  @override
  List<Object?> get props => [
        id,
        variantId,
        productName,
        color,
        size,
        qty,
        price,
        lineDiscount,
        lineTotal,
      ];
}

