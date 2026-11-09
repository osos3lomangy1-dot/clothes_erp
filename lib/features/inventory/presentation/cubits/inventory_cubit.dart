import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../data/datasources/inventory_local_data_source.dart';
import '../../domain/usecases/get_all_inventory_usecase.dart';
import '../../domain/usecases/get_low_stock_usecase.dart';
import 'inventory_state.dart';

@injectable
class InventoryCubit extends Cubit<InventoryState> {
  final GetAllInventoryUseCase _getAllInventoryUseCase;
  final GetLowStockUseCase _getLowStockUseCase;
  final InventoryLocalDataSource _inventoryLocalDataSource;

  bool _isLowStockFilter = false;

  InventoryCubit(
    this._getAllInventoryUseCase,
    this._getLowStockUseCase,
    this._inventoryLocalDataSource,
  ) : super(InventoryInitial());

  Future<void> loadInventory({bool lowStockOnly = false}) async {
    _isLowStockFilter = lowStockOnly;
    emit(InventoryLoading());
    try {
      final result = lowStockOnly
          ? await _getLowStockUseCase()
          : await _getAllInventoryUseCase();

      result.fold(
        (failure) => emit(InventoryError(failure.message)),
        (items) => emit(InventoryLoaded(items, showLowStockOnly: lowStockOnly)),
      );
    } catch (e) {
      emit(InventoryError('تعذر تحميل بيانات المخزون: $e'));
    }
  }

  void toggleLowStockFilter(bool value) {
    loadInventory(lowStockOnly: value);
  }

  Future<void> receiveStock({
    required String variantId,
    required int quantity,
    required String reason,
    String userId = 'admin',
  }) async {
    if (quantity <= 0) {
      throw Exception('الكمية يجب أن تكون أكبر من صفر');
    }
    if (reason.trim().isEmpty) {
      throw Exception('يجب إدخال سبب التوريد أو اسم المورد');
    }

    try {
      await _inventoryLocalDataSource.applyStockMovement(
        variantId: variantId,
        qtyDelta: quantity,
        type: StockMovementType.receive,
        reason: reason.trim(),
        userId: userId,
      );

      await loadInventory(lowStockOnly: _isLowStockFilter);
    } catch (e) {
      emit(InventoryError('تعذر استلام المخزون: $e'));
      rethrow;
    }
  }

  Future<List<InventoryItemDetail>> searchVariants(String query) async {
    return _inventoryLocalDataSource.getInventoryDetails(search: query);
  }

  Future<List<dynamic>> getCategories() async {
    return _inventoryLocalDataSource.getCategories();
  }

  Future<InventoryItemDetail> quickCreateProductAndReceive({
    required String productName,
    required String categoryId,
    required String sku,
    required String color,
    required String size,
    required int costPrice,
    required int sellPrice,
    required int quantity,
    required String reason,
    String userId = 'admin',
  }) async {
    if (productName.trim().isEmpty) throw Exception('اسم المنتج مطلوب');
    if (sku.trim().isEmpty) throw Exception('كود الصنف (SKU) مطلوب');
    if (quantity <= 0) throw Exception('الكمية يجب أن تكون أكبر من صفر');
    if (reason.trim().isEmpty) throw Exception('اسم المورد أو رقم الفاتورة مطلوب');

    try {
      final detail = await _inventoryLocalDataSource.quickCreateProductAndReceive(
        productName: productName.trim(),
        categoryId: categoryId,
        sku: sku.trim(),
        color: color.trim().isEmpty ? 'افتراضي' : color.trim(),
        size: size.trim().isEmpty ? 'افتراضي' : size.trim(),
        costPrice: costPrice,
        sellPrice: sellPrice,
        quantity: quantity,
        reason: reason.trim(),
        userId: userId,
      );

      await loadInventory(lowStockOnly: _isLowStockFilter);
      return detail;
    } catch (e) {
      emit(InventoryError('تعذر إنشاء وتوريد المنتج: $e'));
      rethrow;
    }
  }
}
