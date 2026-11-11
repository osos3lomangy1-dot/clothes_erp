import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import '../../domain/entities/invoice_details_entity.dart';
import '../../domain/repositories/invoices_repository.dart';
import 'invoices_state.dart';

@injectable
class InvoicesCubit extends Cubit<InvoicesState> {
  final InvoicesRepository _repository;

  InvoicesCubit(this._repository) : super(const InvoicesState());

  Future<void> loadInvoices() async {
    emit(state.copyWith(status: InvoicesStatus.loading, clearErrorMessage: true));

    final result = await _repository.getInvoices(
      search: state.searchQuery,
      fromDate: state.fromDate,
      toDate: state.toDate,
      paymentMethod: state.paymentMethod,
    );

    result.fold(
      (failure) => emit(state.copyWith(
        status: InvoicesStatus.error,
        errorMessage: failure.message,
      )),
      (list) => emit(state.copyWith(
        status: InvoicesStatus.loaded,
        invoices: list,
      )),
    );
  }

  void search(String query) {
    emit(state.copyWith(searchQuery: query));
    loadInvoices();
  }

  void filterStatus(String status) {
    emit(state.copyWith(statusFilter: status));
  }

  void filterDate({DateTime? from, DateTime? to}) {
    emit(state.copyWith(
      fromDate: from,
      clearFromDate: from == null,
      toDate: to,
      clearToDate: to == null,
    ));
    loadInvoices();
  }

  void filterPaymentMethod(String? method) {
    emit(state.copyWith(
      paymentMethod: method,
      clearPaymentMethod: method == null,
    ));
    loadInvoices();
  }

  void selectInvoice(InvoiceDetailsEntity? invoice) {
    emit(state.copyWith(
      selectedInvoice: invoice,
      clearSelectedInvoice: invoice == null,
    ));
  }
}
