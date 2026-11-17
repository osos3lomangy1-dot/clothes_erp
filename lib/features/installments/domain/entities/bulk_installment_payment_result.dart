import 'package:equatable/equatable.dart';
import 'installment_payment_entity.dart';

class BulkInstallmentPaymentResult extends Equatable {
  final String customerId;
  final int totalAmountPiasters;
  final int affectedContractsCount;
  final List<InstallmentPaymentEntity> payments;

  const BulkInstallmentPaymentResult({
    required this.customerId,
    required this.totalAmountPiasters,
    required this.affectedContractsCount,
    required this.payments,
  });

  @override
  List<Object?> get props => [
        customerId,
        totalAmountPiasters,
        affectedContractsCount,
        payments,
      ];
}

