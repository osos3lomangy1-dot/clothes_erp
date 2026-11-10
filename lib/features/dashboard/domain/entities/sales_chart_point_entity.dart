import 'package:equatable/equatable.dart';

class DailySalesPointEntity extends Equatable {
  final DateTime date;
  final String dayLabel;
  final int totalAmount; // in piasters
  final int transactionsCount;

  const DailySalesPointEntity({
    required this.date,
    required this.dayLabel,
    required this.totalAmount,
    required this.transactionsCount,
  });

  @override
  List<Object?> get props => [date, dayLabel, totalAmount, transactionsCount];
}

class HourlySalesPointEntity extends Equatable {
  final int hour;
  final String hourLabel;
  final int totalAmount; // in piasters
  final int transactionsCount;

  const HourlySalesPointEntity({
    required this.hour,
    required this.hourLabel,
    required this.totalAmount,
    required this.transactionsCount,
  });

  @override
  List<Object?> get props => [hour, hourLabel, totalAmount, transactionsCount];
}

