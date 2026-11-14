import 'package:equatable/equatable.dart';

class InstallmentPlanEntity extends Equatable {
  final String id;
  final String branchId;
  final String name;
  final String? description;
  final int durationMonths;
  final int downPaymentPiasters;
  final int interestBp;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const InstallmentPlanEntity({
    required this.id,
    required this.branchId,
    required this.name,
    this.description,
    required this.durationMonths,
    required this.downPaymentPiasters,
    required this.interestBp,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  List<Object?> get props => [id, branchId, name, description, durationMonths, downPaymentPiasters, interestBp, isActive, createdAt, updatedAt, deletedAt];
}
