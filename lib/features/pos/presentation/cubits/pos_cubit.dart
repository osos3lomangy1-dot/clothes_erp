import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/payment_split.dart';
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
import '../../../promotions/domain/entities/promotion.dart';
import '../../../promotions/domain/repositories/promotions_repository.dart';
import '../../../promotions/domain/services/promotion_engine.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart' hide Promotion;
import 'package:drift/drift.dart' show Value;
import '../../../inventory/data/datasources/inventory_local_data_source.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../settings/data/services/activity_settings_service.dart';

class PosState {
  final List<VariantEntity> filteredVariants;
  final List<CategoryEntity> categories;
  final String selectedCategory;
  final String selectedActivity;
  final List<SaleItemEntity> cart;
  final CustomerEntity? customer;
  final int subtotal;
  final int total;
  final bool isProcessing;
  final PromotionEvaluationResult? promotionResult;
  final int promotionDiscountPiasters;

  const PosState({
    this.filteredVariants = const [],
    this.categories = const [],
    this.selectedCategory = 'All',
    this.selectedActivity = 'all',
    this.cart = const [],
    this.customer,
    this.subtotal = 0,
    this.total = 0,
    this.isProcessing = false,
    this.promotionResult,
    this.promotionDiscountPiasters = 0,
  });

  bool get hasExchangeItems => cart.any((item) => item.isReturn);
  int get returnItemsTotal => cart
      .where((item) => item.isReturn)
      .fold<int>(0, (sum, item) => sum + (item.price * item.effectiveQuantity).round());
  int get newItemsTotal => cart
      .where((item) => !item.isReturn)
      .fold<int>(0, (sum, item) => sum + (item.price * item.effectiveQuantity).round());
  bool get isZeroNetExchange => hasExchangeItems && total == 0;

  PosState copyWith({
    List<VariantEntity>? filteredVariants,
    List<CategoryEntity>? categories,
    String? selectedCategory,
    String? selectedActivity,
    List<SaleItemEntity>? cart,
    CustomerEntity? customer,
    bool clearCustomer = false,
    int? subtotal,
    int? total,
    bool? isProcessing,
    PromotionEvaluationResult? promotionResult,
    int? promotionDiscountPiasters,
  }) {
    return PosState(
      filteredVariants: filteredVariants ?? this.filteredVariants,
      categories: categories ?? this.categories,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      selectedActivity: selectedActivity ?? this.selectedActivity,
      cart: cart ?? this.cart,
      customer: clearCustomer ? null : (customer ?? this.customer),
      subtotal: subtotal ?? this.subtotal,
      total: total ?? this.total,
      isProcessing: isProcessing ?? this.isProcessing,
      promotionResult: promotionResult ?? this.promotionResult,
      promotionDiscountPiasters:
          promotionDiscountPiasters ?? this.promotionDiscountPiasters,
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
    super.selectedActivity = 'all',
    super.cart,
    super.customer,
    super.subtotal,
    super.total,
    super.isProcessing,
    super.promotionResult,
    super.promotionDiscountPiasters,
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
  final PromotionsRepository? _promotionsRepository;

  List<VariantEntity> _allVariants = [];
  Map<String, String> _productCategoryMap = {};
  Map<String, String> _productNameMap = {};
  Map<String, ProductEntity> _productMap = {};
  Map<String, String> _categoryNameMap = {};
  Map<String, String> _productActivityTypeMap = {};
  Map<String, bool> _productInstallmentEligibleMap = {};
  List<Promotion> _activePromotions = [];
  Map<String, Set<String>> _categoryDescendants = {};
  Map<String, String> _searchTokenMap = {};
  Map<String, VariantEntity> _barcodeMap = {};
  String _currentSearchQuery = '';
  String _currentSelectedCategoryId = 'All';
  String _currentSelectedActivity = 'all';
  StreamSubscription? _variantsSubscription;
  StreamSubscription<List<ActivityType>>? _enabledActivitiesSubscription;
  Set<String> _currentEnabledActivities = {};

  Set<String> get currentEnabledActivities => _currentEnabledActivities;
  String get currentSearchQuery => _currentSearchQuery;

  PosCubit(
    this._createSaleUseCase,
    this._variantRepository,
    this._categoryRepository,
    this._productRepository,
    this._posRepository, [
    this._promotionsRepository,
  ]) : super(const PosState());

  List<Promotion> get activePromotions => List.unmodifiable(_activePromotions);

  Future<void> reloadPromotions([DateTime? now]) async {
    if (_promotionsRepository != null) {
      final res = await _promotionsRepository.getActivePromotions(now: now ?? DateTime.now());
      _activePromotions = res.getOrElse(() => []);
    }
    _updateCart(state, state.cart);
  }

  Future<void> init() async {
    emit(const PosLoading());
    try {
      final categoriesResult = await _categoryRepository.getCategories();
      final productsResult = await _productRepository.getProducts();

      final categories = categoriesResult.getOrElse(() => []);
      final products = productsResult.getOrElse(() => []);
      _productMap = {for (final p in products) p.id: p};
      _productCategoryMap = {for (final p in products) p.id: p.categoryId};
      _productNameMap = {for (final p in products) p.id: p.name};
      _categoryNameMap = {for (final c in categories) c.id: c.name};
      _productActivityTypeMap = {for (final p in products) p.id: p.activityType};
      _productInstallmentEligibleMap = {for (final p in products) p.id: p.isInstallmentEligible};
      _categoryDescendants = {for (final c in categories) c.id: {c.id}};

      if (_promotionsRepository != null) {
        final promoRes = await _promotionsRepository.getActivePromotions(now: DateTime.now());
        _activePromotions = promoRes.getOrElse(() => []);
      }

      if (getIt.isRegistered<ActivitySettingsService>()) {
        final activityService = getIt<ActivitySettingsService>();
        try {
          final initial = await activityService.getEnabledActivities();
          _currentEnabledActivities = initial.map((a) => a.code).toSet();
        } catch (_) {}

        _enabledActivitiesSubscription?.cancel();
        _enabledActivitiesSubscription = activityService.watchEnabledActivities().listen((acts) {
          if (isClosed) return;
          _currentEnabledActivities = acts.map((a) => a.code).toSet();
          if (_currentSelectedActivity != 'all' && !_currentEnabledActivities.contains(_currentSelectedActivity)) {
            _currentSelectedActivity = 'all';
          }
          _applyFilters();
        });
      }

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
              _rebuildSearchIndex();
              if (isClosed) return;
              final prev = state;
              List<VariantEntity> filtered = _allVariants;
              if (_currentEnabledActivities.isNotEmpty) {
                filtered = filtered
                    .where((v) => _currentEnabledActivities.contains(_productActivityTypeMap[v.productId] ?? 'clothing'))
                    .toList();
              }
              if (_currentSelectedActivity != 'all') {
                if (_currentEnabledActivities.isNotEmpty && !_currentEnabledActivities.contains(_currentSelectedActivity)) {
                  _currentSelectedActivity = 'all';
                } else {
                  filtered = filtered
                      .where((v) => (_productActivityTypeMap[v.productId] ?? 'clothing') == _currentSelectedActivity)
                      .toList();
                }
              }
              if (_currentSelectedCategoryId != 'All') {
                filtered = filtered
                    .where((v) => _productCategoryMap[v.productId] == _currentSelectedCategoryId)
                    .toList();
              }
              if (_currentSearchQuery.trim().isNotEmpty) {
                final q = _normalize(_currentSearchQuery);
                filtered = filtered.where((v) {
                  final token = _searchTokenMap[v.id];
                  if (token != null) return token.contains(q);
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
                selectedActivity: _currentSelectedActivity,
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

  void _rebuildSearchIndex() {
    final searchTokenMap = <String, String>{};
    final barcodeMap = <String, VariantEntity>{};
    for (final v in _allVariants) {
      final pName = _productNameMap[v.productId] ?? '';
      final catId = _productCategoryMap[v.productId];
      final catName = _categoryNameMap[catId] ?? '';
      final token = _normalize('$pName ${v.productName} ${v.sku} ${v.productCode} ${v.color} ${v.size} $catName');
      searchTokenMap[v.id] = token;
      if (v.productCode.isNotEmpty) {
        barcodeMap[v.productCode.trim()] = v;
        barcodeMap[_normalize(v.productCode)] = v;
      }
      if (v.sku.isNotEmpty) {
        barcodeMap[v.sku.trim()] = v;
        barcodeMap[_normalize(v.sku)] = v;
      }
    }
    _searchTokenMap = searchTokenMap;
    _barcodeMap = barcodeMap;
  }

  void filterByCategory(String categoryId) {
    _currentSelectedCategoryId = categoryId;
    _applyFilters();
  }

  void filterByActivity(String activity) {
    _currentSelectedActivity = activity;
    _applyFilters();
  }

  void resetAllFilters() {
    _currentSelectedActivity = 'all';
    _currentSelectedCategoryId = 'All';
    _applyFilters();
  }

  void resetFilters() => resetAllFilters();

  String? getProductCategoryId(String productId) => _productCategoryMap[productId];
  String? getProductActivityType(String productId) => _productActivityTypeMap[productId];
  String getProductName(String productId) => _productNameMap[productId] ?? '';
  ProductEntity? getProduct(String productId) => _productMap[productId];
  Map<String, ProductEntity> get productMap => Map.unmodifiable(_productMap);
  bool isProductInstallmentEligible(String? productId) {
    if (productId == null) return true;
    return _productInstallmentEligibleMap[productId] ?? true;
  }

  List<VariantEntity> get allVariants => List.unmodifiable(_allVariants);

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

    // 1. Exclude variants belonging to disabled activities (even in 'all' mode)
    if (_currentEnabledActivities.isNotEmpty) {
      result = result
          .where((v) => _currentEnabledActivities.contains(_productActivityTypeMap[v.productId] ?? 'clothing'))
          .toList();
    }

    // Exclude hospitality raw materials from POS grid
    result = result.where((v) {
      final p = _productMap[v.productId];
      return !(p?.isRestaurantRawMaterial ?? false);
    }).toList();

    // 2. Filter by selected activity tab
    if (_currentSelectedActivity != 'all') {
      if (_currentEnabledActivities.isNotEmpty && !_currentEnabledActivities.contains(_currentSelectedActivity)) {
        _currentSelectedActivity = 'all';
      } else {
        result = result
            .where((v) => (_productActivityTypeMap[v.productId] ?? 'clothing') == _currentSelectedActivity)
            .toList();
      }
    }

    if (_currentSelectedCategoryId != 'All') {
      result = result
          .where((v) => _productCategoryMap[v.productId] == _currentSelectedCategoryId)
          .toList();
    }

    if (_currentSearchQuery.trim().isNotEmpty) {
      final q = _normalize(_currentSearchQuery);
      result = result.where((v) {
        final token = _searchTokenMap[v.id];
        if (token != null) return token.contains(q);
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
      selectedActivity: _currentSelectedActivity,
    ));
  }

  void addToCart(
    VariantEntity variant, [
    int quantity = 1,
    String? kitchenNotes,
    List<String> modifiers = const [],
  ]) {
    if (quantity <= 0) return;
    final state = this.state;
    final cleanNotes = (kitchenNotes != null && kitchenNotes.trim().isNotEmpty)
        ? kitchenNotes.trim()
        : null;
    final existingIndex = state.cart.indexWhere((item) =>
        item.variantId == variant.id &&
        !item.isReturn &&
        (item.kitchenNotes ?? '') == (cleanNotes ?? '') &&
        _modifiersEqual(item.modifiers, modifiers));
    List<SaleItemEntity> newCart;
    if (existingIndex >= 0) {
      final existing = state.cart[existingIndex];
      final updated = existing.copyWith(quantity: existing.quantity + quantity);
      newCart = List<SaleItemEntity>.from(state.cart);
      newCart[existingIndex] = updated;
    } else {
      final newItem = SaleItemEntity(
        variantId: variant.id,
        productId: variant.productId,
        categoryId: _productCategoryMap[variant.productId],
        productName: variant.productName,
        size: variant.size,
        color: variant.color,
        price: variant.salePrice,
        quantity: quantity,
        kitchenNotes: cleanNotes,
        modifiers: modifiers,
      );
      newCart = [...state.cart, newItem];
    }
    _updateCart(state, newCart);
  }

  static bool _modifiersEqual(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void addExchangeItem(VariantEntity variant, [int quantity = 1]) {
    if (quantity <= 0) return;
    final state = this.state;
    final existingIndex = state.cart.indexWhere((item) => item.variantId == variant.id && item.isReturn);
    List<SaleItemEntity> newCart;
    if (existingIndex >= 0) {
      final existing = state.cart[existingIndex];
      final updated = existing.copyWith(quantity: existing.quantity + quantity);
      newCart = List<SaleItemEntity>.from(state.cart);
      newCart[existingIndex] = updated;
    } else {
      final newItem = SaleItemEntity(
        variantId: variant.id,
        productId: variant.productId,
        categoryId: _productCategoryMap[variant.productId],
        productName: variant.productName,
        size: variant.size,
        color: variant.color,
        price: variant.salePrice,
        quantity: quantity,
        isReturn: true,
      );
      newCart = [...state.cart, newItem];
    }
    _updateCart(state, newCart);
  }

  /// Adds multiple variants with specified quantities in a single atomic batch (Task 17)
  void addMultipleToCart(Map<VariantEntity, int> items) {
    if (items.isEmpty) return;
    final state = this.state;
    var newCart = List<SaleItemEntity>.from(state.cart);

    for (final entry in items.entries) {
      final variant = entry.key;
      final quantity = entry.value;
      if (quantity <= 0) continue;

      final existingIndex =
          newCart.indexWhere((item) => item.variantId == variant.id);
      if (existingIndex >= 0) {
        final existing = newCart[existingIndex];
        newCart[existingIndex] = existing.copyWith(
          quantity: existing.quantity + quantity,
        );
      } else {
        final newItem = SaleItemEntity(
          variantId: variant.id,
          productId: variant.productId,
          categoryId: _productCategoryMap[variant.productId],
          productName: variant.productName,
          size: variant.size,
          color: variant.color,
          price: variant.salePrice,
          quantity: quantity,
        );
        newCart.add(newItem);
      }
    }

    _updateCart(state, newCart);
  }

  bool addByBarcode(String barcode) {
    final clean = _normalize(barcode);
    if (clean.isEmpty) return false;
    VariantEntity? match = _barcodeMap[clean] ?? _barcodeMap[barcode.trim()];
    if (match == null) {
      try {
        match = _allVariants.firstWhere(
          (v) =>
              _normalize(v.sku) == clean ||
              _normalize(v.productCode) == clean ||
              _normalize(getProductName(v.productId)) == clean ||
              _normalize(v.productName) == clean,
        );
      } catch (_) {
        return false;
      }
    }
    if (match.quantity > 0) {
      addToCart(match, 1);
      return true;
    }
    return false;
  }

  VariantEntity? getVariantById(String variantId) {
    try {
      return _allVariants.firstWhere((v) => v.id == variantId);
    } catch (_) {
      return null;
    }
  }

  void removeFromCart(String variantId, {bool? isReturn}) {
    final state = this.state;
    final newCart = state.cart.where((item) {
      if (item.variantId != variantId) return true;
      if (isReturn != null) {
        return item.isReturn != isReturn;
      }
      return false;
    }).toList();
    _updateCart(state, newCart);
  }

  void updateQuantity(String variantId, int newQty, {bool? isReturn}) {
    final state = this.state;
    if (newQty <= 0) {
      removeFromCart(variantId, isReturn: isReturn);
      return;
    }
    final newCart = state.cart.map((item) {
      if (item.variantId == variantId && (isReturn == null || item.isReturn == isReturn)) {
        return item.copyWith(
          quantity: newQty,
          clearDecimalQuantity: true,
        );
      }
      return item;
    }).toList();
    _updateCart(state, newCart);
  }

  void updateDecimalQuantity(String variantId, double newQty, [String? unit, bool? isReturn]) {
    final state = this.state;
    if (newQty <= 0) {
      removeFromCart(variantId, isReturn: isReturn);
      return;
    }
    final newCart = state.cart.map((item) {
      if (item.variantId == variantId && (isReturn == null || item.isReturn == isReturn)) {
        return item.copyWith(
          quantity: newQty.ceil(),
          decimalQuantity: newQty,
          unit: unit ?? item.unit,
        );
      }
      return item;
    }).toList();
    _updateCart(state, newCart);
  }

  void updateKitchenNotes(String variantId, String? notes, {List<String>? modifiers, bool? isReturn}) {
    final state = this.state;
    final newCart = state.cart.map((item) {
      if (item.variantId == variantId && (isReturn == null || item.isReturn == isReturn)) {
        return item.copyWith(
          kitchenNotes: notes,
          clearKitchenNotes: notes == null || notes.trim().isEmpty,
          modifiers: modifiers ?? item.modifiers,
        );
      }
      return item;
    }).toList();
    _updateCart(state, newCart);
  }

  void increaseQty(String variantId, {bool? isReturn}) {
    final state = this.state;
    SaleItemEntity? item;
    try {
      item = state.cart.firstWhere(
        (i) => i.variantId == variantId && (isReturn == null || i.isReturn == isReturn),
      );
    } catch (_) {
      item = null;
    }
    if (item != null) {
      if (item.decimalQuantity != null && item.decimalQuantity! > 0) {
        updateDecimalQuantity(variantId, item.decimalQuantity! + 1.0, item.unit, item.isReturn);
      } else {
        updateQuantity(variantId, item.quantity + 1, isReturn: item.isReturn);
      }
    }
  }

  void decreaseQty(String variantId, {bool? isReturn}) {
    final state = this.state;
    SaleItemEntity? item;
    try {
      item = state.cart.firstWhere(
        (i) => i.variantId == variantId && (isReturn == null || i.isReturn == isReturn),
      );
    } catch (_) {
      item = null;
    }
    if (item != null) {
      if (item.decimalQuantity != null && item.decimalQuantity! > 0) {
        final newQty = item.decimalQuantity! - 1.0;
        if (newQty <= 0) {
          removeFromCart(variantId, isReturn: item.isReturn);
        } else {
          updateDecimalQuantity(variantId, newQty, item.unit, item.isReturn);
        }
      } else {
        updateQuantity(variantId, item.quantity - 1, isReturn: item.isReturn);
      }
    }
  }

  void updateUnitPrice(String variantId, int newPrice, {bool? isReturn}) {
    final state = this.state;
    final newCart = state.cart.map((item) {
      if (item.variantId == variantId && (isReturn == null || item.isReturn == isReturn)) {
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
    emit(state.copyWith(
      cart: const [],
      subtotal: 0,
      total: 0,
      promotionResult: null,
      promotionDiscountPiasters: 0,
    ));
  }

  void loadCart({
    required List<SaleItemEntity> cart,
    CustomerEntity? customer,
  }) {
    final next = state.copyWith(
      customer: customer,
      clearCustomer: customer == null,
    );
    _updateCart(next, cart);
  }

  void assignCustomer(CustomerEntity? customer) {
    final next = state.copyWith(
      customer: customer,
      clearCustomer: customer == null,
    );
    _updateCart(next, next.cart);
  }

  void changePaymentMethod(String method) {}

  Future<bool> checkout({
    String? cashierId,
    List<PaymentSplit>? splits,
    String paymentMethod = 'cash',
    void Function(SaleEntity sale)? onSaleCreated,
  }) async {
    final state = this.state;
    if (state.cart.isEmpty) return false;

    final isCredit = paymentMethod == 'credit';
    final effectiveSplits = splits ?? [
      PaymentSplit(
        method: isCredit ? 'credit' : (paymentMethod == 'card' ? 'card' : 'cash'),
        amountPiasters: state.total,
      ),
    ];

    if (paymentMethod != 'installment') {
      final splitTotal = effectiveSplits.fold<int>(0, (s, sp) => s + sp.amountPiasters);
      if (splitTotal != state.total) return false;
    }

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
        subtotal: state.subtotal,
        discount: state.subtotal - state.total,
        total: state.total,
        paymentMethod: paymentMethod == 'installment'
            ? 'installment'
            : (isCredit
                ? 'credit'
                : (effectiveSplits.length > 1 ? 'split' : effectiveSplits.first.method)),
        splits: effectiveSplits,
        promotionResult: state.promotionResult,
        promotionDiscount: state.promotionDiscountPiasters,
      );
      final result = await _createSaleUseCase(sale);
      final success = result.isRight();
      if (success) {
        // Fire optional callback with the CREATED sale (contains generated ID)
        final createdSale = result.getOrElse(() => sale);
        onSaleCreated?.call(createdSale);

        // Auto-deduct recipe raw materials from inventory for hospitality meals
        await _autoDeductRecipeRawMaterials(sale.items);

        emit(PosLoaded(
          filteredVariants: state.filteredVariants,
          categories: state.categories,
          selectedCategory: state.selectedCategory,
          cart: const [],
          customer: null,
          subtotal: 0,
          total: 0,
          isProcessing: false,
          promotionResult: null,
          promotionDiscountPiasters: 0,
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

  Future<bool> completeSale({
    String? cashierId,
    List<PaymentSplit>? splits,
    String paymentMethod = 'cash',
    void Function(SaleEntity sale)? onSaleCreated,
  }) => checkout(
    cashierId: cashierId,
    splits: splits,
    paymentMethod: paymentMethod,
    onSaleCreated: onSaleCreated,
  );

  Future<void> _autoDeductRecipeRawMaterials(List<SaleItemEntity> items) async {
    for (final item in items) {
      final variant = _allVariants.cast<VariantEntity?>().firstWhere(
        (v) => v?.id == item.variantId,
        orElse: () => null,
      );
      final productId = variant?.productId ?? _findProductIdForVariant(item.variantId);
      final product = productId != null ? getProduct(productId) : null;
      if (product == null || product.restaurantRecipeItems.isEmpty) continue;

      for (final recipeItem in product.restaurantRecipeItems) {
        // Formula: consumed = quantityNeeded * (1 + yieldLossPercentage / 100) * soldMealCount
        // Calculated accurately in base units (grams, ml, pieces) with round() to prevent stock depletion discrepancies
        final totalConsumed = recipeItem.effectiveQuantityNeeded(item.quantity);
        final int deductQty = totalConsumed.round();
        if (deductQty <= 0) continue;

        await _deductRawMaterialStock(
          recipeItem.rawMaterialId,
          deductQty,
          item.productName,
        );
      }
    }
  }

  Future<void> _deductRawMaterialStock(
    String rawMaterialId,
    int deductQty,
    String parentMealName,
  ) async {
    VariantEntity? targetVariant = _allVariants.cast<VariantEntity?>().firstWhere(
      (v) => v?.id == rawMaterialId,
      orElse: () => _allVariants.cast<VariantEntity?>().firstWhere(
        (v) => v?.productId == rawMaterialId,
        orElse: () => null,
      ),
    );

    String effectiveVariantId = targetVariant?.id ?? rawMaterialId;

    if (getIt.isRegistered<AppDatabase>()) {
      final db = getIt<AppDatabase>();
      if (targetVariant == null) {
        final row = await (db.select(db.productVariants)
              ..where((t) => t.id.equals(rawMaterialId))
              ..limit(1))
            .getSingleOrNull() ??
            await (db.select(db.productVariants)
              ..where((t) => t.productId.equals(rawMaterialId))
              ..limit(1))
            .getSingleOrNull();
        if (row != null) {
          effectiveVariantId = row.id;
        }
      }

      if (getIt.isRegistered<InventoryLocalDataSource>()) {
        try {
          await getIt<InventoryLocalDataSource>().applyStockMovement(
            variantId: effectiveVariantId,
            qtyDelta: -deductQty,
            type: StockMovementType.adjustment,
            reason: 'استهلاك تلقائي لوصفة طهي (BOM): $parentMealName',
            userId: 'pos_cashier',
            refType: 'recipe_bom',
          );
        } catch (_) {
          await _directDeductVariantQuantity(db, effectiveVariantId, deductQty);
        }
      } else {
        await _directDeductVariantQuantity(db, effectiveVariantId, deductQty);
      }
    }

    final idx = _allVariants.indexWhere((v) => v.id == effectiveVariantId);
    if (idx != -1) {
      final old = _allVariants[idx];
      _allVariants[idx] = old.copyWith(
        quantity: (old.quantity - deductQty).clamp(0, 999999),
      );
    }
  }

  Future<void> _directDeductVariantQuantity(
    AppDatabase db,
    String variantId,
    int deductQty,
  ) async {
    final row = await (db.select(db.productVariants)
          ..where((t) => t.id.equals(variantId)))
        .getSingleOrNull();
    if (row != null) {
      final newQty = (row.quantity - deductQty).clamp(0, 999999);
      await (db.update(db.productVariants)..where((t) => t.id.equals(variantId)))
          .write(
        ProductVariantsCompanion(
          quantity: Value(newQty),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  String? _findProductIdForVariant(String variantId) {
    for (final v in _allVariants) {
      if (v.id == variantId) return v.productId;
    }
    return null;
  }

  void _updateCart(PosState state, List<SaleItemEntity> newCart) {
    if (newCart.isEmpty) {
      emit(state.copyWith(
        cart: const [],
        subtotal: 0,
        total: 0,
        promotionResult: null,
        promotionDiscountPiasters: 0,
      ));
      return;
    }

    final customerPercent = state.customer?.discountPercent;
    final evalResult = PromotionEngine.apply(
      cart: newCart,
      activePromotions: _activePromotions,
      customerDiscountPercent: customerPercent,
      categoryDescendants: _categoryDescendants,
      now: DateTime.now(),
    );

    final updatedCart = <SaleItemEntity>[];
    for (int i = 0; i < newCart.length; i++) {
      final item = newCart[i];
      final lineResult = evalResult.lineResults[i];
      final promoDiscount = lineResult.promotionDiscountPiasters;
      updatedCart.add(item.copyWith(promotionDiscount: promoDiscount));
    }

    final subtotal = updatedCart.fold<int>(
      0,
      (sum, item) =>
          sum +
          (item.isReturn
              ? -(item.price * item.effectiveQuantity).round()
              : (item.price * item.effectiveQuantity).round()),
    );
    final totalPromo = evalResult.totalPromotionDiscountPiasters;
    final totalCustomer = evalResult.totalCustomerDiscountPiasters;
    final manualItemDiscounts = updatedCart.fold<int>(
      0,
      (sum, item) => sum + (item.isReturn ? 0 : item.discount),
    );

    final computedTotal = subtotal - manualItemDiscounts - totalPromo - totalCustomer;
    final finalTotal = computedTotal;

    emit(state.copyWith(
      cart: updatedCart,
      subtotal: subtotal,
      total: finalTotal,
      promotionResult: evalResult,
      promotionDiscountPiasters: totalPromo,
    ));
  }

  @override
  Future<void> close() {
    _variantsSubscription?.cancel();
    _enabledActivitiesSubscription?.cancel();
    return super.close();
  }
}