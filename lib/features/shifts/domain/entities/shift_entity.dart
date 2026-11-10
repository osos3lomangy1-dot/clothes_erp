import 'package:equatable/equatable.dart';

class ShiftEntity extends Equatable {
  final String id;
  final String branchId;
  final String cashierId;
  final String cashierName;
  final int openingBalance; // in piasters
  final DateTime openedAt;
  final DateTime? closedAt;
  final int? expectedBalance; // in piasters
  final int? countedBalance; // in piasters
  final int? difference; // in piasters (counted - expected)
  final DateTime createdAt;
  final DateTime updatedAt;

  const ShiftEntity({
    required this.id,
    required this.branchId,
    required this.cashierId,
    this.cashierName = '',
    required this.openingBalance,
    required this.openedAt,
    this.closedAt,
    this.expectedBalance,
    this.countedBalance,
    this.difference,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isOpen => closedAt == null;

  @override
  List<Object?> get props => [
        id,
        branchId,
        cashierId,
        cashierName,
        openingBalance,
        openedAt,
        closedAt,
        expectedBalance,
        countedBalance,
        difference,
        createdAt,
        updatedAt,
      ];
}

