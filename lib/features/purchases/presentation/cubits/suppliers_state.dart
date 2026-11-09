import 'package:equatable/equatable.dart';
import '../../domain/entities/supplier_entity.dart';
import '../../domain/entities/supplier_payment_entity.dart';

enum SuppliersStatus { initial, loading, loaded, error }

class SuppliersState extends Equatable {
  final SuppliersStatus status;
  final List<SupplierEntity> suppliers;
  final List<SupplierPaymentEntity> payments;
  final String? errorMessage;
  final String? searchQuery;

  const SuppliersState({
    this.status = SuppliersStatus.initial,
    this.suppliers = const [],
    this.payments = const [],
    this.errorMessage,
    this.searchQuery,
  });

  int get totalSuppliersDebt => suppliers.fold(0, (sum, s) => sum + s.balance);

  List<SupplierEntity> get filteredSuppliers {
    if (searchQuery == null || searchQuery!.trim().isEmpty) {
      return suppliers;
    }
    final q = searchQuery!.toLowerCase().trim();
    return suppliers.where((s) {
      return s.name.toLowerCase().contains(q) ||
          (s.phone != null && s.phone!.contains(q)) ||
          (s.companyName != null && s.companyName!.toLowerCase().contains(q));
    }).toList();
  }

  SuppliersState copyWith({
    SuppliersStatus? status,
    List<SupplierEntity>? suppliers,
    List<SupplierPaymentEntity>? payments,
    String? errorMessage,
    String? searchQuery,
  }) {
    return SuppliersState(
      status: status ?? this.status,
      suppliers: suppliers ?? this.suppliers,
      payments: payments ?? this.payments,
      errorMessage: errorMessage,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [
        status,
        suppliers,
        payments,
        errorMessage,
        searchQuery,
      ];
}

