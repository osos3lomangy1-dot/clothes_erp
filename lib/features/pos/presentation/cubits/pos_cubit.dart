import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/entities/sale_item_entity.dart';
import '../../domain/usecases/create_sale_usecase.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../../product_variants/domain/repositories/variant_repository.dart';

sealed class PosState {}

class PosInitial extends PosState {}

class PosLoading extends PosState {}

class PosLoaded extends PosState {
  final List<VariantEntity> filteredVariants;
  final List<SaleItemEntity> cart;
  final int subtotal;
  final int total;
  final bool isProcessing;

  PosLoaded({
    this.filteredVariants = const [],
    this.cart = const [],
    this.subtotal = 0,
    this.total = 0,
    this.isProcessing = false,
  });

  PosLoaded copyWith({
    List<VariantEntity>? filteredVariants,
    List<SaleItemEntity>? cart,
    int? subtotal,
    int? total,
    bool? isProcessing,
  }) {
    return PosLoaded(
      filteredVariants: filteredVariants ?? this.filteredVariants,
      cart: cart ?? this.cart,
      subtotal: subtotal ?? this.subtotal,
      total: total ?? this.total,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}

class PosError extends PosState {
  final String message;
  PosError(this.message);
}

@injectable
class PosCubit extends Cubit<PosState> {
  final CreateSaleUseCase _createSaleUseCase;
  final VariantRepository _variantRepository;
  List<VariantEntity> _allVariants = [];

  PosCubit(this._createSaleUseCase, this._variantRepository) : super(PosInitial());

  Future<void> init() async {
    emit(PosLoading());
    final result = await _variantRepository.getAllVariants();
    result.fold(
      (failure) => emit(PosError(failure.message)),
      (variants) {
        _allVariants = variants;
        emit(PosLoaded(filteredVariants: variants));
      },
    );
  }

  void searchProducts(String query) {
    final state = this.state;
    if (state is! PosLoaded) return;
    if (query.trim().isEmpty) {
      emit(state.copyWith(filteredVariants: _allVariants));
      return;
    }
    final q = query.toLowerCase();
    final filtered = _allVariants
        .where((v) => v.productName.toLowerCase().contains(q) || v.sku.toLowerCase().contains(q))
        .toList();
    emit(state.copyWith(filteredVariants: filtered));
  }

  void addToCart(VariantEntity variant) {
    final state = this.state;
    if (state is! PosLoaded) return;
    final existingIndex = state.cart.indexWhere((item) => item.variantId == variant.id);
    List<SaleItemEntity> newCart;
    if (existingIndex >= 0) {
      final existing = state.cart[existingIndex];
      final updated = existing.copyWith(quantity: existing.quantity + 1);
      newCart = List<SaleItemEntity>.from(state.cart);
      newCart[existingIndex] = updated;
    } else {
      final newItem = SaleItemEntity(
        variantId: variant.id,
        productName: variant.productName,
        size: variant.size,
        color: variant.color,
        price: variant.salePrice,
        quantity: 1,
      );
      newCart = [...state.cart, newItem];
    }
    _updateCart(state, newCart);
  }

  void removeFromCart(String variantId) {
    final state = this.state;
    if (state is! PosLoaded) return;
    final newCart = state.cart.where((item) => item.variantId != variantId).toList();
    _updateCart(state, newCart);
  }

  void updateQuantity(String variantId, int newQty) {
    final state = this.state;
    if (state is! PosLoaded) return;
    if (newQty <= 0) {
      removeFromCart(variantId);
      return;
    }
    final newCart = state.cart.map((item) {
      if (item.variantId == variantId) {
        return item.copyWith(quantity: newQty);
      }
      return item;
    }).toList();
    _updateCart(state, newCart);
  }

  void increaseQty(String variantId) {
    final state = this.state;
    if (state is! PosLoaded) return;
    SaleItemEntity? item;
    try {
      item = state.cart.firstWhere((i) => i.variantId == variantId);
    } catch (_) {
      item = null;
    }
    if (item != null) updateQuantity(variantId, item.quantity + 1);
  }

  void decreaseQty(String variantId) {
    final state = this.state;
    if (state is! PosLoaded) return;
    SaleItemEntity? item;
    try {
      item = state.cart.firstWhere((i) => i.variantId == variantId);
    } catch (_) {
      item = null;
    }
    if (item != null) updateQuantity(variantId, item.quantity - 1);
  }

  void updateUnitPrice(String variantId, int newPrice) {
    final state = this.state;
    if (state is! PosLoaded) return;
    final newCart = state.cart.map((item) {
      if (item.variantId == variantId) {
        return item.copyWith(price: newPrice);
      }
      return item;
    }).toList();
    _updateCart(state, newCart);
  }

  void clearCart() {
    final state = this.state;
    if (state is! PosLoaded) return;
    emit(state.copyWith(cart: const [], subtotal: 0, total: 0));
  }

  Future<bool> checkout({String paymentMethod = 'cash'}) async {
    final state = this.state;
    if (state is! PosLoaded) return false;
    if (state.cart.isEmpty) return false;
    emit(state.copyWith(isProcessing: true));
    final sale = SaleEntity(
      id: '',
      date: DateTime.now(),
      cashierId: 'cashier_id_placeholder',
      cashierName: 'Cashier',
      items: state.cart,
      subtotal: state.subtotal.toDouble(),
      discount: 0.0,
      total: state.total.toDouble(),
      paymentMethod: paymentMethod,
    );
    final result = await _createSaleUseCase(sale);
    final success = result.isRight();
    if (success) {
      emit(PosLoaded(filteredVariants: state.filteredVariants, cart: const [], subtotal: 0, total: 0, isProcessing: false));
    } else {
      emit(state.copyWith(isProcessing: false));
    }
    return success;
  }

  void _updateCart(PosLoaded state, List<SaleItemEntity> newCart) {
    final subtotal = newCart.fold(0, (sum, item) => sum + item.total);
    emit(state.copyWith(cart: newCart, subtotal: subtotal, total: subtotal));
  }
}

