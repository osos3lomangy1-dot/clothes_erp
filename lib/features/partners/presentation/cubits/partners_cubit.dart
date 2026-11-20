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

    if (isClosed) return;

    partnersRes.fold(
      (failure) {
        if (!isClosed) {
          emit(
            state.copyWith(
              status: PartnersStatus.error,
              errorMessage: failure.message,
            ),
          );
        }
      },
      (partners) {
        profitRes.fold(
          (failure) {
            if (!isClosed) {
              emit(
                state.copyWith(
                  status: PartnersStatus.error,
                  errorMessage: failure.message,
                ),
              );
            }
          },
          (summary) {
            if (!isClosed) {
              emit(
                state.copyWith(
                  status: PartnersStatus.loaded,
                  partners: partners,
                  profitSummary: summary,
                  fromDate: effectiveFrom,
                  toDate: effectiveTo,
                ),
              );
            }
          },
        );
      },
    );
  }

  Future<bool> savePartner(PartnerEntity partner) async {
    final result = await _repository.savePartner(partner);
    return await result.fold(
      (failure) async {
        if (!isClosed) {
          emit(
            state.copyWith(
              status: PartnersStatus.error,
              errorMessage: failure.message,
            ),
          );
        }
        return false;
      },
      (_) async {
        await loadData();
        return true;
      },
    );
  }

  Future<void> deletePartner(String id) async {
    final result = await _repository.deletePartner(id);
    await result.fold(
      (failure) async {
        if (!isClosed) {
          emit(
            state.copyWith(
              status: PartnersStatus.error,
              errorMessage: failure.message,
            ),
          );
        }
      },
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

  /// Record an out-of-pocket funding / deposit by a partner (e.g. paying for goods, operating expense, or cash injection)
  Future<bool> recordDeposit({
    required String partnerId,
    required int amount,
    required String category, // 'goods', 'expenses', 'cash'
    String? note,
  }) async {
    final partner = state.partners.firstWhere(
      (p) => p.id == partnerId,
      orElse: () => throw Exception('الشريك غير موجود'),
    );

    final deposit = PartnerDeposit(
      id: _uuid.v4(),
      amount: amount,
      category: category,
      note: note,
      date: DateTime.now(),
    );

    final updatedDeposits = [...partner.deposits, deposit];
    final updatedPartner = partner.copyWith(deposits: updatedDeposits);

    return await savePartner(updatedPartner);
  }

  /// Reinvest retained profit into capital (increases partner capital and records profit withdrawal)
  Future<bool> reinvestProfitIntoCapital({
    required String partnerId,
    required int amount,
    String? note,
  }) async {
    final partner = state.partners.firstWhere(
      (p) => p.id == partnerId,
      orElse: () => throw Exception('الشريك غير موجود'),
    );

    final withdrawal = PartnerWithdrawal(
      id: _uuid.v4(),
      amount: amount,
      type: 'profit',
      note: note ?? 'إعادة استثمار وتدوير الأرباح كزيادة في رأس المال',
      date: DateTime.now(),
    );

    final updatedPartner = partner.copyWith(
      capital: partner.capital + amount,
      withdrawals: [...partner.withdrawals, withdrawal],
    );

    return await savePartner(updatedPartner);
  }

  /// Refund / reimburse personal out-of-pocket funding to the partner
  Future<bool> refundDeposit({
    required String partnerId,
    required int amount,
    String? note,
  }) async {
    final partner = state.partners.firstWhere(
      (p) => p.id == partnerId,
      orElse: () => throw Exception('الشريك غير موجود'),
    );

    final withdrawal = PartnerWithdrawal(
      id: _uuid.v4(),
      amount: amount,
      type: 'deposit_refund',
      note: note ?? 'استرداد تمويل شخصي مدفوع من الجيب',
      date: DateTime.now(),
    );

    final updatedWithdrawals = [...partner.withdrawals, withdrawal];
    final updatedPartner = partner.copyWith(withdrawals: updatedWithdrawals);

    return await savePartner(updatedPartner);
  }

  /// Convert personal funding into active capital (increases capital and closes deposit liability)
  Future<bool> convertDepositToCapital({
    required String partnerId,
    required int amount,
    String? note,
  }) async {
    final partner = state.partners.firstWhere(
      (p) => p.id == partnerId,
      orElse: () => throw Exception('الشريك غير موجود'),
    );

    final withdrawal = PartnerWithdrawal(
      id: _uuid.v4(),
      amount: amount,
      type: 'deposit_to_capital',
      note: note ?? 'تحويل تمويل من الجيب إلى زيادة في رأس المال',
      date: DateTime.now(),
    );

    final updatedPartner = partner.copyWith(
      capital: partner.capital + amount,
      withdrawals: [...partner.withdrawals, withdrawal],
    );

    return await savePartner(updatedPartner);
  }

  /// Delete a specific withdrawal transaction for a partner
  Future<bool> deleteWithdrawal({
    required String partnerId,
    required String withdrawalId,
  }) async {
    final partner = state.partners.firstWhere(
      (p) => p.id == partnerId,
      orElse: () => throw Exception('الشريك غير موجود'),
    );

    final target = partner.withdrawals.firstWhere(
      (w) => w.id == withdrawalId,
      orElse: () => throw Exception('الحركة غير موجودة'),
    );

    int newCapital = partner.capital;
    if (target.type == 'deposit_to_capital') {
      newCapital = (newCapital - target.amount).clamp(0, 100000000000);
    }

    final updatedWithdrawals = partner.withdrawals.where((w) => w.id != withdrawalId).toList();
    final updatedPartner = partner.copyWith(
      capital: newCapital,
      withdrawals: updatedWithdrawals,
    );

    return await savePartner(updatedPartner);
  }

  /// Delete a specific deposit transaction for a partner
  Future<bool> deleteDeposit({
    required String partnerId,
    required String depositId,
  }) async {
    final partner = state.partners.firstWhere(
      (p) => p.id == partnerId,
      orElse: () => throw Exception('الشريك غير موجود'),
    );

    final updatedDeposits = partner.deposits.where((d) => d.id != depositId).toList();
    final updatedPartner = partner.copyWith(deposits: updatedDeposits);

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
