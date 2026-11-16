import 'package:equatable/equatable.dart';
import 'customer_installment_entity.dart';

class CustomerInstallmentsSummary extends Equatable {
  final String customerId;
  final String customerName;
  final int contractsCount;
  final int totalRemainingPiasters;
  final int totalMonthlyAmountPiasters;
  final int currentMonthDuePiasters; // approximation: totalMonthlyAmountPiasters
  final List<CustomerInstallmentEntity> contracts;

  const CustomerInstallmentsSummary({
    required this.customerId,
    required this.customerName,
    required this.contractsCount,
    required this.totalRemainingPiasters,
    required this.totalMonthlyAmountPiasters,
    required this.currentMonthDuePiasters,
    required this.contracts,
  });

  @override
  List<Object?> get props => [
        customerId,
        customerName,
        contractsCount,
        totalRemainingPiasters,
        totalMonthlyAmountPiasters,
        currentMonthDuePiasters,
        contracts,
      ];
}

