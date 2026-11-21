import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../cubits/pre_orders_cubit.dart';
import '../cubits/pre_orders_state.dart';
import '../widgets/create_pre_order_dialog.dart';
import '../widgets/create_pre_order_batch_dialog.dart';
import '../widgets/pre_order_card.dart';
import '../widgets/pre_order_batch_card.dart';
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
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.onSurface, size: 20),
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
              child: Icon(Icons.bookmark_added_rounded,
                  color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'الحجز المسبق والشحنات المجمعة والوساطة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  'إدارة أوردرات شي إن الفردية، كراتين الشحنات المجمعة، وتوزيع الشحن العام',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10.5,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 20),

            // Search Field
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'بحث برقم الحجز، الشحنة، العميل، أو البوليصة...',
                        prefixIcon: const Icon(Icons.search_rounded,
                            size: 18, color: Colors.grey),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  context
                                      .read<PreOrdersCubit>()
                                      .setSearchQuery('');
                                  setState(() {});
                                },
                              )
                            : null,
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.outlineVariant),
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

            // الزر 1: إضافة أوردر فردي
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
              label: const Text(
                '+ أوردر فردي',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
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

            const SizedBox(width: 8),

            // الزر 2: إنشاء شحنة مجمعة (Batch)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
                elevation: 1,
              ),
              icon: const Icon(Icons.all_inbox_rounded, size: 17),
              label: const Text(
                '+ شحنة مجمعة (Batch)',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => BlocProvider.value(
                    value: context.read<PreOrdersCubit>(),
                    child: const CreatePreOrderBatchDialog(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: BlocBuilder<PreOrdersCubit, PreOrdersState>(
        builder: (context, state) {
          if (state.status == PreOrdersViewStatus.loading &&
              state.allOrders.isEmpty &&
              state.allBatches.isEmpty) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (state.status == PreOrdersViewStatus.error &&
              state.allOrders.isEmpty &&
              state.allBatches.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(
                    state.errorMessage ?? 'حدث خطأ أثناء تحميل الحجوزات',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        color: AppColors.error),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<PreOrdersCubit>().loadPreOrders(),
                    child: const Text('إعادة المحاولة',
                        style: TextStyle(fontFamily: 'Cairo')),
                  ),
                ],
              ),
            );
          }

          final isBatchesMode = state.activeMode == 'batches';
          final filteredOrders = state.filteredOrders;
          final filteredBatches = state.filteredBatches;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. شريط التبديل بين (الأوردرات الفردية) و (الشحنات المجمعة)
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                      bottom: BorderSide(color: AppColors.outlineVariant)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // Segmented Tabs
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _modeButton(
                            title: 'الأوردرات الفردية (${state.totalCount})',
                            icon: Icons.person_rounded,
                            isSelected: !isBatchesMode,
                            onTap: () =>
                                context.read<PreOrdersCubit>().setMode('orders'),
                          ),
                          const SizedBox(width: 4),
                          _modeButton(
                            title: 'الشحنات المجمعة (${state.batchesCount})',
                            icon: Icons.inventory_2_rounded,
                            isSelected: isBatchesMode,
                            onTap: () =>
                                context.read<PreOrdersCubit>().setMode('batches'),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Status Chips Bar
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _tabChip(
                              label: 'الكل',
                              count: isBatchesMode
                                  ? state.batchesCount
                                  : state.totalCount,
                              tabId: 'all',
                              currentTab: state.selectedTab,
                              activeColor: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            _tabChip(
                              label: 'قيد التجهيز والشحن',
                              count: isBatchesMode
                                  ? state.pendingBatchesCount
                                  : state.pendingCount,
                              tabId: PreOrderStatuses.pendingProcessing,
                              currentTab: state.selectedTab,
                              activeColor: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            _tabChip(
                              label: 'وصل للمحل وجاهز',
                              count: isBatchesMode
                                  ? state.arrivedBatchesCount
                                  : state.arrivedCount,
                              tabId: PreOrderStatuses.arrivedAtStore,
                              currentTab: state.selectedTab,
                              activeColor: AppColors.primary,
                            ),
                            if (!isBatchesMode) ...[
                              const SizedBox(width: 8),
                              _tabChip(
                                label: 'مكتمل ومستلم',
                                count: state.deliveredCount,
                                tabId: PreOrderStatuses.delivered,
                                currentTab: state.selectedTab,
                                activeColor: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              _tabChip(
                                label: 'مصادرة / لم يستلم',
                                count: state.defaultedCount,
                                tabId: PreOrderStatuses.defaultedForfeited,
                                currentTab: state.selectedTab,
                                activeColor: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              _tabChip(
                                label: 'ملغي ومسترد',
                                count: state.refundedCount,
                                tabId: PreOrderStatuses.refundedCancelled,
                                currentTab: state.selectedTab,
                                activeColor: AppColors.primary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. المحتوى: إما كروت الشحنات المجمعة أو كروت الأوردرات الفردية
              Expanded(
                child: isBatchesMode
                    ? (filteredBatches.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.all_inbox_outlined,
                                    size: 56, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  state.searchQuery.isNotEmpty
                                      ? 'لا توجد شحنات مجمعة مطابقة لبحثك'
                                      : 'لا توجد شحنات مجمعة مسجلة حالياً',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 520,
                              mainAxisExtent: 275,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                            ),
                            itemCount: filteredBatches.length,
                            itemBuilder: (context, index) {
                              final batch = filteredBatches[index];
                              return PreOrderBatchCard(batch: batch);
                            },
                          ))
                    : (filteredOrders.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inventory_2_outlined,
                                    size: 56, color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                Text(
                                  state.searchQuery.isNotEmpty
                                      ? 'لا توجد طلبات حجز مطابقة لبحثك'
                                      : 'لا توجد طلبات حجز مسجلة في هذا القسم',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 430,
                              mainAxisExtent: 275,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                            ),
                            itemCount: filteredOrders.length,
                            itemBuilder: (context, index) {
                              final order = filteredOrders[index];
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
                          )),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _modeButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
    final isSelected = currentTab == tabId;
    return InkWell(
      onTap: () => context.read<PreOrdersCubit>().setTab(tabId),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.onSurface,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
