import 'package:equatable/equatable.dart';
import 'shift_entity.dart';

class ShiftSummaryEntity extends Equatable {
  final ShiftEntity shift;
  final int cashSales; // in piasters
  final int cardSales; // in piasters
  final int otherSales; // in piasters
  final int cashReturns; // in piasters
  final int cashExpenses; // in piasters
  final int totalSalesCount;
  final int expectedCashInDrawer; // in piasters: openingBalance + cashSales - cashReturns - cashExpenses

  const ShiftSummaryEntity({
    required this.shift,
    required this.cashSales,
    required this.cardSales,
    required this.otherSales,
    required this.cashReturns,
    required this.cashExpenses,
    required this.totalSalesCount,
    required this.expectedCashInDrawer,
  });

  int get totalRevenue => cashSales + cardSales + otherSales;

  @override
  List<Object?> get props => [
        shift,
        cashSales,
        cardSales,
        otherSales,
        cashReturns,
        cashExpenses,
        totalSalesCount,
        expectedCashInDrawer,
      ];
}

