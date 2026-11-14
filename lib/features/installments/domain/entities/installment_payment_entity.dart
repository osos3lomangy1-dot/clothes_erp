import 'package:equatable/equatable.dart';

class InstallmentPaymentEntity extends Equatable {
  final String id;
  final String branchId;
  final String customerInstallmentId;
  final int amountPiasters;
  final String paymentMethod;
  final DateTime paidAt;
  final String? receiptNumber;
  final String? notes;
  final String recordedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const InstallmentPaymentEntity({
    required this.id,
    required this.branchId,
    required this.customerInstallmentId,
    required this.amountPiasters,
    required this.paymentMethod,
    required this.paidAt,
    this.receiptNumber,
    this.notes,
    required this.recordedBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  List<Object?> get props => [id, branchId, customerInstallmentId, amountPiasters, paymentMethod, paidAt, receiptNumber, notes, recordedBy, createdAt, updatedAt, deletedAt];
}
