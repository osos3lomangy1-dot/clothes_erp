import 'package:equatable/equatable.dart';

class SupplierPaymentEntity extends Equatable {
  final String id;
  final String branchId;
  final String supplierId;
  final String? supplierName;
  final String? purchaseId;
  final String? purchaseInvoiceNumber;
  final int amount; // in piasters
  final DateTime paymentDate;
  final String paymentMethod; // cash, bank, etc.
  final String? referenceNumber;
  final String? notes;
  final String createdBy;
  final DateTime createdAt;

  const SupplierPaymentEntity({
    required this.id,
    required this.branchId,
    required this.supplierId,
    this.supplierName,
    this.purchaseId,
    this.purchaseInvoiceNumber,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    this.referenceNumber,
    this.notes,
    required this.createdBy,
    required this.createdAt,
  });

  double get amountPounds => amount / 100.0;
  String get formattedAmount => '${amountPounds.toStringAsFixed(2)} ج.م';

  @override
  List<Object?> get props => [
        id,
        branchId,
        supplierId,
        supplierName,
        purchaseId,
        purchaseInvoiceNumber,
        amount,
        paymentDate,
        paymentMethod,
        referenceNumber,
        notes,
        createdBy,
        createdAt,
      ];
}

