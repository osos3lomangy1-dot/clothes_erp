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
  final String statusFilter; // 'all', 'completed', 'returned'
  final String? errorMessage;

  const InvoicesState({
    this.status = InvoicesStatus.initial,
    this.invoices = const [],
    this.selectedInvoice,
    this.searchQuery = '',
    this.fromDate,
    this.toDate,
    this.paymentMethod,
    this.statusFilter = 'all',
    this.errorMessage,
  });

  List<InvoiceDetailsEntity> get filteredInvoices {
    if (statusFilter == 'completed') {
      return invoices.where((i) => i.status == 'completed').toList();
    } else if (statusFilter == 'returned') {
      return invoices.where((i) => i.status == 'returned' || i.status == 'partially_returned').toList();
    }
    return invoices;
  }

  int get totalInvoicesCount => filteredInvoices.length;
  int get totalRevenuePiasters => filteredInvoices.fold<int>(0, (sum, i) => sum + i.total);
  int get returnedInvoicesCount =>
      invoices.where((i) => i.status == 'returned' || i.status == 'partially_returned').length;

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
    String? statusFilter,
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
      statusFilter: statusFilter ?? this.statusFilter,
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
        statusFilter,
        errorMessage,
      ];
}
