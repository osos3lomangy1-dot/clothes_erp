import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../domain/entities/customer_entity.dart';
import '../../domain/repositories/customer_repository.dart';

enum CustomerStatus { initial, loading, success, error }

class CustomerState extends Equatable {
  final CustomerStatus status;
  final List<CustomerEntity> customers;
  final String? errorMessage;

  const CustomerState({
    this.status = CustomerStatus.initial,
    this.customers = const [],
    this.errorMessage,
  });

  CustomerState copyWith({
    CustomerStatus? status,
    List<CustomerEntity>? customers,
    String? errorMessage,
  }) {
    return CustomerState(
      status: status ?? this.status,
      customers: customers ?? this.customers,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, customers, errorMessage];
}

@injectable
class CustomerCubit extends Cubit<CustomerState> {
  final CustomerRepository _repository;

  CustomerCubit(this._repository) : super(const CustomerState()) {
    loadCustomers();
  }

  Future<void> loadCustomers() async {
    emit(state.copyWith(status: CustomerStatus.loading));
    final result = await _repository.getCustomers();
    result.fold(
      (failure) => emit(state.copyWith(status: CustomerStatus.error, errorMessage: failure.message)),
      (customers) => emit(state.copyWith(status: CustomerStatus.success, customers: customers)),
    );
  }

  Future<void> addCustomer(CustomerEntity customer) async {
    final result = await _repository.addCustomer(customer);
    result.fold(
      (failure) => emit(state.copyWith(status: CustomerStatus.error, errorMessage: failure.message)),
      (_) => loadCustomers(),
    );
  }
}
