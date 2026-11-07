import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/partner_entity.dart';
import '../../domain/repositories/partner_repository.dart';
import 'partners_state.dart';

@injectable
class PartnersCubit extends Cubit<PartnersState> {
  final PartnerRepository _repository;

  PartnersCubit(this._repository) : super(const PartnersState());

  Future<void> loadData({DateTime? from, DateTime? to}) async {
    emit(state.copyWith(
      status: PartnersStatus.loading,
      fromDate: from ?? state.fromDate,
      toDate: to ?? state.toDate,
    ));

    final effectiveFrom = from ?? state.fromDate;
    final effectiveTo = to ?? state.toDate;

    final partnersRes = await _repository.getPartners();
    final profitRes = await _repository.getProfitSummary(from: effectiveFrom, to: effectiveTo);

    partnersRes.fold(
      (failure) => emit(state.copyWith(status: PartnersStatus.error, errorMessage: failure.message)),
      (partners) {
        profitRes.fold(
          (failure) => emit(state.copyWith(status: PartnersStatus.error, errorMessage: failure.message)),
          (summary) {
            emit(state.copyWith(
              status: PartnersStatus.loaded,
              partners: partners,
              profitSummary: summary,
            ));
          },
        );
      },
    );
  }

  Future<bool> savePartner(PartnerEntity partner) async {
    final result = await _repository.savePartner(partner);
    return result.fold(
      (failure) {
        emit(state.copyWith(status: PartnersStatus.error, errorMessage: failure.message));
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
      (failure) => emit(state.copyWith(status: PartnersStatus.error, errorMessage: failure.message)),
      (_) => loadData(),
    );
  }
}

