import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/usecases/get_all_inventory_usecase.dart';
import '../../domain/usecases/get_low_stock_usecase.dart';
import 'inventory_state.dart';

@injectable
class InventoryCubit extends Cubit<InventoryState> {
  final GetAllInventoryUseCase _getAllInventoryUseCase;
  final GetLowStockUseCase _getLowStockUseCase;

  InventoryCubit(
    this._getAllInventoryUseCase,
    this._getLowStockUseCase,
  ) : super(InventoryInitial());

  Future<void> loadInventory({bool lowStockOnly = false}) async {
    emit(InventoryLoading());
    final result = lowStockOnly 
        ? await _getLowStockUseCase() 
        : await _getAllInventoryUseCase();

    result.fold(
      (failure) => emit(InventoryError(failure.message)),
      (items) => emit(InventoryLoaded(items, showLowStockOnly: lowStockOnly)),
    );
  }

  void toggleLowStockFilter(bool value) {
    loadInventory(lowStockOnly: value);
  }
}
