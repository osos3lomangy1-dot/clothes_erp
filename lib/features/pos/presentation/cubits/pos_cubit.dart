import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/entities/sale_item_entity.dart';
import '../../domain/usecases/create_sale_usecase.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../../product_variants/domain/repositories/variant_repository.dart';

enum PosStatus { initial, loading, success, error, checkoutLoading }

class PosState extends Equatable {
  final List<SaleItemEntity> cart;
  final List<VariantEntity> searchResults;
  final String paymentMethod;
  final PosStatus status;
  final String? errorMessage;
  final double subtotal;
  final double discount;
  final double total;
  final String notes;

  const PosState({
    this.cart = const [],
    this.searchResults = const [],
    this.paymentMethod = 'cash',
    this.status = PosStatus.initial,
    this.errorMessage,
    this.subtotal = 0.0,
    this.discount = 0.0,
    this.total = 0.0,
    this.notes = '',
  });

  PosState copyWith({
    List<SaleItemEntity>? cart,
    List<VariantEntity>? searchResults,
    String? paymentMethod,
    PosStatus? status,
    String? errorMessage,
    double? subtotal,
    double? discount,
    double? total,
    String? notes,
  }) {
    return PosState(
      cart: cart ?? this.cart,
      searchResults: searchResults ?? this.searchResults,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      errorMessage: errorMessage,
      subtotal: subtotal ?? this.subtotal,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [cart, searchResults, paymentMethod, status, errorMessage, subtotal, discount, total, notes];
}

@injectable
class PosCubit extends Cubit<PosState> {
  final CreateSaleUseCase _createSaleUseCase;
  final VariantRepository _variantRepository;

  PosCubit(this._createSaleUseCase, this._variantRepository) : super(const PosState());

  void addToCart(VariantEntity variant) {
    final existingIndex = state.cart.indexWhere((item) => item.variantId == variant.id);
    if (existingIndex >= 0) {
      final existing = state.cart[existingIndex];
      final updated = existing.copyWith(quantity: existing.quantity + 1);
      final newCart = List<SaleItemEntity>.from(state.cart);
      newCart[existingIndex] = updated;
      _updateCart(newCart);
    } else {
      final newItem = SaleItemEntity(
        variantId: variant.id,
        productName: variant.productCode,
        size: variant.size,
        color: variant.color,
        price: variant.salePrice,
        quantity: 1,
      );
      _updateCart([...state.cart, newItem]);
    }
  }

  void removeFromCart(String variantId) {
    final newCart = state.cart.where((item) => item.variantId != variantId).toList();
    _updateCart(newCart);
  }

  void updateQuantity(String variantId, int newQty) {
    if (newQty <= 0) {
      removeFromCart(variantId);
      return;
    }
    final newCart = state.cart.map((item) {
      if (item.variantId == variantId) {
        return SaleItemEntity(
          variantId: item.variantId,
          productName: item.productName,
          size: item.size,
          color: item.color,
          price: item.price,
          quantity: newQty,
        );
      }
      return item;
    }).toList();
    _updateCart(newCart);
  }

  void clearCart() {
    emit(const PosState());
  }

  void changePaymentMethod(String method) {
    emit(state.copyWith(paymentMethod: method));
  }

  Future<void> loadVariants() async {
    emit(state.copyWith(status: PosStatus.loading));
    final result = await _variantRepository.getAllVariants();
    result.fold(
      (failure) => emit(state.copyWith(status: PosStatus.error, errorMessage: failure.message)),
      (variants) => emit(state.copyWith(status: PosStatus.initial, searchResults: variants)),
    );
  }

  Future<void> searchVariants(String query) async {
    if (query.trim().isEmpty) {
      await loadVariants();
      return;
    }
    emit(state.copyWith(status: PosStatus.loading));
    final result = await _variantRepository.searchVariants(query);
    result.fold(
      (failure) => emit(state.copyWith(status: PosStatus.error, errorMessage: failure.message)),
      (variants) => emit(state.copyWith(status: PosStatus.initial, searchResults: variants)),
    );
  }

  Future<void> checkout(String cashierId, String cashierName) async {
    if (state.cart.isEmpty) {
      emit(state.copyWith(status: PosStatus.error, errorMessage: 'Cart is empty'));
      return;
    }

    emit(state.copyWith(status: PosStatus.checkoutLoading));

    final subtotal = state.cart.fold(0.0, (sum, item) => sum + item.total);
    final sale = SaleEntity(
      id: '',
      date: DateTime.now(),
      cashierId: cashierId,
      cashierName: cashierName,
      items: state.cart,
      subtotal: subtotal,
      discount: state.discount,
      total: subtotal - state.discount,
      paymentMethod: state.paymentMethod,
    );

    final result = await _createSaleUseCase(sale);
    result.fold(
      (failure) => emit(state.copyWith(status: PosStatus.error, errorMessage: failure.message)),
      (createdSale) {
        emit(state.copyWith(status: PosStatus.success, cart: [], searchResults: []));
        clearCart();
      },
    );
  }

  void applyDiscount(double amount) {
    emit(state.copyWith(
      discount: amount,
      total: state.subtotal - amount,
    ));
  }

  void updateNotes(String notes) {
    emit(state.copyWith(notes: notes));
  }

  void _updateCart(List<SaleItemEntity> newCart) {
    final subtotal = newCart.fold(0.0, (sum, item) => sum + item.total);
    emit(state.copyWith(
      cart: newCart,
      subtotal: subtotal,
      total: subtotal - state.discount,
    ));
  }
}

