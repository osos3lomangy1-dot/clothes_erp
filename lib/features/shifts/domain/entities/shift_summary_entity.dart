import 'package:equatable/equatable.dart';
import 'shift_entity.dart';

class ShiftSummaryEntity extends Equatable {
  final ShiftEntity shift;
  final int cashSales; // in piasters
  final int cardSales; // in piasters
  final int otherSales; // in piasters
  final int cashReturns; // in piasters
  final int cashExpenses; // in piasters
  final int cashInstallments; // in piasters (collected in cash during this shift)
  final int cardInstallments; // in piasters (collected by card during this shift)
  final int totalSalesCount;
  final int expectedCashInDrawer; // in piasters: openingBalance + cashSales + cashInstallments - cashReturns - cashExpenses

  const ShiftSummaryEntity({
    required this.shift,
    required this.cashSales,
    required this.cardSales,
    required this.otherSales,
    required this.cashReturns,
    required this.cashExpenses,
    this.cashInstallments = 0,
    this.cardInstallments = 0,
    required this.totalSalesCount,
    required this.expectedCashInDrawer,
  });

  int get totalRevenue => cashSales + cardSales + otherSales;
  int get totalInstallments => cashInstallments + cardInstallments;

  @override
  List<Object?> get props => [
        shift,
        cashSales,
        cardSales,
        otherSales,
        cashReturns,
        cashExpenses,
        cashInstallments,
        cardInstallments,
        totalSalesCount,
        expectedCashInDrawer,
      ];
}

