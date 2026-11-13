import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/entities/sale_item_entity.dart';
import '../../domain/usecases/create_sale_usecase.dart';
import '../../domain/repositories/pos_repository.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../../product_variants/domain/repositories/variant_repository.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/domain/repositories/category_repository.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../../customers/domain/entities/customer_entity.dart';

class PosState {
  final List<VariantEntity> filteredVariants;
  final List<CategoryEntity> categories;
  final String selectedCategory;
  final List<SaleItemEntity> cart;
  final CustomerEntity? customer;
  final int subtotal;
  final int total;
  final bool isProcessing;

  const PosState({
    this.filteredVariants = const [],
    this.categories = const [],
    this.selectedCategory = 'All',
    this.cart = const [],
    this.customer,
    this.subtotal = 0,
    this.total = 0,
    this.isProcessing = false,
  });

  PosState copyWith({
    List<VariantEntity>? filteredVariants,
    List<CategoryEntity>? categories,
    String? selectedCategory,
    List<SaleItemEntity>? cart,
    CustomerEntity? customer,
    bool clearCustomer = false,
    int? subtotal,
    int? total,
    bool? isProcessing,
  }) {
    return PosState(
      filteredVariants: filteredVariants ?? this.filteredVariants,
      categories: categories ?? this.categories,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      cart: cart ?? this.cart,
      customer: clearCustomer ? null : (customer ?? this.customer),
      subtotal: subtotal ?? this.subtotal,
      total: total ?? this.total,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}

class PosLoading extends PosState {
  const PosLoading() : super();
}

class PosLoaded extends PosState {
  const PosLoaded({
    super.filteredVariants,
    super.categories,
    super.selectedCategory,
    super.cart,
    super.customer,
    super.subtotal,
    super.total,
    super.isProcessing,
  });
}

class PosError extends PosState {
  final String message;
  const PosError(this.message) : super();
}

@injectable
class PosCubit extends Cubit<PosState> {
  final CreateSaleUseCase _createSaleUseCase;
  final VariantRepository _variantRepository;
  final CategoryRepository _categoryRepository;
  final ProductRepository _productRepository;
  final PosRepository _posRepository;

  List<VariantEntity> _allVariants = [];
  Map<String, String> _productCategoryMap = {};
  Map<String, String> _productNameMap = {};
  Map<String, String> _categoryNameMap = {};
  String _currentSearchQuery = '';
  String _currentSelectedCategoryId = 'All';
  StreamSubscription? _variantsSubscription;

  PosCubit(
    this._createSaleUseCase,
    this._variantRepository,
    this._categoryRepository,
    this._productRepository,
    this._posRepository,
  ) : super(const PosState());

  Future<void> init() async {
    emit(const PosLoading());
    try {
      final categoriesResult = await _categoryRepository.getCategories();
      final productsResult = await _productRepository.getProducts();

      final categories = categoriesResult.getOrElse(() => []);
      final products = productsResult.getOrElse(() => []);
      _productCategoryMap = {for (final p in products) p.id: p.categoryId};
      _productNameMap = {for (final p in products) p.id: p.name};
      _categoryNameMap = {for (final c in categories) c.id: c.name};

      _variantsSubscription?.cancel();
      _variantsSubscription = _variantRepository.watchAllVariants().listen(
        (result) {
          if (isClosed) return;
          result.fold(
            (failure) {
              if (!isClosed) emit(PosError(failure.message));
            },
            (variants) {
              if (isClosed) return;
              _allVariants = variants.map((v) => VariantEntity(
                id: v.id,
                productId: v.productId,
                productCode: v.productCode,
                color: v.color,
                size: v.size,
                quantity: v.quantity,
                costPrice: v.costPrice,
                salePrice: v.salePrice,
                minStock: v.minStock,
                createdAt: v.createdAt,
                productName: _productNameMap[v.productId],
              )).toList();
              if (isClosed) return;
              final prev = state;
              List<VariantEntity> filtered = _allVariants;
              if (_currentSelectedCategoryId != 'All') {
                filtered = filtered
                    .where((v) => _productCategoryMap[v.productId] == _currentSelectedCategoryId)
                    .toList();
              }
              if (_currentSearchQuery.trim().isNotEmpty) {
                final q = _normalize(_currentSearchQuery);
                filtered = filtered.where((v) {
                  final prodName = _normalize(getProductName(v.productId));
                  final variantProdName = _normalize(v.productName);
                  final sku = _normalize(v.sku);
                  final code = _normalize(v.productCode);
                  final color = _normalize(v.color);
                  final size = _normalize(v.size);
                  final catId = _productCategoryMap[v.productId];
                  final catName = _normalize(_categoryNameMap[catId] ?? '');
                  return prodName.contains(q) ||
                      variantProdName.contains(q) ||
                      sku.contains(q) ||
                      code.contains(q) ||
                      color.contains(q) ||
                      size.contains(q) ||
                      catName.contains(q);
                }).toList();
              }
              emit(PosLoaded(
                filteredVariants: filtered,
                categories: categories,
                selectedCategory: _currentSelectedCategoryId,
                cart: prev.cart,
                customer: prev.customer,
                subtotal: prev.subtotal,
                total: prev.total,
                isProcessing: prev.isProcessing,
              ));
            },
          );
        },
        onError: (e) {
          if (!isClosed) emit(PosError('تعذر تحميل بيانات نقطة البيع: $e'));
        },
      );
    } catch (e) {
      emit(PosError('تعذر تحميل بيانات نقطة البيع: $e'));
    }
  }

  String _normalize(String input) {
    return input
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '')
        .toLowerCase()
        .trim();
  }

  void filterByCategory(String categoryId) {
    _currentSelectedCategoryId = categoryId;
    _applyFilters();
  }

  String? getProductCategoryId(String productId) => _productCategoryMap[productId];
  String getProductName(String productId) => _productNameMap[productId] ?? '';

  List<VariantEntity> getVariantsForProduct(String productId) =>
      _allVariants.where((v) => v.productId == productId).toList();

  void searchProducts(String query) {
    _currentSearchQuery = query;
    _applyFilters();
  }

  void _applyFilters() {
    if (isClosed) return;
    final state = this.state;
    List<VariantEntity> result = _allVariants;

    if (_currentSelectedCategoryId != 'All') {
      result = result
          .where((v) => _productCategoryMap[v.productId] == _currentSelectedCategoryId)
          .toList();
    }

    if (_currentSearchQuery.trim().isNotEmpty) {
      final q = _normalize(_currentSearchQuery);
      result = result.where((v) {
        final prodName = _normalize(getProductName(v.productId));
        final variantProdName = _normalize(v.productName);
        final sku = _normalize(v.sku);
        final code = _normalize(v.productCode);
        final color = _normalize(v.color);
        final size = _normalize(v.size);
        final catId = _productCategoryMap[v.productId];
        final catName = _normalize(_categoryNameMap[catId] ?? '');

        return prodName.contains(q) ||
            variantProdName.contains(q) ||
            sku.contains(q) ||
            code.contains(q) ||
            color.contains(q) ||
            size.contains(q) ||
            catName.contains(q);
      }).toList();
    }

    if (isClosed) return;
    emit(state.copyWith(
      filteredVariants: result,
      selectedCategory: _currentSelectedCategoryId,
    ));
  }

  void addToCart(VariantEntity variant, [int quantity = 1]) {
    if (quantity <= 0) return;
    final state = this.state;
    final existingIndex = state.cart.indexWhere((item) => item.variantId == variant.id);
    List<SaleItemEntity> newCart;
    if (existingIndex >= 0) {
      final existing = state.cart[existingIndex];
      final updated = existing.copyWith(quantity: existing.quantity + quantity);
      newCart = List<SaleItemEntity>.from(state.cart);
      newCart[existingIndex] = updated;
    } else {
      final newItem = SaleItemEntity(
        variantId: variant.id,
        productName: variant.productName,
        size: variant.size,
        color: variant.color,
        price: variant.salePrice,
        quantity: quantity,
      );
      newCart = [...state.cart, newItem];
    }
    _updateCart(state, newCart);
  }

  bool addByBarcode(String barcode) {
    final clean = _normalize(barcode);
    if (clean.isEmpty) return false;
    try {
      final match = _allVariants.firstWhere(
        (v) =>
            _normalize(v.sku) == clean ||
            _normalize(v.productCode) == clean ||
            _normalize(getProductName(v.productId)) == clean ||
            _normalize(v.productName) == clean,
      );
      if (match.quantity > 0) {
        addToCart(match, 1);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  VariantEntity? getVariantById(String variantId) {
    try {
      return _allVariants.firstWhere((v) => v.id == variantId);
    } catch (_) {
      return null;
    }
  }

  void removeFromCart(String variantId) {
    final state = this.state;
    final newCart = state.cart.where((item) => item.variantId != variantId).toList();
    _updateCart(state, newCart);
  }

  void updateQuantity(String variantId, int newQty) {
    final state = this.state;
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
    final newCart = state.cart.map((item) {
      if (item.variantId == variantId) {
        return item.copyWith(price: newPrice);
      }
      return item;
    }).toList();
    _updateCart(state, newCart);
  }

  void applyItemDiscount(String variantId, int discount) {
    final state = this.state;
    final newCart = state.cart.map((item) {
      if (item.variantId == variantId) {
        return item.copyWith(discount: discount);
      }
      return item;
    }).toList();
    _updateCart(state, newCart);
  }

  void applyDiscount(int discountPiasters) {
    final state = this.state;
    final newTotal = state.subtotal - discountPiasters;
    emit(state.copyWith(total: newTotal < 0 ? 0 : newTotal));
  }

  void clearCart() {
    final state = this.state;
    emit(state.copyWith(cart: const [], subtotal: 0, total: 0));
  }

  void assignCustomer(CustomerEntity? customer) {
    emit(state.copyWith(
      customer: customer,
      clearCustomer: customer == null,
    ));
  }

  void changePaymentMethod(String method) {}

  Future<bool> checkout({String? cashierId, String paymentMethod = 'cash'}) async {
    final state = this.state;
    if (state.cart.isEmpty) return false;
    emit(state.copyWith(isProcessing: true));

    try {
      String effectiveCashierId = cashierId ?? '';
      if (effectiveCashierId.isEmpty) {
        final cashierResult = await _posRepository.getActiveCashierId();
        effectiveCashierId = cashierResult.getOrElse(() => 'cashier_local');
      }

      final sale = SaleEntity(
        id: '',
        date: DateTime.now(),
        cashierId: effectiveCashierId,
        cashierName: 'Cashier',
        customerId: state.customer?.id,
        items: state.cart,
        subtotal: state.subtotal.toDouble(),
        discount: (state.subtotal - state.total).toDouble(),
        total: state.total.toDouble(),
        paymentMethod: paymentMethod,
      );
      final result = await _createSaleUseCase(sale);
      final success = result.isRight();
      if (success) {
        emit(PosLoaded(
          filteredVariants: state.filteredVariants,
          categories: state.categories,
          selectedCategory: state.selectedCategory,
          cart: const [],
          customer: null,
          subtotal: 0,
          total: 0,
          isProcessing: false,
        ));
      } else {
        emit(state.copyWith(isProcessing: false));
      }
      return success;
    } catch (e) {
      emit(state.copyWith(isProcessing: false));
      return false;
    }
  }

  void _updateCart(PosState state, List<SaleItemEntity> newCart) {
    final subtotal = newCart.fold(0, (sum, item) => sum + item.total);
    emit(state.copyWith(cart: newCart, subtotal: subtotal, total: subtotal));
  }

  @override
  Future<void> close() {
    _variantsSubscription?.cancel();
    return super.close();
  }
}