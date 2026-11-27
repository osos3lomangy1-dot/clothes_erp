import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../cubits/smart_inventory_cubit.dart';
import '../../domain/entities/smart_inventory_entities.dart';

class SmartInventoryReportsScreen extends StatelessWidget {
  final int initialTabIndex;
  final bool embedded;

  const SmartInventoryReportsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<SmartInventoryCubit>(),
      child: _SmartInventoryReportsView(
        initialTabIndex: initialTabIndex,
        embedded: embedded,
      ),
    );
  }
}

class _SmartInventoryReportsView extends StatefulWidget {
  final int initialTabIndex;
  final bool embedded;

  const _SmartInventoryReportsView({
    required this.initialTabIndex,
    required this.embedded,
  });

  @override
  State<_SmartInventoryReportsView> createState() =>
      _SmartInventoryReportsViewState();
}

class _SmartInventoryReportsViewState extends State<_SmartInventoryReportsView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SmartInventoryCubit>();
    final tabBar = TabBar(
      controller: _tabController,
      labelColor: AppColors.primary,
      unselectedLabelColor: Colors.grey.shade600,
      indicatorColor: AppColors.primary,
      indicatorWeight: 3,
      labelStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      unselectedLabelStyle: const TextStyle(
        fontFamily: 'Cairo',
        fontWeight: FontWeight.normal,
        fontSize: 13,
      ),
      tabs: const [
        Tab(
          icon: Icon(Icons.shopping_cart_checkout_rounded, size: 20),
          text: 'اقتراح طلب الشراء',
        ),
        Tab(
          icon: Icon(Icons.hourglass_bottom_rounded, size: 20),
          text: 'المنتجات الراكدة',
        ),
        Tab(
          icon: Icon(Icons.history_edu_rounded, size: 20),
          text: 'كارت حركة الصنف',
        ),
      ],
    );

    final tabView = TabBarView(
      controller: _tabController,
      children: const [
        _ReorderSuggestionsTab(),
        _DeadStockTab(),
        _StockMovementCardTab(),
      ],
    );

    if (widget.embedded) {
      return Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(child: tabBar),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
                  tooltip: 'تحديث البيانات',
                  onPressed: () => cubit.init(),
                ),
              ],
            ),
          ),
          Expanded(child: tabView),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تقارير المخزون الذكية',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'اقتراح طلب الشراء، تحليل الرواكد، وكارت حركة كل صنف',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            tooltip: 'تحديث البيانات',
            onPressed: () => cubit.init(),
          ),
        ],
        bottom: tabBar,
      ),
      body: tabView,
    );
  }
}

// =============================================================================
// TAB 1: REORDER SUGGESTIONS
// =============================================================================

class _ReorderSuggestionsTab extends StatelessWidget {
  const _ReorderSuggestionsTab();

  void _copyPurchaseList(BuildContext context, List<ReorderSuggestionEntity> list) {
    if (list.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('*طلب شراء بضاعة ونواقص مخزن*');
    buffer.writeln('تاريخ: ${DateFormat('yyyy/MM/dd').format(DateTime.now())}');
    buffer.writeln('--------------------------------');
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      final sizeColor = (item.color != '-' || item.size != '-')
          ? ' (${item.color} / ${item.size})'
          : '';
      buffer.writeln(
        '${i + 1}. ${item.productName}$sizeColor - باركود: ${item.sku} -> مطلوب: [ ${item.suggestedReorderQty} قطعة ] (رصيده حالياً: ${item.currentStock})',
      );
    }
    buffer.writeln('--------------------------------');
    buffer.writeln('إجمالي الأصناف: ${list.length}');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم نسخ قائمة النواقص إلى الحافظة بنجاح جاهزة للإرسال!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SmartInventoryCubit, SmartInventoryState>(
      builder: (context, state) {
        if (state.reorderStatus == SmartInventoryStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.reorderStatus == SmartInventoryStatus.error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(state.errorMessage ?? 'حدث خطأ أثناء تحميل النواقص'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<SmartInventoryCubit>().loadReorderSuggestions(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }

        final items = state.reorderSuggestions;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Top Summary Cards
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'أصناف تحتاج إعادة طلب',
                    value: '${items.length} صنف',
                    icon: Icons.inventory_2_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'التكلفة المقدرة للشراء',
                    value: '${Money(state.totalReorderCostPiasters).toDisplay()} ج.م',
                    icon: Icons.payments_outlined,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Controls & Action Bar
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'قائمة الأصناف الأقل من الحد الأدنى والكميات المقترحة:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                if (items.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _copyPurchaseList(context, items),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('نسخ قائمة الشراء'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (items.isEmpty)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, size: 54, color: Colors.green),
                      SizedBox(height: 12),
                      Text(
                        'المخزون في حالة ممتازة!',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'لا توجد أصناف وصلت للحد الأدنى في الوقت الحالي.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...items.map((item) => _ReorderItemCard(item: item)),
          ],
        );
      },
    );
  }
}

class _ReorderItemCard extends StatelessWidget {
  final ReorderSuggestionEntity item;

  const _ReorderItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isOut = item.currentStock <= 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isOut ? AppColors.error.withValues(alpha: 0.5) : Colors.black12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isOut
                    ? AppColors.error.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isOut ? Icons.warning_amber_rounded : Icons.shopping_basket_outlined,
                color: isOut ? AppColors.error : AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الباركود: ${item.sku} | القسم: ${item.categoryName} | المقاس: ${item.size} | اللون: ${item.color}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _badge(
                        'الرصيد الحالي: ${item.currentStock}',
                        isOut ? AppColors.error : AppColors.primary,
                      ),
                      _badge('حد الطلب: ${item.minStock}', Colors.grey.shade700),
                      _badge(
                        'مبيعات 30 يوم: ${item.soldLast30Days}',
                        AppColors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'مطلوب: +${item.suggestedReorderQty}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'تكلفة: ${Money(item.totalEstimatedCostPiasters).toDisplay()} ج.م',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

// =============================================================================
// TAB 2: DEAD STOCK REPORT
// =============================================================================

class _DeadStockTab extends StatelessWidget {
  const _DeadStockTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SmartInventoryCubit>();

    return BlocBuilder<SmartInventoryCubit, SmartInventoryState>(
      builder: (context, state) {
        if (state.deadStockStatus == SmartInventoryStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.deadStockStatus == SmartInventoryStatus.error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(state.errorMessage ?? 'حدث خطأ أثناء تحميل تقرير الرواكد'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => cubit.loadDeadStock(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }

        final items = state.deadStockItems;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Top Summary Cards
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'رأس المال المجمد (بالتكلفة)',
                    value: '${Money(state.totalFrozenCapitalPiasters).toDisplay()} ج.م',
                    icon: Icons.lock_clock_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'القيمة البيعية المعطلة',
                    value: '${Money(state.totalLostRevenuePotentialPiasters).toDisplay()} ج.م',
                    icon: Icons.savings_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SummaryCard(
                    title: 'إجمالي القطع الراكدة',
                    value: '${state.totalDeadUnits} قطعة (${items.length} صنف)',
                    icon: Icons.layers_clear_outlined,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Period Selector
            Row(
              children: [
                const Text(
                  'فترة الركود (بدون أي بيع):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 10),
                _periodChip(context, label: '30 يوماً', days: 30, selected: state.deadStockDormantDays == 30),
                const SizedBox(width: 8),
                _periodChip(context, label: '60 يوماً', days: 60, selected: state.deadStockDormantDays == 60),
                const SizedBox(width: 8),
                _periodChip(context, label: '90 يوماً', days: 90, selected: state.deadStockDormantDays == 90),
              ],
            ),
            const SizedBox(height: 16),

            if (items.isEmpty)
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 54, color: Colors.green),
                      SizedBox(height: 12),
                      Text(
                        'لا توجد أصناف راكدة!',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'جميع البضائع المتوفرة بالمخزن تم تسجيل مبيعات لها خلال الفترة المحددة.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...items.map((item) => _DeadStockItemCard(item: item)),
          ],
        );
      },
    );
  }

  Widget _periodChip(
    BuildContext context, {
    required String label,
    required int days,
    required bool selected,
  }) {
    return InkWell(
      onTap: () => context.read<SmartInventoryCubit>().loadDeadStock(dormantDays: days),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'Cairo',
            color: selected ? Colors.white : AppColors.onSurface,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _DeadStockItemCard extends StatelessWidget {
  final DeadStockItemEntity item;

  const _DeadStockItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.pause_circle_outline_rounded,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الباركود: ${item.sku} | القسم: ${item.categoryName} | المقاس: ${item.size} | اللون: ${item.color}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'الكمية الراكدة: ${item.currentStock} قطعة',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'تكلفة الوحدة: ${Money(item.costPricePiasters).toDisplay()} ج.م',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${Money(item.frozenCapitalPiasters).toDisplay()} ج.م',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'رأس مال مجمد',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TAB 3: STOCK MOVEMENT CARD
// =============================================================================

class _StockMovementCardTab extends StatelessWidget {
  const _StockMovementCardTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SmartInventoryCubit>();

    return BlocBuilder<SmartInventoryCubit, SmartInventoryState>(
      builder: (context, state) {
        final variants = state.variantsList;
        final selectedId = state.selectedVariantId;

        return Column(
          children: [
            // Variant Selector Container
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: AppColors.primary),
                  const SizedBox(width: 10),
                  const Text(
                    'اختر الصنف لعرض كارت حركته:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedId,
                          hint: const Text('اختر الصنف...'),
                          items: variants.map((v) {
                            return DropdownMenuItem<String>(
                              value: v.id,
                              child: Text(
                                '${v.label} [${v.sku}]',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              cubit.loadStockMovementCard(val);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Expanded(
              child: Builder(
                builder: (context) {
                  if (state.cardStatus == SmartInventoryStatus.loading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state.movementCardItems.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_rounded, size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'لا توجد حركات مسجلة لهذا الصنف حتى الآن',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.movementCardItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = state.movementCardItems[index];
                      final isPositive = item.qtyDelta > 0;

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Colors.black12),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isPositive
                                  ? Colors.green.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isPositive ? Icons.add_circle_outline : Icons.remove_circle_outline,
                              color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                              size: 22,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                item.typeLabel,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              if (item.refId != null && item.refId!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${item.refId!.length > 8 ? item.refId!.substring(0, 8) : item.refId}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(item.date)} | بواسطة: ${item.userName}${item.reason != null && item.reason!.isNotEmpty ? ' | السبب: ${item.reason}' : ''}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isPositive ? '+${item.qtyDelta}' : '${item.qtyDelta}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                                ),
                              ),
                              Text(
                                'الرصيد بعد: ${item.runningBalance}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
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
    );
  }
}

// =============================================================================
// REUSABLE SUMMARY CARD
// =============================================================================

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
