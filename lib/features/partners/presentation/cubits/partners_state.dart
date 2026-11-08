import 'package:equatable/equatable.dart';
import '../../data/datasources/partners_local_data_source.dart';
import '../../domain/entities/partner_entity.dart';

enum PartnersStatus { initial, loading, loaded, error }

class PartnersState extends Equatable {
  final PartnersStatus status;
  final List<PartnerEntity> partners;
  final ProfitSummary? profitSummary;
  final String? errorMessage;
  final DateTime? fromDate;
  final DateTime? toDate;

  const PartnersState({
    this.status = PartnersStatus.initial,
    this.partners = const [],
    this.profitSummary,
    this.errorMessage,
    this.fromDate,
    this.toDate,
  });

  double get totalPercentage => partners.fold<double>(0.0, (sum, p) => sum + p.percentage);

  int get totalCapital => partners.fold<int>(0, (sum, p) => sum + p.capital);

  int get totalCurrentCapital => partners.fold<int>(0, (sum, p) => sum + p.currentCapital);

  int get totalWithdrawn => partners.fold<int>(0, (sum, p) => sum + p.totalWithdrawn);

  PartnersState copyWith({
    PartnersStatus? status,
    List<PartnerEntity>? partners,
    ProfitSummary? profitSummary,
    String? errorMessage,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    return PartnersState(
      status: status ?? this.status,
      partners: partners ?? this.partners,
      profitSummary: profitSummary ?? this.profitSummary,
      errorMessage: errorMessage ?? this.errorMessage,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
    );
  }

  @override
  List<Object?> get props => [status, partners, profitSummary, errorMessage, fromDate, toDate];
}
