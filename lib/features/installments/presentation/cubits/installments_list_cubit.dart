import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../customers/domain/repositories/customer_repository.dart';
import '../../domain/entities/customer_installment_entity.dart';
import '../../domain/facades/installments_facade.dart';

enum InstallmentsListStatus { initial, loading, success, error }

class InstallmentsListState extends Equatable {
  final InstallmentsListStatus status;
  final List<CustomerInstallmentEntity> allContracts;
  final List<CustomerInstallmentEntity> contracts;
  final Map<String, String> customerNames;
  final String filter; // 'all', 'active', 'completed', 'overdue', 'cancelled'
  final String searchQuery;
  final String? errorMessage;

  const InstallmentsListState({
    this.status = InstallmentsListStatus.initial,
    this.allContracts = const [],
    this.contracts = const [],
    this.customerNames = const {},
    this.filter = 'all',
    this.searchQuery = '',
    this.errorMessage,
  });

  InstallmentsListState copyWith({
    InstallmentsListStatus? status,
    List<CustomerInstallmentEntity>? allContracts,
    List<CustomerInstallmentEntity>? contracts,
    Map<String, String>? customerNames,
    String? filter,
    String? searchQuery,
    String? errorMessage,
  }) {
    return InstallmentsListState(
      status: status ?? this.status,
      allContracts: allContracts ?? this.allContracts,
      contracts: contracts ?? this.contracts,
      customerNames: customerNames ?? this.customerNames,
      filter: filter ?? this.filter,
      searchQuery: searchQuery ?? this.searchQuery,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        allContracts,
        contracts,
        customerNames,
        filter,
        searchQuery,
        errorMessage,
      ];
}

@injectable
class InstallmentsListCubit extends Cubit<InstallmentsListState> {
  final InstallmentsFacade _facade;
  final CustomerRepository _customerRepo;
  Timer? _debounceTimer;

  InstallmentsListCubit(
    this._facade,
    this._customerRepo,
  ) : super(const InstallmentsListState()) {
    loadContracts();
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }

  Future<void> loadContracts() async {
    emit(state.copyWith(status: InstallmentsListStatus.loading));

    // Fetch customers to map customerId to name
    final customersRes = await _customerRepo.getCustomers();
    final customerMap = <String, String>{};
    customersRes.fold(
      (_) => null,
      (customers) {
        for (final c in customers) {
          customerMap[c.id] = c.name;
        }
      },
    );

    final contractsRes = await _facade.listContracts();
    contractsRes.fold(
      (failure) => emit(state.copyWith(
        status: InstallmentsListStatus.error,
        errorMessage: failure.message,
      )),
      (contracts) {
        final filtered = _applyFilters(
          contracts,
          state.searchQuery,
          state.filter,
          customerMap,
        );
        emit(state.copyWith(
          status: InstallmentsListStatus.success,
          allContracts: contracts,
          contracts: filtered,
          customerNames: customerMap,
        ));
      },
    );
  }

  void setFilter(String status) {
    final filtered = _applyFilters(
      state.allContracts,
      state.searchQuery,
      status,
      state.customerNames,
    );
    emit(state.copyWith(filter: status, contracts: filtered));
  }

  void setSearchQuery(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      final filtered = _applyFilters(
        state.allContracts,
        query,
        state.filter,
        state.customerNames,
      );
      emit(state.copyWith(searchQuery: query, contracts: filtered));
    });
  }

  List<CustomerInstallmentEntity> _applyFilters(
    List<CustomerInstallmentEntity> list,
    String query,
    String filter,
    Map<String, String> names,
  ) {
    var result = list;
    final now = DateTime.now();

    // 1. Status Filter
    if (filter != 'all') {
      result = result.where((c) {
        final computed = c.statusAt(now);
        return computed == filter;
      }).toList();
    }

    // 2. Search Query (Customer name or contract ID)
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((c) {
        final name = (names[c.customerId] ?? '').toLowerCase();
        final id = c.id.toLowerCase();
        return name.contains(q) || id.contains(q);
      }).toList();
    }

    return result;
  }
}

