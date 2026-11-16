import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/customer_installment_entity.dart';
import '../../domain/entities/customer_installments_summary.dart';
import '../cubits/installments_list_cubit.dart';
import 'installment_detail_screen.dart';
import 'installment_plans_screen.dart';

class InstallmentsListScreen extends StatelessWidget {
  const InstallmentsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<InstallmentsListCubit>(),
      child: const _InstallmentsListView(),
    );
  }
}

class _InstallmentsListView extends StatefulWidget {
  const _InstallmentsListView();

  @override
  State<_InstallmentsListView> createState() => _InstallmentsListViewState();
}

class _InstallmentsListViewState extends State<_InstallmentsListView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _guardFeature();
  }

  Future<void> _guardFeature() async {
    final enabled =
        await getIt<FeatureGate>().isEnabled(FeatureKeys.installments);
    if (!enabled && mounted) {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ميزة التقسيط غير مفعلة')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InstallmentsListCubit>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.onSurface),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إدارة عقود التقسيط',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.onSurface),
            ),
            Text(
              'متابعة الأقساط، الدفعات، والتحصيل',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_rounded, color: AppColors.primary),
            tooltip: 'خطط التقسيط',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const InstallmentPlansScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            tooltip: 'تحديث',
            onPressed: () => cubit.loadGrouped(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'إنشاء عقود التقسيط متاح عبر شاشة نقطة البيع (POS) وقريباً هنا'),
            ),
          );
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'عقد جديد',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Header: Search & Filter chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: cubit.setSearchQuery,
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم العميل أو رقم العقد...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              cubit.setSearchQuery('');
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.black12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),
                BlocBuilder<InstallmentsListCubit, InstallmentsListState>(
                  builder: (context, state) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _filterChip(context,
                              label: 'الكل',
                              value: 'all',
                              selected: state.filter == 'all'),
                          const SizedBox(width: 8),
                          _filterChip(context,
                              label: 'نشط',
                              value: 'active',
                              selected: state.filter == 'active'),
                          const SizedBox(width: 8),
                          _filterChip(context,
                              label: 'متأخر',
                              value: 'overdue',
                              selected: state.filter == 'overdue'),
                          const SizedBox(width: 8),
                          _filterChip(context,
                              label: 'مكتمل',
                              value: 'completed',
                              selected: state.filter == 'completed'),
                          const SizedBox(width: 8),
                          _filterChip(context,
                              label: 'ملغي',
                              value: 'cancelled',
                              selected: state.filter == 'cancelled'),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Colors.black12),

          // Grouped Customers List
          Expanded(
            child: BlocBuilder<InstallmentsListCubit, InstallmentsListState>(
              builder: (context, state) {
                if (state.status == InstallmentsListStatus.loading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state.status == InstallmentsListStatus.error) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Colors.red, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'خطأ: ${state.errorMessage ?? "حدث خطأ أثناء تحميل العقود"}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => cubit.loadGrouped(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (state.groupedByCustomer.isEmpty) {
                  final isFiltered =
                      state.searchQuery.isNotEmpty || state.filter != 'all';
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment_outlined,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          isFiltered
                              ? 'لا توجد عقود مطابقة للبحث'
                              : 'لا توجد عقود تقسيط مسجلة حتى الآن',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (isFiltered) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              cubit.setSearchQuery('');
                              cubit.setFilter('all');
                              setState(() {});
                            },
                            child: const Text('إعادة تعيين الفلاتر'),
                          ),
                        ],
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.groupedByCustomer.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final summary = state.groupedByCustomer[index];
                    return CustomerInstallmentsCard(
                      summary: summary,
                      onContractTap: (contract) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InstallmentDetailScreen(
                                contractId: contract.id),
                          ),
                        ).then((_) => cubit.loadGrouped());
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required String value,
    required bool selected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) =>
          context.read<InstallmentsListCubit>().setFilter(value),
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : Colors.black87,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

class CustomerInstallmentsCard extends StatefulWidget {
  final CustomerInstallmentsSummary summary;
  final void Function(CustomerInstallmentEntity contract) onContractTap;

  const CustomerInstallmentsCard({
    super.key,
    required this.summary,
    required this.onContractTap,
  });

  @override
  State<CustomerInstallmentsCard> createState() =>
      _CustomerInstallmentsCardState();
}

class _CustomerInstallmentsCardState extends State<CustomerInstallmentsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final now = DateTime.now();

    final hasOverdue = s.contracts.any((c) => c.statusAt(now) == 'overdue');
    final allCompleted =
        s.contracts.every((c) => c.statusAt(now) == 'completed');
    final overallStatus = hasOverdue
        ? 'overdue'
        : allCompleted
            ? 'completed'
            : 'active';

    final statusBadge = _getStatusBadge(overallStatus);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    s.customerName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBadge.backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusBadge.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusBadge.color,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _metricChip(
                    Icons.description_rounded,
                    s.contractsCount == 1
                        ? 'المدة: ${s.contracts.first.durationMonths} شهور'
                        : '${s.contractsCount} عقود',
                  ),
                  _metricChip(
                    Icons.money_off_rounded,
                    'متبقي: ${Money(s.totalRemainingPiasters).toDisplay()} ج.م',
                  ),
                  _metricChip(
                    Icons.calendar_month_rounded,
                    'قسط شهري: ${Money(s.totalMonthlyAmountPiasters).toDisplay()} ج.م',
                  ),
                ],
              ),
            ),
            trailing: IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              tooltip: _expanded ? 'إخفاء العقود' : 'عرض العقود',
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ...s.contracts.map((contract) {
              final cStatus = contract.statusAt(now);
              final badge = _getStatusBadge(cStatus);
              final shortId = contract.id.length > 8
                  ? contract.id.substring(0, 8)
                  : contract.id;
              return ListTile(
                dense: true,
                leading: const Icon(Icons.receipt_long_rounded,
                    size: 20, color: AppColors.primary),
                title: Text('عقد #$shortId',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'المدة: ${contract.durationMonths} شهور | متبقي: ${Money(contract.remainingPiasters).toDisplay()} ج.م | قسط: ${Money(contract.monthlyAmountPiasters).toDisplay()} ج.م',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badge.backgroundColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badge.color,
                    ),
                  ),
                ),
                onTap: () => widget.onContractTap(contract),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _metricChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  _StatusBadge _getStatusBadge(String status) {
    switch (status) {
      case 'active':
        return _StatusBadge(
          label: 'نشط',
          color: Colors.blue.shade800,
          backgroundColor: Colors.blue.shade50,
        );
      case 'overdue':
        return _StatusBadge(
          label: 'متأخر',
          color: Colors.red.shade800,
          backgroundColor: Colors.red.shade50,
        );
      case 'completed':
        return _StatusBadge(
          label: 'مكتمل',
          color: Colors.green.shade800,
          backgroundColor: Colors.green.shade50,
        );
      case 'cancelled':
        return _StatusBadge(
          label: 'ملغي',
          color: Colors.grey.shade800,
          backgroundColor: Colors.grey.shade200,
        );
      default:
        return _StatusBadge(
          label: status,
          color: Colors.grey.shade700,
          backgroundColor: Colors.grey.shade100,
        );
    }
  }
}

class _StatusBadge {
  final String label;
  final Color color;
  final Color backgroundColor;

  _StatusBadge({
    required this.label,
    required this.color,
    required this.backgroundColor,
  });
}
