import 'package:equatable/equatable.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import 'employee_entity.dart';

enum PayrollSalaryStatus {
  notSet, // لم يُحدد الراتب الأساسي
  notPaid, // لم يُصرف راتب هذا الشهر
  partiallyPaid, // تم صرف جزء من الراتب
  fullyPaid, // تم صرف الراتب بالكامل
}

class EmployeePayrollSummary extends Equatable {
  final EmployeeEntity employee;
  final int basicSalary; // in piasters (e.g. 500000 = 5000 EGP)
  final int salaryPaidThisMonth; // in piasters
  final int bonusThisMonth; // in piasters (مكافآت وبونص)
  final int advancesThisMonth; // in piasters (سلف وخصومات)
  final DateTime monthDate;
  final List<ExpenseEntity> transactions; // related financial entries this month
  final bool hasActiveShift;
  final DateTime? shiftOpenedAt;
  final int? shiftOpeningBalance;

  const EmployeePayrollSummary({
    required this.employee,
    required this.basicSalary,
    required this.salaryPaidThisMonth,
    required this.bonusThisMonth,
    required this.advancesThisMonth,
    required this.monthDate,
    this.transactions = const [],
    this.hasActiveShift = false,
    this.shiftOpenedAt,
    this.shiftOpeningBalance,
  });

  /// Net balance due to the employee for this month:
  /// (Basic Salary - Already Paid) + Bonuses - Advances
  int get netDue {
    final remainingSalary = basicSalary > salaryPaidThisMonth
        ? (basicSalary - salaryPaidThisMonth)
        : 0;
    return remainingSalary + bonusThisMonth - advancesThisMonth;
  }

  /// Remaining unpaid portion of basic salary
  int get remainingSalary {
    if (basicSalary <= 0) return 0;
    final diff = basicSalary - salaryPaidThisMonth;
    return diff > 0 ? diff : 0;
  }

  PayrollSalaryStatus get salaryStatus {
    if (basicSalary <= 0) return PayrollSalaryStatus.notSet;
    if (salaryPaidThisMonth <= 0) return PayrollSalaryStatus.notPaid;
    if (salaryPaidThisMonth < basicSalary) return PayrollSalaryStatus.partiallyPaid;
    return PayrollSalaryStatus.fullyPaid;
  }

  String get salaryStatusArabic {
    switch (salaryStatus) {
      case PayrollSalaryStatus.notSet:
        return 'غير محدد';
      case PayrollSalaryStatus.notPaid:
        return 'لم يُصرف بعد';
      case PayrollSalaryStatus.partiallyPaid:
        return 'مستلم جزئياً';
      case PayrollSalaryStatus.fullyPaid:
        return 'تم الصرف بالكامل';
    }
  }

  String get monthArabicName {
    const months = [
      '',
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    final m = monthDate.month;
    final name = (m >= 1 && m <= 12) ? months[m] : '';
    return '$name ${monthDate.year}';
  }

  @override
  List<Object?> get props => [
        employee,
        basicSalary,
        salaryPaidThisMonth,
        bonusThisMonth,
        advancesThisMonth,
        monthDate,
        transactions,
        hasActiveShift,
        shiftOpenedAt,
        shiftOpeningBalance,
      ];
}
