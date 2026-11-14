import 'package:equatable/equatable.dart';

class InstallmentScheduleEntry extends Equatable {
  final int installmentNumber;
  final DateTime dueDate;
  final int amountPiasters;
  final int principalComponentPiasters;
  final int interestComponentPiasters;

  const InstallmentScheduleEntry({
    required this.installmentNumber,
    required this.dueDate,
    required this.amountPiasters,
    required this.principalComponentPiasters,
    required this.interestComponentPiasters,
  });

  @override
  List<Object?> get props => [installmentNumber, dueDate, amountPiasters, principalComponentPiasters, interestComponentPiasters];
}
