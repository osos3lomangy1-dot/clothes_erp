class PreOrderPaymentEntity {
  final String id;
  final String preOrderId;
  final String branchId;
  final String? shiftId;
  final String? cashierId;
  final int amountPiasters;
  final String paymentMethod; // 'cash', 'instapay', 'vodafone_cash', 'card', 'transfer'
  final String? notes;
  final DateTime createdAt;

  const PreOrderPaymentEntity({
    required this.id,
    required this.preOrderId,
    required this.branchId,
    this.shiftId,
    this.cashierId,
    required this.amountPiasters,
    this.paymentMethod = 'cash',
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pre_order_id': preOrderId,
      'branch_id': branchId,
      'shift_id': shiftId,
      'cashier_id': cashierId,
      'amount_piasters': amountPiasters,
      'payment_method': paymentMethod,
      'notes': notes,
      'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
    };
  }

  factory PreOrderPaymentEntity.fromMap(Map<String, dynamic> map) {
    return PreOrderPaymentEntity(
      id: map['id'] as String,
      preOrderId: map['pre_order_id'] as String,
      branchId: map['branch_id'] as String,
      shiftId: map['shift_id'] as String?,
      cashierId: map['cashier_id'] as String?,
      amountPiasters: (map['amount_piasters'] as num?)?.toInt() ?? 0,
      paymentMethod: map['payment_method'] as String? ?? 'cash',
      notes: map['notes'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        ((map['created_at'] as num?)?.toInt() ?? 0) * 1000,
      ),
    );
  }
}

