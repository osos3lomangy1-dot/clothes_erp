import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/invoice_details_entity.dart';
import '../cubits/invoices_cubit.dart';
import '../cubits/invoices_state.dart';
import '../services/receipt_pdf_service.dart';
import '../widgets/invoice_details_dialog.dart';

class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<InvoicesCubit>()..loadInvoices(),
      child: const _InvoicesView(),
    );
  }
}

class _InvoicesView extends StatefulWidget {
  const _InvoicesView();

  @override
  State<_InvoicesView> createState() => _InvoicesViewState();
}

class _InvoicesViewState extends State<_InvoicesView> {
  final _searchController = TextEditingController();
  String _activeDateFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setDateFilter(String filter) {
    setState(() => _activeDateFilter = filter);
    final now = DateTime.now();
    final cubit = context.read<InvoicesCubit>();

    if (filter == 'today') {
      cubit.filterDate(
        from: DateTime(now.year, now.month, now.day),
        to: DateTime(now.year, now.month, now.day),
      );
    } else if (filter == 'week') {
      cubit.filterDate(
        from: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
        to: DateTime(now.year, now.month, now.day),
      );
    } else if (filter == 'month') {
      cubit.filterDate(
        from: DateTime(now.year, now.month, 1),
        to: DateTime(now.year, now.month, now.day),
      );
    } else {
      cubit.filterDate(from: null, to: null);
    }
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _activeDateFilter = 'custom');
      if (mounted) {
        context.read<InvoicesCubit>().filterDate(from: picked.start, to: picked.end);
      }
    }
  }

  void _openDetails(InvoiceDetailsEntity invoice) {
    showDialog(
      context: context,
      builder: (_) => InvoiceDetailsDialog(invoice: invoice),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    return Scaffold(
      backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سجل فواتير المبيعات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
              ),
              Text(
                'البحث في فواتير الكاشير، إعادة الطباعة، وتنزيل نسخ PDF',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              // Search & Filter Bar
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (q) => context.read<InvoicesCubit>().search(q),
                      decoration: InputDecoration(
                        hintText: 'ابحث برقم الفاتورة (#S...) أو اسم العميل أو الموبايل...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded),
                                onPressed: () {
                                  _searchController.clear();
                                  context.read<InvoicesCubit>().search('');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _filterChip('الكل', 'all'),
                  const SizedBox(width: 6),
                  _filterChip('اليوم', 'today'),
                  const SizedBox(width: 6),
                  _filterChip('آخر 7 أيام', 'week'),
                  const SizedBox(width: 6),
                  _filterChip('هذا الشهر', 'month'),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: _activeDateFilter == 'custom' ? AppColors.primary : Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onPressed: _pickCustomDateRange,
                    icon: Icon(Icons.calendar_month_rounded, size: 18, color: _activeDateFilter == 'custom' ? AppColors.primary : Colors.grey.shade700),
                    label: Text(
                      'تاريخ مخصص',
                      style: TextStyle(fontSize: 12, color: _activeDateFilter == 'custom' ? AppColors.primary : Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Summary Stats Row
              BlocBuilder<InvoicesCubit, InvoicesState>(
                builder: (context, state) {
                  return Row(
                    children: [
                      Expanded(
                        child: _statsCard(
                          'عدد الفواتير',
                          '${state.totalInvoicesCount} فاتورة',
                          Icons.receipt_long_rounded,
                          AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _statsCard(
                          'إجمالي المبيعات بالفترة',
                          '${Money(state.totalRevenuePiasters).toDisplay()} ج.م',
                          Icons.monetization_on_rounded,
                          Colors.green.shade700,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),

              // Invoices List
              Expanded(
                child: BlocBuilder<InvoicesCubit, InvoicesState>(
                  builder: (context, state) {
                    if (state.status == InvoicesStatus.loading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (state.invoices.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'لا توجد فواتير مطابقة لبحثك',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600, fontSize: 16),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: state.invoices.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final invoice = state.invoices[idx];
                        return Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: InkWell(
                            onTap: () => _openDetails(invoice),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.receipt_rounded, color: AppColors.primary, size: 24),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'فاتورة #${invoice.shortRef}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dateFormat.format(invoice.date),
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          invoice.customerName ?? 'عميل نقدي',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        ),
                                        Text(
                                          'كاشير: ${invoice.cashierName}',
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: invoice.paymentMethod.toLowerCase().contains('cash') || invoice.paymentMethod.contains('كاش')
                                            ? Colors.green.shade50
                                            : Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        invoice.paymentMethod,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: invoice.paymentMethod.toLowerCase().contains('cash') || invoice.paymentMethod.contains('كاش')
                                              ? Colors.green.shade800
                                              : Colors.blue.shade800,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${Money(invoice.total).toDisplay()} ج.م',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                                      ),
                                      Text(
                                        '${invoice.totalItemsCount} قطعة',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  // Quick Action Icons
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'تنزيل PDF',
                                        icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.red, size: 20),
                                        onPressed: () async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          final path = await ReceiptPdfService.saveReceiptAsPdf(invoice);
                                          if (path != null) {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text('تم تنزيل الفاتورة كملف PDF:\n$path'),
                                                backgroundColor: Colors.green,
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                      IconButton(
                                        tooltip: 'طباعة فورية',
                                        icon: const Icon(Icons.print_rounded, color: AppColors.primary, size: 20),
                                        onPressed: () => ReceiptPdfService.printReceipt(invoice),
                                      ),
                                      IconButton(
                                        tooltip: 'عرض التفاصيل',
                                        icon: const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                                        onPressed: () => _openDetails(invoice),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _activeDateFilter == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      onSelected: (_) => _setDateFilter(value),
    );
  }

  Widget _statsCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

