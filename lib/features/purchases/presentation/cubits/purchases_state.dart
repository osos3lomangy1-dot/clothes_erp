import 'package:equatable/equatable.dart';
import '../../domain/entities/purchase_entity.dart';

enum PurchasesStatus { initial, loading, loaded, error }

class PurchasesState extends Equatable {
  final PurchasesStatus status;
  final List<PurchaseEntity> purchases;
  final String? errorMessage;
  final String? selectedSupplierId;
  final String? selectedPaymentStatus;

  const PurchasesState({
    this.status = PurchasesStatus.initial,
    this.purchases = const [],
    this.errorMessage,
    this.selectedSupplierId,
    this.selectedPaymentStatus,
  });

  int get totalPurchasesAmount => purchases.fold(0, (sum, p) => sum + p.totalAmount);
  int get totalPaidAmount => purchases.fold(0, (sum, p) => sum + p.paidAmount);
  int get totalRemainingDebt => purchases.fold(0, (sum, p) => sum + p.remainingAmount);

  PurchasesState copyWith({
    PurchasesStatus? status,
    List<PurchaseEntity>? purchases,
    String? errorMessage,
    String? selectedSupplierId,
    String? selectedPaymentStatus,
  }) {
    return PurchasesState(
      status: status ?? this.status,
      purchases: purchases ?? this.purchases,
      errorMessage: errorMessage,
      selectedSupplierId: selectedSupplierId ?? this.selectedSupplierId,
      selectedPaymentStatus: selectedPaymentStatus ?? this.selectedPaymentStatus,
    );
  }

  @override
  List<Object?> get props => [
        status,
        purchases,
        errorMessage,
        selectedSupplierId,
        selectedPaymentStatus,
      ];
}

