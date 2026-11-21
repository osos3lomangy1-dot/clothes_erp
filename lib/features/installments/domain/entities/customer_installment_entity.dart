import 'package:equatable/equatable.dart';

import '../services/installment_calculator.dart';

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
  final bool promissoryNoteDelivered;
  final DateTime? promissoryNoteDeliveredAt;
  final bool hasPromissoryNote;

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
    this.promissoryNoteDelivered = false,
    this.promissoryNoteDeliveredAt,
    this.hasPromissoryNote = true,
  });

  String statusAt(DateTime now) {
    if (status == 'completed' || status == 'cancelled') return status;
    if (status == 'written_off' || status == 'cancelled_bad_debt') return status;
    if (remainingPiasters <= 0) return 'completed';
    if (status == 'legal_case') return status;
    if (now.isAfter(endDate)) return 'overdue';
    return 'active';
  }

  /// Calculates the due date of the next pending installment schedule item.
  DateTime? get nextDueDate {
    if (remainingPiasters <= 0) return null;
    if (status == 'completed' || status == 'cancelled') return null;
    if (monthlyAmountPiasters <= 0) return endDate;
    final paidPiasters = totalPiasters - remainingPiasters;
    final paidCount = (paidPiasters > 0) ? (paidPiasters ~/ monthlyAmountPiasters) : 0;
    final nextMonthIndex = (paidCount + 1).clamp(1, durationMonths);
    return InstallmentCalculator.addMonths(startDate, nextMonthIndex);
  }

  CustomerInstallmentEntity copyWith({
    String? id,
    String? branchId,
    String? saleId,
    String? customerId,
    String? planId,
    int? totalPiasters,
    int? downPaymentPiasters,
    int? principalPiasters,
    int? interestBp,
    int? monthlyAmountPiasters,
    int? remainingPiasters,
    int? durationMonths,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool? promissoryNoteDelivered,
    DateTime? promissoryNoteDeliveredAt,
    bool? hasPromissoryNote,
  }) {
    return CustomerInstallmentEntity(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      saleId: saleId ?? this.saleId,
      customerId: customerId ?? this.customerId,
      planId: planId ?? this.planId,
      totalPiasters: totalPiasters ?? this.totalPiasters,
      downPaymentPiasters: downPaymentPiasters ?? this.downPaymentPiasters,
      principalPiasters: principalPiasters ?? this.principalPiasters,
      interestBp: interestBp ?? this.interestBp,
      monthlyAmountPiasters: monthlyAmountPiasters ?? this.monthlyAmountPiasters,
      remainingPiasters: remainingPiasters ?? this.remainingPiasters,
      durationMonths: durationMonths ?? this.durationMonths,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      promissoryNoteDelivered: promissoryNoteDelivered ?? this.promissoryNoteDelivered,
      promissoryNoteDeliveredAt: promissoryNoteDeliveredAt ?? this.promissoryNoteDeliveredAt,
      hasPromissoryNote: hasPromissoryNote ?? this.hasPromissoryNote,
    );
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        saleId,
        customerId,
        planId,
        totalPiasters,
        downPaymentPiasters,
        principalPiasters,
        interestBp,
        monthlyAmountPiasters,
        remainingPiasters,
        durationMonths,
        startDate,
        endDate,
        status,
        createdBy,
        createdAt,
        updatedAt,
        deletedAt,
        promissoryNoteDelivered,
        promissoryNoteDeliveredAt,
        hasPromissoryNote,
      ];
}
