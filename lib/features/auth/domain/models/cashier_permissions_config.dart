import 'dart:convert';

/// Configuration for Cashier permissions controlled by Manager/Admin
class CashierPermissionsConfig {
  /// Allow cashier to process credit sales (on-account / deferred payment)
  final bool allowCreditSale;

  /// Allow cashier to initiate and process installment sales
  final bool allowInstallments;

  /// Allow cashier to receive incoming goods shipments into inventory
  final bool allowGoodsIntake;

  /// Allow cashier to add and edit customer records
  final bool allowManageCustomers;

  /// Allow cashier to record minor petty cash expenses from drawer
  final bool allowCashExpenses;

  /// Allow cashier to view global invoice history beyond current shift
  final bool allowViewInvoicesHistory;

  /// Allow cashier to apply exceptional manual discounts on POS
  final bool allowManualDiscount;

  const CashierPermissionsConfig({
    this.allowCreditSale = false,
    this.allowInstallments = false,
    this.allowGoodsIntake = false,
    this.allowManageCustomers = true,
    this.allowCashExpenses = false,
    this.allowViewInvoicesHistory = false,
    this.allowManualDiscount = false,
  });

  CashierPermissionsConfig copyWith({
    bool? allowCreditSale,
    bool? allowInstallments,
    bool? allowGoodsIntake,
    bool? allowManageCustomers,
    bool? allowCashExpenses,
    bool? allowViewInvoicesHistory,
    bool? allowManualDiscount,
  }) {
    return CashierPermissionsConfig(
      allowCreditSale: allowCreditSale ?? this.allowCreditSale,
      allowInstallments: allowInstallments ?? this.allowInstallments,
      allowGoodsIntake: allowGoodsIntake ?? this.allowGoodsIntake,
      allowManageCustomers: allowManageCustomers ?? this.allowManageCustomers,
      allowCashExpenses: allowCashExpenses ?? this.allowCashExpenses,
      allowViewInvoicesHistory:
          allowViewInvoicesHistory ?? this.allowViewInvoicesHistory,
      allowManualDiscount: allowManualDiscount ?? this.allowManualDiscount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'allowCreditSale': allowCreditSale,
      'allowInstallments': allowInstallments,
      'allowGoodsIntake': allowGoodsIntake,
      'allowManageCustomers': allowManageCustomers,
      'allowCashExpenses': allowCashExpenses,
      'allowViewInvoicesHistory': allowViewInvoicesHistory,
      'allowManualDiscount': allowManualDiscount,
    };
  }

  factory CashierPermissionsConfig.fromMap(Map<String, dynamic> map) {
    return CashierPermissionsConfig(
      allowCreditSale: map['allowCreditSale'] as bool? ?? false,
      allowInstallments: map['allowInstallments'] as bool? ?? false,
      allowGoodsIntake: map['allowGoodsIntake'] as bool? ?? false,
      allowManageCustomers: map['allowManageCustomers'] as bool? ?? true,
      allowCashExpenses: map['allowCashExpenses'] as bool? ?? false,
      allowViewInvoicesHistory:
          map['allowViewInvoicesHistory'] as bool? ?? false,
      allowManualDiscount: map['allowManualDiscount'] as bool? ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory CashierPermissionsConfig.fromJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return CashierPermissionsConfig.fromMap(decoded);
      }
    } catch (_) {}
    return const CashierPermissionsConfig();
  }
}

