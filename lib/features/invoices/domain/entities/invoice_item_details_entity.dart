import 'package:equatable/equatable.dart';

class InvoiceItemDetailsEntity extends Equatable {
  final String id;
  final String variantId;
  final String productName;
  final String color;
  final String size;
  final int qty;
  final double? decimalQty;
  final String? unit;
  final int price; // in piasters
  final int costPrice; // in piasters (cost snapshot)
  final int lineDiscount; // in piasters
  final int promotionDiscount; // in piasters
  final int lineTotal; // in piasters
  final String? kitchenNotes;
  final List<String> modifiers;
  final String? warrantyPeriod;
  final String? brandOrModel;
  final String? imei;
  final String? deviceCondition;

  const InvoiceItemDetailsEntity({
    required this.id,
    required this.variantId,
    required this.productName,
    required this.color,
    required this.size,
    required this.qty,
    this.decimalQty,
    this.unit,
    required this.price,
    this.costPrice = 0,
    this.lineDiscount = 0,
    this.promotionDiscount = 0,
    required this.lineTotal,
    this.kitchenNotes,
    this.modifiers = const [],
    this.warrantyPeriod,
    this.brandOrModel,
    this.imei,
    this.deviceCondition,
  });

  InvoiceItemDetailsEntity copyWith({
    String? id,
    String? variantId,
    String? productName,
    String? color,
    String? size,
    int? qty,
    double? decimalQty,
    String? unit,
    int? price,
    int? costPrice,
    int? lineDiscount,
    int? promotionDiscount,
    int? lineTotal,
    String? kitchenNotes,
    List<String>? modifiers,
    String? warrantyPeriod,
    String? brandOrModel,
    String? imei,
    String? deviceCondition,
  }) {
    return InvoiceItemDetailsEntity(
      id: id ?? this.id,
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      color: color ?? this.color,
      size: size ?? this.size,
      qty: qty ?? this.qty,
      decimalQty: decimalQty ?? this.decimalQty,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      lineDiscount: lineDiscount ?? this.lineDiscount,
      promotionDiscount: promotionDiscount ?? this.promotionDiscount,
      lineTotal: lineTotal ?? this.lineTotal,
      kitchenNotes: kitchenNotes ?? this.kitchenNotes,
      modifiers: modifiers ?? this.modifiers,
      warrantyPeriod: warrantyPeriod ?? this.warrantyPeriod,
      brandOrModel: brandOrModel ?? this.brandOrModel,
      imei: imei ?? this.imei,
      deviceCondition: deviceCondition ?? this.deviceCondition,
    );
  }

  /// Effective quantity: returns decimalQty if available and positive, else qty as double
  double get effectiveQuantity =>
      (decimalQty != null && decimalQty! > 0) ? decimalQty! : qty.toDouble();

  /// Formatted quantity representation
  String get formattedQuantity => (effectiveQuantity % 1 == 0)
      ? effectiveQuantity.toInt().toString()
      : effectiveQuantity.toString();

  /// Net line profit in piasters: lineTotal - (costPrice * effectiveQuantity).round()
  int get profitPiasters =>
      lineTotal - (costPrice * effectiveQuantity).round();

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
        decimalQty,
        unit,
        price,
        costPrice,
        lineDiscount,
        promotionDiscount,
        lineTotal,
        kitchenNotes,
        modifiers,
        warrantyPeriod,
        brandOrModel,
      ];
}

