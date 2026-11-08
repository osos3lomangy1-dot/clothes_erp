import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/partner_entity.dart';
import '../../domain/repositories/partner_repository.dart';
import 'partners_state.dart';

@injectable
class PartnersCubit extends Cubit<PartnersState> {
  final PartnerRepository _repository;
  final _uuid = const Uuid();

  PartnersCubit(this._repository) : super(const PartnersState());

  Future<void> loadData({DateTime? from, DateTime? to}) async {
    emit(
      state.copyWith(
        status: PartnersStatus.loading,
        fromDate: from ?? state.fromDate,
        toDate: to ?? state.toDate,
      ),
    );

    final effectiveFrom = from ?? state.fromDate;
    final effectiveTo = to ?? state.toDate;

    final partnersRes = await _repository.getPartners();
    final profitRes = await _repository.getProfitSummary(
      from: effectiveFrom,
      to: effectiveTo,
    );

    partnersRes.fold(
      (failure) => emit(
        state.copyWith(
          status: PartnersStatus.error,
          errorMessage: failure.message,
        ),
      ),
      (partners) {
        profitRes.fold(
          (failure) => emit(
            state.copyWith(
              status: PartnersStatus.error,
              errorMessage: failure.message,
            ),
          ),
          (summary) {
            emit(
              state.copyWith(
                status: PartnersStatus.loaded,
                partners: partners,
                profitSummary: summary,
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> savePartner(PartnerEntity partner) async {
    final result = await _repository.savePartner(partner);
    return result.fold(
      (failure) {
        emit(
          state.copyWith(
            status: PartnersStatus.error,
            errorMessage: failure.message,
          ),
        );
        return false;
      },
      (_) {
        loadData();
        return true;
      },
    );
  }

  Future<void> deletePartner(String id) async {
    final result = await _repository.deletePartner(id);
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: PartnersStatus.error,
          errorMessage: failure.message,
        ),
      ),
      (_) => loadData(),
    );
  }

  /// Record a withdrawal / payout to a partner (e.g. paying out profits or returning capital)
  Future<bool> recordWithdrawal({
    required String partnerId,
    required int amount,
    required String type, // 'profit' or 'capital'
    String? note,
  }) async {
    final partner = state.partners.firstWhere(
      (p) => p.id == partnerId,
      orElse: () => throw Exception('الشريك غير موجود'),
    );

    final withdrawal = PartnerWithdrawal(
      id: _uuid.v4(),
      amount: amount,
      type: type,
      note: note,
      date: DateTime.now(),
    );

    final updatedWithdrawals = [...partner.withdrawals, withdrawal];
    final updatedPartner = partner.copyWith(withdrawals: updatedWithdrawals);

    return await savePartner(updatedPartner);
  }

  /// Automatically re-calculate percentages for all capital-contributing partners based on their capital ratio
  Future<bool> autoBalancePercentagesByCapital() async {
    final partners = state.partners;
    final totalCapital = partners.fold<int>(0, (sum, p) => sum + p.capital);

    if (totalCapital <= 0) return false;

    // Distribute 100% proportionally to capital
    for (final partner in partners) {
      if (partner.capital > 0) {
        final calcPercentage = (partner.capital / totalCapital) * 100.0;
        final rounded = double.parse(calcPercentage.toStringAsFixed(2));
        final updated = partner.copyWith(percentage: rounded);
        await _repository.savePartner(updated);
      }
    }

    await loadData();
    return true;
  }
}
