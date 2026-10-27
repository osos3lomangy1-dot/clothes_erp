import 'package:equatable/equatable.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';

class CartItemEntity extends Equatable {
  final VariantEntity variant;
  final int quantity;

  const CartItemEntity({
    required this.variant,
    required this.quantity,
  });

  int get totalPrice => variant.salePrice * quantity;

  CartItemEntity copyWith({int? quantity}) {
    return CartItemEntity(
      variant: variant,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  List<Object?> get props => [variant, quantity];
}
