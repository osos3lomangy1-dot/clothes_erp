import 'package:equatable/equatable.dart';

class SaleItemEntity extends Equatable {
  final String variantId;
  final String? productId;
  final String? categoryId;
  final String productName;
  final String size;
  final String color;
  final int price;
  final int quantity;
  final double? decimalQuantity;
  final String? unit;
  final int discount;
  final int promotionDiscount;
  final bool isReturn;
  final String? kitchenNotes;
  final List<String> modifiers;

  const SaleItemEntity({
    required this.variantId,
    this.productId,
    this.categoryId,
    required this.productName,
    required this.size,
    required this.color,
    required this.price,
    required this.quantity,
    this.decimalQuantity,
    this.unit,
    this.discount = 0,
    this.promotionDiscount = 0,
    this.isReturn = false,
    this.kitchenNotes,
    this.modifiers = const [],
  });

  double get effectiveQuantity =>
      (decimalQuantity != null && decimalQuantity! > 0)
          ? decimalQuantity!
          : quantity.toDouble();

  String get formattedQuantity => (effectiveQuantity % 1 == 0)
      ? effectiveQuantity.toInt().toString()
      : effectiveQuantity.toString();

  SaleItemEntity copyWith({
    String? variantId,
    String? productId,
    String? categoryId,
    String? productName,
    String? size,
    String? color,
    int? price,
    int? quantity,
    double? decimalQuantity,
    bool clearDecimalQuantity = false,
    String? unit,
    int? discount,
    int? promotionDiscount,
    bool? isReturn,
    String? kitchenNotes,
    bool clearKitchenNotes = false,
    List<String>? modifiers,
  }) {
    return SaleItemEntity(
      variantId: variantId ?? this.variantId,
      productId: productId ?? this.productId,
      categoryId: categoryId ?? this.categoryId,
      productName: productName ?? this.productName,
      size: size ?? this.size,
      color: color ?? this.color,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      decimalQuantity: clearDecimalQuantity
          ? null
          : (decimalQuantity ?? this.decimalQuantity),
      unit: unit ?? this.unit,
      discount: discount ?? this.discount,
      promotionDiscount: promotionDiscount ?? this.promotionDiscount,
      isReturn: isReturn ?? this.isReturn,
      kitchenNotes: clearKitchenNotes
          ? null
          : (kitchenNotes ?? this.kitchenNotes),
      modifiers: modifiers ?? this.modifiers,
    );
  }

  int get total {
    final rawTotal =
        (price * effectiveQuantity).round() - discount - promotionDiscount;
    return isReturn ? -rawTotal : rawTotal;
  }

  @override
  List<Object?> get props => [
        variantId,
        productId,
        categoryId,
        productName,
        size,
        color,
        price,
        quantity,
        decimalQuantity,
        unit,
        discount,
        promotionDiscount,
        isReturn,
        kitchenNotes,
        modifiers,
      ];
}
