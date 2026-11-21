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
  final String filter; // 'all', 'active', 'completed', 'overdue', 'legal_case', 'cancelled'
  final String dateFilter; // 'all_dates', 'today', 'this_week', 'this_month', 'custom'
  final DateTime? customFromDate;
  final DateTime? customToDate;
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
    this.dateFilter = 'all_dates',
    this.customFromDate,
    this.customToDate,
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
    String? dateFilter,
    DateTime? customFromDate,
    DateTime? customToDate,
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
      dateFilter: dateFilter ?? this.dateFilter,
      customFromDate: customFromDate ?? this.customFromDate,
      customToDate: customToDate ?? this.customToDate,
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
        dateFilter,
        customFromDate,
        customToDate,
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
    final groupedRes = await _facade.getGroupedByCustomer(
      now: now,
      includeInactive: true,
    );
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
          state.dateFilter,
          state.customFromDate,
          state.customToDate,
          customerMap,
        );
        final filteredGroups = _applyGroupFilters(
          groups,
          state.searchQuery,
          state.filter,
          state.dateFilter,
          state.customFromDate,
          state.customToDate,
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
      state.dateFilter,
      state.customFromDate,
      state.customToDate,
      state.customerNames,
    );
    final filteredGroups = _applyGroupFilters(
      state.allGrouped,
      state.searchQuery,
      status,
      state.dateFilter,
      state.customFromDate,
      state.customToDate,
    );
    emit(state.copyWith(
      filter: status,
      contracts: filteredContracts,
      groupedByCustomer: filteredGroups,
    ));
  }

  void setDateFilter(String dateFilter, {DateTime? customFrom, DateTime? customTo}) {
    final from = customFrom ?? (dateFilter == 'all_dates' ? null : state.customFromDate);
    final to = customTo ?? (dateFilter == 'all_dates' ? null : state.customToDate);
    final filteredContracts = _applyFilters(
      state.allContracts,
      state.searchQuery,
      state.filter,
      dateFilter,
      from,
      to,
      state.customerNames,
    );
    final filteredGroups = _applyGroupFilters(
      state.allGrouped,
      state.searchQuery,
      state.filter,
      dateFilter,
      from,
      to,
    );
    emit(state.copyWith(
      dateFilter: dateFilter,
      customFromDate: from,
      customToDate: to,
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
        state.dateFilter,
        state.customFromDate,
        state.customToDate,
        state.customerNames,
      );
      final filteredGroups = _applyGroupFilters(
        state.allGrouped,
        query,
        state.filter,
        state.dateFilter,
        state.customFromDate,
        state.customToDate,
      );
      emit(state.copyWith(
        searchQuery: query,
        contracts: filteredContracts,
        groupedByCustomer: filteredGroups,
      ));
    });
  }

  static bool _matchesDateFilter(
    CustomerInstallmentEntity c,
    String dateFilter,
    DateTime now, {
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    if (dateFilter == 'all_dates') return true;
    final due = c.nextDueDate;
    if (due == null) return false;

    final dueDateOnly = DateTime(due.year, due.month, due.day);
    final today = DateTime(now.year, now.month, now.day);

    switch (dateFilter) {
      case 'today':
        return dueDateOnly.isAtSameMomentAs(today);

      case 'this_week':
        // Include any contract due this current calendar week or next 7 days
        final daysFromSat = (now.weekday == DateTime.saturday) ? 0 : (now.weekday % 7) + 1;
        final startOfWeek = today.subtract(Duration(days: daysFromSat));
        final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
        final next7Days = today.add(const Duration(days: 7, hours: 23, minutes: 59, seconds: 59));
        final weekEnd = endOfWeek.isAfter(next7Days) ? endOfWeek : next7Days;
        return !due.isBefore(startOfWeek) && !due.isAfter(weekEnd);

      case 'this_month':
        final isSameMonth = due.year == now.year && due.month == now.month;
        final next30Days = today.add(const Duration(days: 30, hours: 23, minutes: 59, seconds: 59));
        return isSameMonth || (!due.isBefore(today) && !due.isAfter(next30Days));

      case 'custom':
        if (customFrom != null && customTo != null) {
          final from = DateTime(customFrom.year, customFrom.month, customFrom.day);
          final to = DateTime(customTo.year, customTo.month, customTo.day, 23, 59, 59);
          return !due.isBefore(from) && !due.isAfter(to);
        }
        return true;

      default:
        return true;
    }
  }

  List<CustomerInstallmentEntity> _applyFilters(
    List<CustomerInstallmentEntity> list,
    String query,
    String filter,
    String dateFilter,
    DateTime? customFrom,
    DateTime? customTo,
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

    // 2. Date Filter
    if (dateFilter != 'all_dates') {
      result = result.where((c) {
        return _matchesDateFilter(
          c,
          dateFilter,
          now,
          customFrom: customFrom,
          customTo: customTo,
        );
      }).toList();
    }

    // 3. Search Query (Customer name or contract ID)
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
    String dateFilter,
    DateTime? customFrom,
    DateTime? customTo,
  ) {
    var result = list;
    final now = DateTime.now();

    // 1. Status Filter
    if (filter != 'all') {
      result = result.where((summary) {
        return summary.contracts.any((c) => c.statusAt(now) == filter);
      }).toList();
    }

    // 2. Date Filter
    if (dateFilter != 'all_dates') {
      result = result.where((summary) {
        return summary.contracts.any((c) => _matchesDateFilter(
          c,
          dateFilter,
          now,
          customFrom: customFrom,
          customTo: customTo,
        ));
      }).toList();
    }

    // 3. Search Query (Customer name or customer ID or contract ID)
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
