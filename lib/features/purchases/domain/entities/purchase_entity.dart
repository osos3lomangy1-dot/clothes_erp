import 'package:equatable/equatable.dart';
import 'purchase_item_entity.dart';

class PurchaseEntity extends Equatable {
  final String id;
  final String branchId;
  final String supplierId;
  final String? supplierName;
  final String? invoiceNumber;
  final DateTime purchaseDate;
  final int totalAmount; // in piasters
  final int paidAmount; // in piasters
  final String status; // pending, received, cancelled
  final String paymentStatus; // unpaid, partial, paid
  final String? notes;
  final List<PurchaseItemEntity> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const PurchaseEntity({
    required this.id,
    required this.branchId,
    required this.supplierId,
    this.supplierName,
    this.invoiceNumber,
    required this.purchaseDate,
    required this.totalAmount,
    required this.paidAmount,
    required this.status,
    required this.paymentStatus,
    this.notes,
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  int get remainingAmount => totalAmount - paidAmount;
  double get totalAmountPounds => totalAmount / 100.0;
  double get paidAmountPounds => paidAmount / 100.0;
  double get remainingAmountPounds => remainingAmount / 100.0;

  String get formattedTotalAmount => '${totalAmountPounds.toStringAsFixed(2)} ج.م';
  String get formattedPaidAmount => '${paidAmountPounds.toStringAsFixed(2)} ج.م';
  String get formattedRemainingAmount => '${remainingAmountPounds.toStringAsFixed(2)} ج.م';

  @override
  List<Object?> get props => [
        id,
        branchId,
        supplierId,
        supplierName,
        invoiceNumber,
        purchaseDate,
        totalAmount,
        paidAmount,
        status,
        paymentStatus,
        notes,
        items,
        createdAt,
        updatedAt,
        deletedAt,
      ];
}

