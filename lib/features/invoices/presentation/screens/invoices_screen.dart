import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/custom_date_range_dialog.dart';
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
        from: DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6)),
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
    final picked = await showCustomDateRangeDialog(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _activeDateFilter = 'custom');
      if (mounted) {
        context.read<InvoicesCubit>().filterDate(
          from: picked.start,
          to: picked.end,
        );
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
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.onSurface,
                ),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سجل فواتير المبيعات',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'البحث في فواتير الكاشير، متابعة المرتجعات، وإعادة الطباعة وتنزيل PDF',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Search & Date Filter Bar (Responsive: single Row on wide, Wrap below on compact)
            LayoutBuilder(
              builder: (context, constraints) {
                final searchField = TextField(
                  controller: _searchController,
                  onChanged: (q) => context.read<InvoicesCubit>().search(q),
                  decoration: InputDecoration(
                    hintText:
                        'ابحث برقم الفاتورة (#S...) أو اسم العميل أو الموبايل...',
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
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                );

                final customDateBtn = OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(
                      color: _activeDateFilter == 'custom'
                          ? AppColors.primary
                          : Colors.grey.shade300,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onPressed: _pickCustomDateRange,
                  icon: Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: _activeDateFilter == 'custom'
                        ? AppColors.primary
                        : Colors.grey.shade700,
                  ),
                  label: Text(
                    'تاريخ مخصص',
                    style: TextStyle(
                      fontSize: 12,
                      color: _activeDateFilter == 'custom'
                          ? AppColors.primary
                          : Colors.grey.shade700,
                    ),
                  ),
                );

                final dateChips = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _filterChip('الكل', 'all'),
                    _filterChip('اليوم', 'today'),
                    _filterChip('آخر 7 أيام', 'week'),
                    _filterChip('هذا الشهر', 'month'),
                    customDateBtn,
                  ],
                );

                if (constraints.maxWidth >= 880) {
                  return Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 12),
                      dateChips,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    dateChips,
                  ],
                );
              },
            ),
            const SizedBox(height: 12),

            // Status Filter Tabs (الكل | المكتملة | المرتجعات)
            BlocBuilder<InvoicesCubit, InvoicesState>(
              builder: (context, state) {
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _statusChip(
                        context,
                        'جميع الفواتير',
                        'all',
                        state.statusFilter,
                      ),
                      _statusChip(
                        context,
                        'المبيعات المكتملة',
                        'completed',
                        state.statusFilter,
                      ),
                      _statusChip(
                        context,
                        'المرتجعات',
                        'returned',
                        state.statusFilter,
                        badgeCount: state.returnedInvoicesCount,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 14),

            // Summary Stats Row
            BlocBuilder<InvoicesCubit, InvoicesState>(
              builder: (context, state) {
                return Row(
                  children: [
                    Expanded(
                      child: _statsCard(
                        'عدد الفواتير المعروضة',
                        '${state.totalInvoicesCount} فاتورة',
                        Icons.receipt_long_rounded,
                        AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _statsCard(
                        'إجمالي القيمة بالفترة',
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

                  final list = state.filteredInvoices;

                  if (list.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            state.statusFilter == 'returned'
                                ? 'لا توجد فواتير مرتجعة في الفترة المحددة'
                                : 'لا توجد فواتير مطابقة لبحثك',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final invoice = list[idx];
                      return _buildInvoiceCard(context, invoice, dateFormat);
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

  Widget _buildInvoiceCard(
    BuildContext context,
    InvoiceDetailsEntity invoice,
    DateFormat dateFormat,
  ) {
    Color statusBorderColor;
    Color statusTextColor;
    String statusLabel;

    if (invoice.status == 'returned') {
      statusBorderColor = AppColors.error.withValues(alpha: 0.3);
      statusTextColor = AppColors.error;
      statusLabel = 'مرتجعة بالكامل';
    } else if (invoice.status == 'partially_returned') {
      statusBorderColor = AppColors.warning.withValues(alpha: 0.3);
      statusTextColor = AppColors.warning;
      statusLabel = 'مرتجع جزئي';
    } else {
      statusBorderColor = AppColors.success.withValues(alpha: 0.3);
      statusTextColor = AppColors.success;
      statusLabel = 'مكتملة';
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => _openDetails(invoice),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: invoice.status == 'returned'
                      ? AppColors.error.withValues(alpha: 0.08)
                      : AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  invoice.status == 'returned'
                      ? Icons.assignment_return_rounded
                      : Icons.receipt_rounded,
                  color: invoice.status == 'returned'
                      ? AppColors.error
                      : AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              // Reference, Date & Status Badge
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          'فاتورة #',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: statusBorderColor),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dateFormat.format(invoice.date),
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Customer & Cashier Info
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.customerName ?? 'عميل نقدي',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: AppColors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'كاشير: ',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Payment Method Badge (purified subtle pill)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Text(
                  _formatPaymentLabel(invoice.paymentMethod),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              // Total Amount & Items Count
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 80),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        ' ج.م',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                          color: invoice.status == 'returned'
                              ? AppColors.error
                              : AppColors.primary,
                          decoration: invoice.status == 'returned'
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    Text(
                      ' قطعة',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: const EdgeInsets.all(4),
                    tooltip: 'تنزيل PDF',
                    icon: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Color(0xFFEF4444),
                      size: 18,
                    ),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final path = await ReceiptPdfService.saveReceiptAsPdf(
                        invoice,
                      );
                      if (path != null) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('تم تنزيل الفاتورة كملف PDF:\n'),
                            backgroundColor: AppColors.success,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: const EdgeInsets.all(4),
                    tooltip: 'طباعة فورية',
                    icon: Icon(
                      Icons.print_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    onPressed: () => ReceiptPdfService.printReceipt(invoice),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: const EdgeInsets.all(4),
                    tooltip: 'عرض التفاصيل',
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: Color(0xFF94A3B8),
                      size: 20,
                    ),
                    onPressed: () => _openDetails(invoice),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(
    BuildContext context,
    String label,
    String value,
    String activeStatus, {
    int? badgeCount,
  }) {
    final isSelected = activeStatus == value;
    final cubit = context.read<InvoicesCubit>();

    return FilterChip(
      selected: isSelected,
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppColors.primary : Colors.grey.shade800,
            ),
          ),
          if (badgeCount != null && badgeCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onSelected: (_) => cubit.filterStatus(value),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _activeDateFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatPaymentLabel(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'cash':
        return 'نقدي';
      case 'card':
      case 'visa':
        return 'بطاقة';
      case 'installment':
        return 'تقسيط';
      case 'mixed':
        return 'مختلط';
      default:
        return raw;
    }
  }
}
