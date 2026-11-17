import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../domain/entities/bulk_installment_payment_result.dart';
import '../../domain/entities/customer_installment_entity.dart';
import '../../domain/entities/customer_installments_summary.dart';
import '../../domain/facades/installments_facade.dart';

enum InstallmentsListStatus { initial, loading, success, error }

class InstallmentsListState extends Equatable {
  final InstallmentsListStatus status;
  final List<CustomerInstallmentEntity> allContracts;
  final List<CustomerInstallmentEntity> contracts;
  final List<CustomerInstallmentsSummary> allGrouped;
  final List<CustomerInstallmentsSummary> groupedByCustomer;
  final Map<String, String> customerNames;
  final String filter; // 'all', 'active', 'completed', 'overdue', 'cancelled'
  final String searchQuery;
  final String? errorMessage;

  const InstallmentsListState({
    this.status = InstallmentsListStatus.initial,
    this.allContracts = const [],
    this.contracts = const [],
    this.allGrouped = const [],
    this.groupedByCustomer = const [],
    this.customerNames = const {},
    this.filter = 'all',
    this.searchQuery = '',
    this.errorMessage,
  });

  InstallmentsListState copyWith({
    InstallmentsListStatus? status,
    List<CustomerInstallmentEntity>? allContracts,
    List<CustomerInstallmentEntity>? contracts,
    List<CustomerInstallmentsSummary>? allGrouped,
    List<CustomerInstallmentsSummary>? groupedByCustomer,
    Map<String, String>? customerNames,
    String? filter,
    String? searchQuery,
    String? errorMessage,
  }) {
    return InstallmentsListState(
      status: status ?? this.status,
      allContracts: allContracts ?? this.allContracts,
      contracts: contracts ?? this.contracts,
      allGrouped: allGrouped ?? this.allGrouped,
      groupedByCustomer: groupedByCustomer ?? this.groupedByCustomer,
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
        allGrouped,
        groupedByCustomer,
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

    final now = DateTime.now();
    final groupedRes = await _facade.getGroupedByCustomer(now: now);
    final groups = groupedRes.getOrElse(() => []);

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
        final filteredContracts = _applyFilters(
          contracts,
          state.searchQuery,
          state.filter,
          customerMap,
        );
        final filteredGroups = _applyGroupFilters(
          groups,
          state.searchQuery,
          state.filter,
        );
        emit(state.copyWith(
          status: InstallmentsListStatus.success,
          allContracts: contracts,
          contracts: filteredContracts,
          allGrouped: groups,
          groupedByCustomer: filteredGroups,
          customerNames: customerMap,
        ));
      },
    );
  }

  Future<void> loadGrouped() async {
    await loadContracts();
  }

  Future<Either<Failure, BulkInstallmentPaymentResult>> recordBulkCustomerPayment({
    required String customerId,
    required int amountPiasters,
    required String paymentMethod,
    required String pin,
    String? notes,
  }) async {
    final res = await _facade.recordBulkCustomerPayment(
      customerId: customerId,
      amountPiasters: amountPiasters,
      paymentMethod: paymentMethod,
      pin: pin,
      notes: notes,
    );
    if (res.isRight()) {
      await loadContracts();
    }
    return res;
  }

  void setFilter(String status) {
    final filteredContracts = _applyFilters(
      state.allContracts,
      state.searchQuery,
      status,
      state.customerNames,
    );
    final filteredGroups = _applyGroupFilters(
      state.allGrouped,
      state.searchQuery,
      status,
    );
    emit(state.copyWith(
      filter: status,
      contracts: filteredContracts,
      groupedByCustomer: filteredGroups,
    ));
  }

  void setSearchQuery(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      final filteredContracts = _applyFilters(
        state.allContracts,
        query,
        state.filter,
        state.customerNames,
      );
      final filteredGroups = _applyGroupFilters(
        state.allGrouped,
        query,
        state.filter,
      );
      emit(state.copyWith(
        searchQuery: query,
        contracts: filteredContracts,
        groupedByCustomer: filteredGroups,
      ));
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

  List<CustomerInstallmentsSummary> _applyGroupFilters(
    List<CustomerInstallmentsSummary> list,
    String query,
    String filter,
  ) {
    var result = list;
    final now = DateTime.now();

    // 1. Status Filter
    if (filter != 'all') {
      result = result.where((summary) {
        return summary.contracts.any((c) => c.statusAt(now) == filter);
      }).toList();
    }

    // 2. Search Query (Customer name or customer ID or contract ID)
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((summary) {
        final name = summary.customerName.toLowerCase();
        final id = summary.customerId.toLowerCase();
        final matchesContractId =
            summary.contracts.any((c) => c.id.toLowerCase().contains(q));
        return name.contains(q) || id.contains(q) || matchesContractId;
      }).toList();
    }

    return result;
  }
}
