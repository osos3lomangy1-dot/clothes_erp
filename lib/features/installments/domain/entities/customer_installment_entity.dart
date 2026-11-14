import 'package:equatable/equatable.dart';

class CustomerInstallmentEntity extends Equatable {
  final String id;
  final String branchId;
  final String saleId;
  final String customerId;
  final String? planId;
  final int totalPiasters;
  final int downPaymentPiasters;
  final int principalPiasters;
  final int interestBp;
  final int monthlyAmountPiasters;
  final int remainingPiasters;
  final int durationMonths;
  final DateTime startDate;
  final DateTime endDate;
  final String status;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const CustomerInstallmentEntity({
    required this.id,
    required this.branchId,
    required this.saleId,
    required this.customerId,
    this.planId,
    required this.totalPiasters,
    required this.downPaymentPiasters,
    required this.principalPiasters,
    required this.interestBp,
    required this.monthlyAmountPiasters,
    required this.remainingPiasters,
    required this.durationMonths,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  String statusAt(DateTime now) {
    if (status == 'completed' || status == 'cancelled') return status;
    if (remainingPiasters <= 0) return 'completed';
    if (now.isAfter(endDate)) return 'overdue';
    return 'active';
  }

  @override
  List<Object?> get props => [id, branchId, saleId, customerId, planId, totalPiasters, downPaymentPiasters, principalPiasters, interestBp, monthlyAmountPiasters, remainingPiasters, durationMonths, startDate, endDate, status, createdBy, createdAt, updatedAt, deletedAt];
}
