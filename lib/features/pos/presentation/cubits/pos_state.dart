import 'package:equatable/equatable.dart';
import '../../domain/entities/cart_item_entity.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';

enum PosStatus { initial, loading, success, error, checkoutLoading }

class PosState extends Equatable {
  final List<CartItemEntity> cartItems;
  final List<VariantEntity> searchResults;
  final String paymentMethod;
  final PosStatus status;
  final String? errorMessage;

  const PosState({
    this.cartItems = const [],
    this.searchResults = const [],
    this.paymentMethod = 'cash',
    this.status = PosStatus.initial,
    this.errorMessage,
  });

  double get totalAmount => cartItems.fold(0, (sum, item) => sum + item.totalPrice);

  PosState copyWith({
    List<CartItemEntity>? cartItems,
    List<VariantEntity>? searchResults,
    String? paymentMethod,
    PosStatus? status,
    String? errorMessage,
  }) {
    return PosState(
      cartItems: cartItems ?? this.cartItems,
      searchResults: searchResults ?? this.searchResults,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [cartItems, searchResults, paymentMethod, status, errorMessage];
}
