import 'package:equatable/equatable.dart';

class PartnerWithdrawal extends Equatable {
  final String id;
  final int amount; // in piasters
  final String type; // 'profit' (سحب أرباح) or 'capital' (استرداد جزء من رأس المال)
  final String? note;
  final DateTime date;

  const PartnerWithdrawal({
    required this.id,
    required this.amount,
    this.type = 'profit',
    this.note,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'type': type,
        'note': note,
        'date': date.toIso8601String(),
      };

  factory PartnerWithdrawal.fromJson(Map<String, dynamic> json) => PartnerWithdrawal(
        id: json['id'] as String,
        amount: (json['amount'] as num).toInt(),
        type: json['type'] as String? ?? 'profit',
        note: json['note'] as String?,
        date: DateTime.parse(json['date'] as String),
      );

  String get typeLabel {
    switch (type) {
      case 'advance':
        return 'سلفة شخصية مؤقتة';
      case 'deposit_refund':
        return 'استرداد تمويل شخصي من الجيب';
      case 'deposit_to_capital':
        return 'تحويل تمويل الجيب لرأس مال';
      case 'capital':
        return 'استرداد من رأس المال';
      case 'profit':
      default:
        return 'سحب أرباح';
    }
  }

  @override
  List<Object?> get props => [id, amount, type, note, date];
}

class PartnerDeposit extends Equatable {
  final String id;
  final int amount; // in piasters
  final String category; // 'goods' (تكملة بضاعة), 'expenses' (سداد مصروفات), 'cash' (سيولة بالخزينة)
  final String? note;
  final DateTime date;

  const PartnerDeposit({
    required this.id,
    required this.amount,
    this.category = 'goods',
    this.note,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'category': category,
        'note': note,
        'date': date.toIso8601String(),
      };

  factory PartnerDeposit.fromJson(Map<String, dynamic> json) => PartnerDeposit(
        id: json['id'] as String,
        amount: (json['amount'] as num).toInt(),
        category: json['category'] as String? ?? 'goods',
        note: json['note'] as String?,
        date: DateTime.parse(json['date'] as String),
      );

  String get categoryLabel {
    switch (category) {
      case 'advance_repayment':
        return 'رد سلفة شخصية مؤقتة';
      case 'goods':
        return 'تكملة / شراء بضاعة';
      case 'expenses':
        return 'سداد مصروفات أو إيجار';
      case 'cash':
      default:
        return 'سيولة نقدية في المحل';
    }
  }

  @override
  List<Object?> get props => [id, amount, category, note, date];
}

class PartnerEntity extends Equatable {
  final String id;
  final String name;
  final String? phone;
  final double percentage; // e.g. 60.0 for 60% profit share
  final double? capitalPercentage; // e.g. 50.0 for 50% capital/equity share
  final int capital; // in piasters
  final String partnershipType; // 'capital_only', 'effort_only', 'capital_and_effort'
  final String profitMode; // 'net_profit_share' (نسبة من صافي الربح), 'fixed_roi' (عائد سنوي محدد على رأس المال)
  final double roiPercentage; // e.g. 20.0 for 20% annual ROI
  final int monthlySalary; // in piasters (بدل أو راتب إدارة شهري إن وجد)
  final List<PartnerWithdrawal> withdrawals;
  final List<PartnerDeposit> deposits;
  final String? notes;
  final DateTime createdAt;

  const PartnerEntity({
    required this.id,
    required this.name,
    this.phone,
    required this.percentage,
    this.capitalPercentage,
    this.capital = 0,
    this.partnershipType = 'capital_and_effort',
    this.profitMode = 'net_profit_share',
    this.roiPercentage = 0.0,
    this.monthlySalary = 0,
    this.withdrawals = const [],
    this.deposits = const [],
    this.notes,
    required this.createdAt,
  });

  /// Effective capital / equity share percentage (falls back to profit percentage if not explicitly set)
  double get effectiveCapitalPercentage => capitalPercentage ?? percentage;

  /// Total temporary personal advances withdrawn by partner (سلف مؤقتة)
  int get totalAdvanceWithdrawn => withdrawals
      .where((w) => w.type == 'advance')
      .fold<int>(0, (sum, w) => sum + w.amount);

  /// Total temporary personal advances repaid by partner to store
  int get totalAdvanceRepaid => deposits
      .where((d) => d.category == 'advance_repayment')
      .fold<int>(0, (sum, d) => sum + d.amount);

  /// Remaining temporary advance currently owed by partner to store (مدين للمحل)
  int get remainingAdvance => (totalAdvanceWithdrawn - totalAdvanceRepaid).clamp(0, 100000000000);

  /// Total out-of-pocket funding / deposits contributed by the partner (e.g. for goods, liquidity)
  int get totalDeposited => deposits
      .where((d) => d.category != 'advance_repayment')
      .fold<int>(0, (sum, d) => sum + d.amount);

  /// Total personal deposits reimbursed or converted to capital
  int get totalDepositsRefunded => withdrawals
      .where((w) => w.type == 'deposit_refund' || w.type == 'deposit_to_capital')
      .fold<int>(0, (sum, w) => sum + w.amount);

  /// Remaining personal funding that the store owes to this partner (دائن للمحل)
  int get remainingDeposited => (totalDeposited - totalDepositsRefunded).clamp(0, 100000000000);

  /// Total profits withdrawn so far
  int get totalProfitWithdrawn => withdrawals
      .where((w) => w.type == 'profit')
      .fold<int>(0, (sum, w) => sum + w.amount);

  /// Total capital returned so far
  int get totalCapitalWithdrawn => withdrawals
      .where((w) => w.type == 'capital')
      .fold<int>(0, (sum, w) => sum + w.amount);

  /// Current remaining active capital in store
  int get currentCapital => (capital - totalCapitalWithdrawn).clamp(0, 100000000000);

  /// Total withdrawals across all types
  int get totalWithdrawn => withdrawals.fold<int>(0, (sum, w) => sum + w.amount);

  /// Unwithdrawn / retained profit remaining in store for a given earned profit
  int getUnwithdrawnProfit(int earnedProfit) {
    final remaining = earnedProfit - totalProfitWithdrawn;
    return remaining > 0 ? remaining : 0;
  }

  /// Total net financial balance/entitlement of the partner in the store
  int calculateNetBalance(int earnedProfit) {
    final positiveBalance = currentCapital + remainingDeposited + getUnwithdrawnProfit(earnedProfit);
    return positiveBalance - remainingAdvance;
  }

  /// Calculate profit share for a given net profit and period duration in days
  int calculateProfitShare(int netProfitPiasters, {int days = 30}) {
    if (profitMode == 'fixed_roi' && capital > 0 && roiPercentage > 0) {
      // Annual ROI prorated for the number of days (e.g. 30 days)
      final annualReturn = capital * (roiPercentage / 100.0);
      final prorated = annualReturn * (days / 365.0);
      return prorated.round();
    }

    // Default: Net Profit Share
    if (netProfitPiasters <= 0) return 0;
    return ((netProfitPiasters * percentage) / 100.0).round();
  }

  /// Label for partnership type in Arabic
  String get typeLabel {
    switch (partnershipType) {
      case 'capital_only':
        return 'شريك بالمال فقط (مموّل)';
      case 'effort_only':
        return 'شريك بالمجهود والإدارة';
      case 'capital_and_effort':
      default:
        return 'شريك بالمال والمجهود';
    }
  }

  /// Label for profit calculation mode in Arabic
  String get profitModeLabel {
    if (profitMode == 'fixed_roi') {
      return 'عائد استثماري (${roiPercentage.toStringAsFixed(1)}% سنوياً)';
    }
    return 'نسبة من صافي الأرباح (${percentage.toStringAsFixed(1)}%)';
  }

  PartnerEntity copyWith({
    String? id,
    String? name,
    String? phone,
    double? percentage,
    double? capitalPercentage,
    int? capital,
    String? partnershipType,
    String? profitMode,
    double? roiPercentage,
    int? monthlySalary,
    List<PartnerWithdrawal>? withdrawals,
    List<PartnerDeposit>? deposits,
    String? notes,
    DateTime? createdAt,
  }) {
    return PartnerEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      percentage: percentage ?? this.percentage,
      capitalPercentage: capitalPercentage ?? this.capitalPercentage,
      capital: capital ?? this.capital,
      partnershipType: partnershipType ?? this.partnershipType,
      profitMode: profitMode ?? this.profitMode,
      roiPercentage: roiPercentage ?? this.roiPercentage,
      monthlySalary: monthlySalary ?? this.monthlySalary,
      withdrawals: withdrawals ?? this.withdrawals,
      deposits: deposits ?? this.deposits,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'percentage': percentage,
        'capitalPercentage': capitalPercentage,
        'capital': capital,
        'partnershipType': partnershipType,
        'profitMode': profitMode,
        'roiPercentage': roiPercentage,
        'monthlySalary': monthlySalary,
        'withdrawals': withdrawals.map((w) => w.toJson()).toList(),
        'deposits': deposits.map((d) => d.toJson()).toList(),
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PartnerEntity.fromJson(Map<String, dynamic> json) => PartnerEntity(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
        capitalPercentage: (json['capitalPercentage'] as num?)?.toDouble(),
        capital: (json['capital'] as num?)?.toInt() ?? 0,
        partnershipType: json['partnershipType'] as String? ?? 'capital_and_effort',
        profitMode: json['profitMode'] as String? ?? 'net_profit_share',
        roiPercentage: (json['roiPercentage'] as num?)?.toDouble() ?? 0.0,
        monthlySalary: (json['monthlySalary'] as num?)?.toInt() ?? 0,
        withdrawals: (json['withdrawals'] as List<dynamic>?)
                ?.map((w) => PartnerWithdrawal.fromJson(w as Map<String, dynamic>))
                .toList() ??
            const [],
        deposits: (json['deposits'] as List<dynamic>?)
                ?.map((d) => PartnerDeposit.fromJson(d as Map<String, dynamic>))
                .toList() ??
            const [],
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        name,
        phone,
        percentage,
        capitalPercentage,
        capital,
        partnershipType,
        profitMode,
        roiPercentage,
        monthlySalary,
        withdrawals,
        deposits,
        notes,
        createdAt,
      ];
}
