import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/supplier_entity.dart';
import '../../domain/entities/supplier_payment_entity.dart';
import '../../domain/repositories/purchases_repository.dart';
import 'suppliers_state.dart';

@injectable
class SuppliersCubit extends Cubit<SuppliersState> {
  final PurchasesRepository _repository;

  SuppliersCubit(this._repository) : super(const SuppliersState());

  void onSearchChanged(String query) {
    emit(state.copyWith(searchQuery: query));
  }

  Future<void> loadSuppliers() async {
    emit(state.copyWith(status: SuppliersStatus.loading));

    final result = await _repository.getSuppliers();

    result.fold(
      (failure) => emit(state.copyWith(
        status: SuppliersStatus.error,
        errorMessage: failure.message,
      )),
      (suppliers) => emit(state.copyWith(
        status: SuppliersStatus.loaded,
        suppliers: suppliers,
      )),
    );
  }

  Future<SupplierEntity?> addSupplier({
    required String name,
    String? phone,
    String? companyName,
    String? address,
  }) async {
    final result = await _repository.addSupplier(
      name: name,
      phone: phone,
      companyName: companyName,
      address: address,
    );

    return result.fold(
      (failure) {
        emit(state.copyWith(
          status: SuppliersStatus.error,
          errorMessage: failure.message,
        ));
        return null;
      },
      (newSupplier) {
        final updatedList = [...state.suppliers, newSupplier];
        emit(state.copyWith(
          status: SuppliersStatus.loaded,
          suppliers: updatedList,
        ));
        return newSupplier;
      },
    );
  }

  Future<bool> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? companyName,
    String? address,
  }) async {
    final result = await _repository.updateSupplier(
      id: id,
      name: name,
      phone: phone,
      companyName: companyName,
      address: address,
    );

    return result.fold(
      (failure) {
        emit(state.copyWith(
          status: SuppliersStatus.error,
          errorMessage: failure.message,
        ));
        return false;
      },
      (updated) {
        final updatedList = state.suppliers.map((s) => s.id == id ? updated : s).toList();
        emit(state.copyWith(
          status: SuppliersStatus.loaded,
          suppliers: updatedList,
        ));
        return true;
      },
    );
  }

  Future<bool> deleteSupplier(String id) async {
    final result = await _repository.deleteSupplier(id);

    return result.fold(
      (failure) {
        emit(state.copyWith(
          status: SuppliersStatus.error,
          errorMessage: failure.message,
        ));
        return false;
      },
      (_) {
        final updatedList = state.suppliers.where((s) => s.id != id).toList();
        emit(state.copyWith(
          status: SuppliersStatus.loaded,
          suppliers: updatedList,
        ));
        return true;
      },
    );
  }

  Future<SupplierPaymentEntity?> addSupplierPayment({
    required String supplierId,
    String? purchaseId,
    required int amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? referenceNumber,
    String? notes,
    required String userId,
  }) async {
    final result = await _repository.addSupplierPayment(
      supplierId: supplierId,
      purchaseId: purchaseId,
      amount: amount,
      paymentDate: paymentDate,
      paymentMethod: paymentMethod,
      referenceNumber: referenceNumber,
      notes: notes,
      userId: userId,
    );

    return result.fold(
      (failure) {
        emit(state.copyWith(
          status: SuppliersStatus.error,
          errorMessage: failure.message,
        ));
        return null;
      },
      (payment) {
        // Refresh suppliers list to update balance
        loadSuppliers();
        return payment;
      },
    );
  }
}

