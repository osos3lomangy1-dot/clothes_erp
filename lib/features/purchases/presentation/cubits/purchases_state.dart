import 'package:equatable/equatable.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/entities/purchase_return_entity.dart';

enum PurchasesStatus { initial, loading, loaded, error }

class PurchasesState extends Equatable {
  final PurchasesStatus status;
  final List<PurchaseEntity> purchases;
  final List<PurchaseReturnEntity> returns;
  final String? errorMessage;
  final String? selectedSupplierId;
  final String? selectedPaymentStatus;

  const PurchasesState({
    this.status = PurchasesStatus.initial,
    this.purchases = const [],
    this.returns = const [],
    this.errorMessage,
    this.selectedSupplierId,
    this.selectedPaymentStatus,
  });

  int get totalPurchasesAmount => purchases.fold(0, (sum, p) => sum + p.totalAmount);
  int get totalPaidAmount => purchases.fold(0, (sum, p) => sum + p.paidAmount);
  int get totalRemainingDebt => purchases.fold(0, (sum, p) => sum + p.remainingAmount);
  int get totalReturnsAmount => returns.fold(0, (sum, r) => sum + r.totalAmount);

  PurchasesState copyWith({
    PurchasesStatus? status,
    List<PurchaseEntity>? purchases,
    List<PurchaseReturnEntity>? returns,
    String? errorMessage,
    String? selectedSupplierId,
    String? selectedPaymentStatus,
  }) {
    return PurchasesState(
      status: status ?? this.status,
      purchases: purchases ?? this.purchases,
      returns: returns ?? this.returns,
      errorMessage: errorMessage,
      selectedSupplierId: selectedSupplierId ?? this.selectedSupplierId,
      selectedPaymentStatus: selectedPaymentStatus ?? this.selectedPaymentStatus,
    );
  }

  @override
  List<Object?> get props => [
        status,
        purchases,
        returns,
        errorMessage,
        selectedSupplierId,
        selectedPaymentStatus,
      ];
}
