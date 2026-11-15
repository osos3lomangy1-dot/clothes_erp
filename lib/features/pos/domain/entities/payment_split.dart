class PaymentSplit {
  final String method; // 'cash' | 'card'
  final int amountPiasters;

  const PaymentSplit({
    required this.method,
    required this.amountPiasters,
  });

  Map<String, dynamic> toJson() => {
        'method': method,
        'amountPiasters': amountPiasters,
      };

  factory PaymentSplit.fromJson(Map<String, dynamic> json) => PaymentSplit(
        method: json['method'] as String,
        amountPiasters: json['amountPiasters'] as int,
      );
}

class PaymentRefund {
  final String salePaymentId;
  final String method; // original or override
  final int amountPiasters;

  const PaymentRefund({
    required this.salePaymentId,
    required this.method,
    required this.amountPiasters,
  });

  Map<String, dynamic> toJson() => {
        'salePaymentId': salePaymentId,
        'method': method,
        'amountPiasters': amountPiasters,
      };

  factory PaymentRefund.fromJson(Map<String, dynamic> json) => PaymentRefund(
        salePaymentId: json['salePaymentId'] as String,
        method: json['method'] as String,
        amountPiasters: json['amountPiasters'] as int,
      );
}

