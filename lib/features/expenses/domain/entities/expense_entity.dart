import 'package:equatable/equatable.dart';

class ExpenseKind {
  static const String operating = 'operating';
  static const String supplierPayment = 'supplier_payment';
}

class ExpenseEntity extends Equatable {
  final String id;
  final String branchId;
  final String category;
  final int amount; // in piasters
  final String kind;
  final String? note;
  final String userId;
  final DateTime expenseDate;
  final DateTime createdAt;

  const ExpenseEntity({
    required this.id,
    required this.branchId,
    required this.category,
    required this.amount,
    this.kind = ExpenseKind.operating,
    this.note,
    required this.userId,
    required this.expenseDate,
    required this.createdAt,
  });

  double get amountPounds => amount / 100.0;

  String get formattedAmount => '${amountPounds.toStringAsFixed(2)} ج.م';

  ExpenseEntity copyWith({
    String? id,
    String? branchId,
    String? category,
    int? amount,
    String? kind,
    String? note,
    String? userId,
    DateTime? expenseDate,
    DateTime? createdAt,
  }) {
    return ExpenseEntity(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      kind: kind ?? this.kind,
      note: note ?? this.note,
      userId: userId ?? this.userId,
      expenseDate: expenseDate ?? this.expenseDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        branchId,
        category,
        amount,
        kind,
        note,
        userId,
        expenseDate,
        createdAt,
      ];
}
