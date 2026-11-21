import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../cubits/pre_orders_cubit.dart';
import '../cubits/pre_orders_state.dart';
import '../widgets/create_pre_order_dialog.dart';
import '../widgets/pre_order_card.dart';
import '../widgets/pre_order_delivery_dialog.dart';

class PreOrdersScreen extends StatelessWidget {
  const PreOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<PreOrdersCubit>()..loadPreOrders(),
      child: const _PreOrdersView(),
    );
  }
}

class _PreOrdersView extends StatefulWidget {
  const _PreOrdersView();

  @override
  State<_PreOrdersView> createState() => _PreOrdersViewState();
}

class _PreOrdersViewState extends State<_PreOrdersView> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        shape: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
        titleSpacing: 16,
        title: Row(
          children: [
            if (Navigator.canPop(context)) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface, size: 20),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 4),
            ],
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.bookmark_added_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'الحجز المسبق والعربونات والطلبات الخاصة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  'إدارة عربونات شي إن والطلبات المؤجلة وتتبع حالات الشحن والتسليم والمصادرة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 24),

            // Search Field
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'بحث برقم الحجز، اسم العميل، أو الهاتف...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.grey),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  context.read<PreOrdersCubit>().setSearchQuery('');
                                  setState(() {});
                                },
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppColors.outlineVariant),
                        ),
                      ),
                      onChanged: (q) {
                        context.read<PreOrdersCubit>().setSearchQuery(q);
                        setState(() {});
                      },
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Add Pre-Order Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 1,
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'حجز مسبق جديد',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => BlocProvider.value(
                    value: context.read<PreOrdersCubit>(),
                    child: const CreatePreOrderDialog(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: BlocBuilder<PreOrdersCubit, PreOrdersState>(
        builder: (context, state) {
          if (state.status == PreOrdersViewStatus.loading && state.allOrders.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (state.status == PreOrdersViewStatus.error && state.allOrders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(
                    state.errorMessage ?? 'حدث خطأ أثناء تحميل الحجوزات',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, color: AppColors.error),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.read<PreOrdersCubit>().loadPreOrders(),
                    child: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo')),
                  ),
                ],
              ),
            );
          }

          final filtered = state.filteredOrders;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Status Tabs Bar
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _tabChip(
                        label: 'الكل',
                        count: state.totalCount,
                        tabId: 'all',
                        currentTab: state.selectedTab,
                        activeColor: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      _tabChip(
                        label: 'قيد التجهيز والشحن',
                        count: state.pendingCount,
                        tabId: PreOrderStatuses.pendingProcessing,
                        currentTab: state.selectedTab,
                        activeColor: Colors.amber.shade800,
                      ),
                      const SizedBox(width: 8),
                      _tabChip(
                        label: 'وصل للمحل وجاهز',
                        count: state.arrivedCount,
                        tabId: PreOrderStatuses.arrivedAtStore,
                        currentTab: state.selectedTab,
                        activeColor: Colors.teal.shade700,
                      ),
                      const SizedBox(width: 8),
                      _tabChip(
                        label: 'مكتمل ومستلم',
                        count: state.deliveredCount,
                        tabId: PreOrderStatuses.delivered,
                        currentTab: state.selectedTab,
                        activeColor: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      _tabChip(
                        label: 'مصادرة / لم يستلم',
                        count: state.defaultedCount,
                        tabId: PreOrderStatuses.defaultedForfeited,
                        currentTab: state.selectedTab,
                        activeColor: Colors.orange.shade800,
                      ),
                      const SizedBox(width: 8),
                      _tabChip(
                        label: 'ملغي ومسترد',
                        count: state.refundedCount,
                        tabId: PreOrderStatuses.refundedCancelled,
                        currentTab: state.selectedTab,
                        activeColor: Colors.grey.shade600,
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Orders Content
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              state.searchQuery.isNotEmpty
                                  ? 'لا توجد طلبات حجز مطابقة لبحثك'
                                  : 'لا توجد طلبات حجز مسجلة في هذا القسم',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 14, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 420,
                          mainAxisExtent: 265,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final order = filtered[index];
                          return PreOrderCard(
                            order: order,
                            onDeliver: () {
                              showDialog(
                                context: context,
                                builder: (_) => BlocProvider.value(
                                  value: context.read<PreOrdersCubit>(),
                                  child: PreOrderDeliveryDialog(order: order),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tabChip({
    required String label,
    required int count,
    required String tabId,
    required String currentTab,
    required Color activeColor,
  }) {
    final isSelected = tabId == currentTab;
    return InkWell(
      onTap: () => context.read<PreOrdersCubit>().setTab(tabId),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.outlineVariant,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? activeColor : AppColors.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
