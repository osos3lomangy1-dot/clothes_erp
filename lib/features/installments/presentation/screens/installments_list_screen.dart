import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/customer_installment_entity.dart';
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
    final enabled = await getIt<FeatureGate>().isEnabled(FeatureKeys.installments);
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
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إدارة عقود التقسيط',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
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
                MaterialPageRoute(builder: (_) => const InstallmentPlansScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            tooltip: 'تحديث',
            onPressed: () => cubit.loadContracts(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('إنشاء عقود التقسيط متاح عبر شاشة نقطة البيع (POS) وقريباً هنا'),
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
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              cubit.setSearchQuery('');
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Status Filter Chips
                BlocBuilder<InstallmentsListCubit, InstallmentsListState>(
                  buildWhen: (prev, curr) => prev.filter != curr.filter,
                  builder: (context, state) {
                    final filters = [
                      {'key': 'all', 'label': 'الكل'},
                      {'key': 'active', 'label': 'نشط'},
                      {'key': 'overdue', 'label': 'متأخر'},
                      {'key': 'completed', 'label': 'مكتمل'},
                      {'key': 'cancelled', 'label': 'ملغي'},
                    ];

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: filters.map((f) {
                          final isSelected = state.filter == f['key'];
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: FilterChip(
                              label: Text(f['label']!),
                              selected: isSelected,
                              selectedColor: AppColors.primary.withValues(alpha: 0.15),
                              checkmarkColor: AppColors.primary,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? AppColors.primary : Colors.grey.shade700,
                              ),
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: isSelected ? AppColors.primary : Colors.grey.shade300,
                                ),
                              ),
                              onSelected: (_) => cubit.setFilter(f['key']!),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Colors.black12),

          // Contracts List
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
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'خطأ: ${state.errorMessage ?? "حدث خطأ أثناء تحميل العقود"}',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => cubit.loadContracts(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (state.contracts.isEmpty) {
                  final isFiltered = state.searchQuery.isNotEmpty || state.filter != 'all';
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          isFiltered ? 'لا توجد عقود مطابقة للبحث' : 'لا توجد عقود تقسيط مسجلة حتى الآن',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  itemCount: state.contracts.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final contract = state.contracts[index];
                    final customerName = state.customerNames[contract.customerId] ??
                        'عميل #${contract.customerId.length > 8 ? contract.customerId.substring(0, 8) : contract.customerId}';

                    return _ContractCard(
                      contract: contract,
                      customerName: customerName,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InstallmentDetailScreen(contractId: contract.id),
                          ),
                        ).then((_) => cubit.loadContracts());
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
}

class _ContractCard extends StatelessWidget {
  final CustomerInstallmentEntity contract;
  final String customerName;
  final VoidCallback onTap;

  const _ContractCard({
    required this.contract,
    required this.customerName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final computedStatus = contract.statusAt(now);
    final statusBadge = _getStatusBadge(computedStatus);

    final total = contract.totalPiasters;
    final remaining = contract.remainingPiasters;
    final paid = total - remaining;
    final progress = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;

    final endDateStr = DateFormat('yyyy/MM/dd').format(contract.endDate);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Customer & Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    customerName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            const SizedBox(height: 12),

            // Amounts Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('إجمالي العقد', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Text(
                      '${Money(total).toDisplay()} ج.م',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('المتبقي', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 2),
                    Text(
                      '${Money(remaining).toDisplay()} ج.م',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: remaining > 0 ? AppColors.primary : Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  computedStatus == 'overdue'
                      ? Colors.red
                      : computedStatus == 'completed'
                          ? Colors.green
                          : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Footer Row: Next Due / Duration
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'المدة: ${contract.durationMonths} شهور',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                Text(
                  'تاريخ الاستحقاق: $endDateStr',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ],
        ),
      ),
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

