import 'package:equatable/equatable.dart';
import '../../domain/entities/invoice_details_entity.dart';

enum InvoicesStatus { initial, loading, loaded, error }

class InvoicesState extends Equatable {
  final InvoicesStatus status;
  final List<InvoiceDetailsEntity> invoices;
  final InvoiceDetailsEntity? selectedInvoice;
  final String searchQuery;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? paymentMethod;
  final String? errorMessage;

  const InvoicesState({
    this.status = InvoicesStatus.initial,
    this.invoices = const [],
    this.selectedInvoice,
    this.searchQuery = '',
    this.fromDate,
    this.toDate,
    this.paymentMethod,
    this.errorMessage,
  });

  int get totalInvoicesCount => invoices.length;
  int get totalRevenuePiasters => invoices.fold<int>(0, (sum, i) => sum + i.total);

  InvoicesState copyWith({
    InvoicesStatus? status,
    List<InvoiceDetailsEntity>? invoices,
    InvoiceDetailsEntity? selectedInvoice,
    bool clearSelectedInvoice = false,
    String? searchQuery,
    DateTime? fromDate,
    bool clearFromDate = false,
    DateTime? toDate,
    bool clearToDate = false,
    String? paymentMethod,
    bool clearPaymentMethod = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return InvoicesState(
      status: status ?? this.status,
      invoices: invoices ?? this.invoices,
      selectedInvoice: clearSelectedInvoice ? null : (selectedInvoice ?? this.selectedInvoice),
      searchQuery: searchQuery ?? this.searchQuery,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      paymentMethod: clearPaymentMethod ? null : (paymentMethod ?? this.paymentMethod),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        status,
        invoices,
        selectedInvoice,
        searchQuery,
        fromDate,
        toDate,
        paymentMethod,
        errorMessage,
      ];
}

