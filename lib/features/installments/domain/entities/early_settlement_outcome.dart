import 'package:equatable/equatable.dart';
import 'installment_payment_entity.dart';

class EarlySettlementOutcome extends Equatable {
  final String contractId;
  final int settlementAmountPiasters;
  final int waivedInterestPiasters;
  final String paymentMethod;
  final DateTime settledAt;
  final InstallmentPaymentEntity? cashPayment;

  const EarlySettlementOutcome({
    required this.contractId,
    required this.settlementAmountPiasters,
    required this.waivedInterestPiasters,
    required this.paymentMethod,
    required this.settledAt,
    this.cashPayment,
  });

  @override
  List<Object?> get props => [
        contractId,
        settlementAmountPiasters,
        waivedInterestPiasters,
        paymentMethod,
        settledAt,
        cashPayment,
      ];
}

