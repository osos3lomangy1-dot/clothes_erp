import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../../pos/domain/entities/sale_entity.dart';
import '../../domain/usecases/get_recent_sales_usecase.dart';
import '../../domain/usecases/process_return_usecase.dart';
import 'returns_state.dart';

@injectable
class ReturnsCubit extends Cubit<ReturnsState> {
  final GetRecentSalesUseCase _getRecentSalesUseCase;
  final ProcessReturnUseCase _processReturnUseCase;

  ReturnsCubit(
    this._getRecentSalesUseCase,
    this._processReturnUseCase,
  ) : super(const ReturnsState());

  Future<void> init() async {
    await Future.wait([
      loadRecentSales(),
      loadReturnsHistory(),
    ]);
  }

  Future<void> loadRecentSales() async {
    emit(state.copyWith(isLoading: true, clearMessages: true));
    try {
      final result = await _getRecentSalesUseCase.getRecentSales();
      result.fold(
        (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
        (sales) => emit(state.copyWith(isLoading: false, recentSales: sales)),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: 'تعذر تحميل فواتير البيع: $e'));
    }
  }

  Future<void> loadReturnsHistory() async {
    try {
      final result = await _getRecentSalesUseCase.getReturnsHistory();
      result.fold(
        (_) {},
        (history) => emit(state.copyWith(returnsHistory: history)),
      );
    } catch (_) {}
  }

  Future<void> searchSale(String query) async {
    if (query.trim().isEmpty) {
      await loadRecentSales();
      return;
    }
    emit(state.copyWith(isLoading: true, clearMessages: true));
    try {
      final result = await _getRecentSalesUseCase.getSaleByIdOrRef(query.trim());
      result.fold(
        (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
        (sale) {
          if (sale != null) {
            selectSale(sale);
          } else {
            emit(state.copyWith(isLoading: false, errorMessage: 'لم يتم العثور على فاتورة مطابقة للبحث "$query"'));
          }
        },
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: 'تعذر البحث عن الفاتورة: $e'));
    }
  }

  Future<void> selectSale(SaleEntity sale) async {
    emit(state.copyWith(isLoading: true, selectedSale: sale, clearMessages: true));
    try {
      final result = await _getRecentSalesUseCase.getSaleItems(sale.id);
      result.fold(
        (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
        (items) {
          final totalReturnable = items.fold<int>(0, (sum, it) => sum + it.maxQty);
          if (totalReturnable == 0) {
            emit(state.copyWith(
              isLoading: false,
              clearSelectedSale: true,
              errorMessage: 'الفاتورة #${sale.id.length > 8 ? sale.id.substring(0, 8) : sale.id} تم إرجاع جميع أصنافها بالكامل مسبقاً، ولا يمكن إجراء مرتجع إضافي.',
            ));
          } else {
            emit(state.copyWith(
              isLoading: false,
              selectedSale: sale,
              returnItems: items,
            ));
          }
        },
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: 'تعذر تحميل أصناف الفاتورة: $e'));
    }
  }

  void updateItemQty(String variantId, int newQty) {
    final updated = state.returnItems.map((item) {
      if (item.variantId == variantId) {
        final clamped = newQty.clamp(0, item.maxQty);
        return item.copyWith(qty: clamped);
      }
      return item;
    }).toList();
    emit(state.copyWith(returnItems: updated));
  }

  void clearSelection() {
    emit(state.copyWith(
      clearSelectedSale: true,
      returnItems: const [],
      clearMessages: true,
    ));
    loadRecentSales();
  }

  Future<bool> processReturn({
    required String reason,
    required String userId,
    String paymentMethod = 'cash',
  }) async {
    final activeItems = state.returnItems.where((i) => i.qty > 0).toList();
    if (activeItems.isEmpty) {
      emit(state.copyWith(errorMessage: 'يرجى تحديد كمية صنف واحد على الأقل لإرجاعه.'));
      return false;
    }
    if (reason.trim().isEmpty) {
      emit(state.copyWith(errorMessage: 'يرجى كتابة سبب الإرجاع للمتابعة.'));
      return false;
    }

    emit(state.copyWith(isProcessing: true, clearMessages: true));
    try {
      final saleId = state.selectedSale?.id ?? '';
      final result = await _processReturnUseCase(
        saleId: saleId,
        items: activeItems,
        reason: reason.trim(),
        userId: userId,
        paymentMethod: paymentMethod,
      );

      return await result.fold(
        (failure) async {
          emit(state.copyWith(isProcessing: false, errorMessage: failure.message));
          return false;
        },
        (_) async {
          emit(state.copyWith(
            isProcessing: false,
            clearSelectedSale: true,
            returnItems: const [],
            successMessage: 'تم تسجيل المرتجع بنجاح، وتحديث المخزون وخصم المبلغ من الدرج!',
          ));
          await loadRecentSales();
          await loadReturnsHistory();
          return true;
        },
      );
    } catch (e) {
      emit(state.copyWith(isProcessing: false, errorMessage: 'تعذر معالجة المرتجع: $e'));
      return false;
    }
  }
}
