import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/customer_entity.dart';
import '../../domain/repositories/customer_repository.dart';

enum CustomerStatus { initial, loading, success, error }

class CustomerState extends Equatable {
  final CustomerStatus status;
  final List<CustomerEntity> customers;
  final String? errorMessage;
  final String searchQuery;

  const CustomerState({
    this.status = CustomerStatus.initial,
    this.customers = const [],
    this.errorMessage,
    this.searchQuery = '',
  });

  CustomerState copyWith({
    CustomerStatus? status,
    List<CustomerEntity>? customers,
    String? errorMessage,
    String? searchQuery,
    bool clearError = false,
  }) {
    return CustomerState(
      status: status ?? this.status,
      customers: customers ?? this.customers,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [status, customers, errorMessage, searchQuery];
}

@injectable
class CustomerCubit extends Cubit<CustomerState> {
  final CustomerRepository _repository;

  CustomerCubit(this._repository) : super(const CustomerState()) {
    loadCustomers();
  }

  Future<void> loadCustomers({String? search}) async {
    final query = search ?? state.searchQuery;
    emit(state.copyWith(status: CustomerStatus.loading, searchQuery: query, clearError: true));
    try {
      final result = await _repository.getCustomers(search: query.isEmpty ? null : query);
      result.fold(
        (failure) => emit(state.copyWith(status: CustomerStatus.error, errorMessage: failure.message)),
        (customers) => emit(state.copyWith(status: CustomerStatus.success, customers: customers)),
      );
    } catch (e) {
      emit(state.copyWith(status: CustomerStatus.error, errorMessage: 'تعذر تحميل بيانات العملاء: $e'));
    }
  }

  void searchCustomers(String query) {
    loadCustomers(search: query);
  }

  Future<bool> addCustomer(CustomerEntity customer) async {
    try {
      final result = await _repository.addCustomer(customer);
      return await result.fold(
        (failure) async {
          emit(state.copyWith(status: CustomerStatus.error, errorMessage: failure.message));
          return false;
        },
        (_) async {
          await loadCustomers();
          return true;
        },
      );
    } catch (e) {
      emit(state.copyWith(status: CustomerStatus.error, errorMessage: 'تعذر إضافة العميل: $e'));
      return false;
    }
  }

  Future<bool> updateCustomer(CustomerEntity customer) async {
    try {
      final result = await _repository.updateCustomer(customer);
      return await result.fold(
        (failure) async {
          emit(state.copyWith(status: CustomerStatus.error, errorMessage: failure.message));
          return false;
        },
        (_) async {
          await loadCustomers();
          return true;
        },
      );
    } catch (e) {
      emit(state.copyWith(status: CustomerStatus.error, errorMessage: 'تعذر تحديث العميل: $e'));
      return false;
    }
  }

  Future<bool> deleteCustomer(String id) async {
    try {
      final result = await _repository.deleteCustomer(id);
      return await result.fold(
        (failure) async {
          emit(state.copyWith(status: CustomerStatus.error, errorMessage: failure.message));
          return false;
        },
        (_) async {
          await loadCustomers();
          return true;
        },
      );
    } catch (e) {
      emit(state.copyWith(status: CustomerStatus.error, errorMessage: 'تعذر حذف العميل: $e'));
      return false;
    }
  }
}
