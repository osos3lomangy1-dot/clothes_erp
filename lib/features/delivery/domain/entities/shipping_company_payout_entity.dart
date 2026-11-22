import 'package:equatable/equatable.dart';

class ShippingCompanyPayoutEntity extends Equatable {
  final String id;
  final String branchId;
  final String courierId;
  final int amountPiasters;
  final String paymentMethod; // 'bank_transfer', 'cash', 'cheque', 'vodafone_cash'
  final String? referenceNumber;
  final String? notes;
  final DateTime payoutDate;
  final DateTime createdAt;

  const ShippingCompanyPayoutEntity({
    required this.id,
    required this.branchId,
    required this.courierId,
    required this.amountPiasters,
    this.paymentMethod = 'bank_transfer',
    this.referenceNumber,
    this.notes,
    required this.payoutDate,
    required this.createdAt,
  });

  double get amount => amountPiasters / 100.0;

  @override
  List<Object?> get props => [
        id,
        branchId,
        courierId,
        amountPiasters,
        paymentMethod,
        referenceNumber,
        notes,
        payoutDate,
        createdAt,
      ];
}
