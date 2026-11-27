import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/standard_date_filter_chips.dart';
import '../../domain/entities/inventory_log_entity.dart';
import '../cubits/inventory_log_cubit.dart';

typedef StockMovementsScreen = InventoryLogsScreen;

class InventoryLogsScreen extends StatelessWidget {
  const InventoryLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<InventoryLogCubit>(),
      child: const _InventoryLogsView(),
    );
  }
}

class _InventoryLogsView extends StatefulWidget {
  const _InventoryLogsView();

  @override
  State<_InventoryLogsView> createState() => _InventoryLogsViewState();
}

class _InventoryLogsViewState extends State<_InventoryLogsView> {
  final TextEditingController _searchController = TextEditingController();
  String _activeDateFilter = 'all';
  DateTimeRange? _customRange;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InventoryLogCubit>();

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
              'سجل حركات المخزن',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
            ),
            Text(
              'تتبع حركات الإدخال، الإخراج، التوريد، والخصم من الرصيد',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            tooltip: 'تحديث',
            onPressed: () => cubit.loadLogs(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: _searchController,
                  onChanged: cubit.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'ابحث باسم المنتج، المقاس، اسم الموظف...',
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.grey),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              cubit.onSearchChanged('');
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

                // Filter Chips
                BlocBuilder<InventoryLogCubit, InventoryLogState>(
                  buildWhen: (prev, curr) => prev.selectedType != curr.selectedType,
                  builder: (context, state) {
                    final filters = [
                      {'key': 'all', 'label': 'الكل'},
                      {'key': 'in', 'label': 'حركات الإدخال (+)'},
                      {'key': 'out', 'label': 'حركات الإخراج (-)'},
                      {'key': 'receive', 'label': 'توريد'},
                      {'key': 'sale', 'label': 'بيع'},
                      {'key': 'return', 'label': 'مرتجع'},
                      {'key': 'stocktake', 'label': 'جرد مخزني'},
                      {'key': 'adjustment', 'label': 'تسوية'},
                    ];

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: filters.map((f) {
                          final isSelected = state.selectedType == f['key'];
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
                              onSelected: (_) => cubit.onTypeFilterChanged(f['key']!),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                StandardDateFilterChips(
                  activeFilter: _activeDateFilter,
                  customRange: _customRange,
                  onFilterChanged: (v) => setState(() => _activeDateFilter = v),
                  onCustomRangePicked: (picked) => setState(() {
                    _customRange = picked;
                    _activeDateFilter = 'custom';
                  }),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Colors.black12),

          // Logs List
          Expanded(
            child: BlocBuilder<InventoryLogCubit, InventoryLogState>(
              builder: (context, state) {
                if (state.status == InventoryLogStatus.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.status == InventoryLogStatus.error) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
                          const SizedBox(height: 12),
                          Text('خطأ: ${state.errorMessage ?? "حدث خطأ غير متوقع"}', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => cubit.loadLogs(),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final filteredLogs = state.logs
                    .where(
                      (l) => StandardDateFilterChips.matchesDate(
                        l.date,
                        _activeDateFilter,
                        _customRange,
                      ),
                    )
                    .toList();

                if (filteredLogs.isEmpty) {
                  final isFiltered = state.searchQuery.isNotEmpty ||
                      state.selectedType != 'all' ||
                      _activeDateFilter != 'all';
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          isFiltered ? 'لا توجد نتائج مطابقة لبحثك' : 'لا توجد حركات مخزن مسجلة حتى الآن',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (isFiltered) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              _searchController.clear();
                              cubit.onSearchChanged('');
                              cubit.onTypeFilterChanged('all');
                              setState(() {
                                _activeDateFilter = 'all';
                                _customRange = null;
                              });
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
                  itemCount: filteredLogs.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final log = filteredLogs[index];
                    return _InventoryLogCard(log: log);
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

class _InventoryLogCard extends StatelessWidget {
  final InventoryLogEntity log;

  const _InventoryLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final isIn = log.type == 'in' ||
        log.type == 'receive' ||
        log.type == 'return' ||
        log.type == 'return_';
    final sign = isIn ? '+' : '-';
    final typeBadge = _getTypeBadge(log.type);
    final dateFormatted = DateFormat('yyyy/MM/dd • HH:mm').format(log.date);

    final productName = (log.productName?.isNotEmpty ?? false)
        ? log.productName!
        : 'منتج غير محدد (${log.productId})';

    final variantInfoParts = <String>[];
    if (log.variantSize?.isNotEmpty ?? false) {
      variantInfoParts.add('المقاس: ${log.variantSize}');
    }
    if (log.variantColor?.isNotEmpty ?? false) {
      variantInfoParts.add('اللون: ${log.variantColor}');
    }
    final variantInfo = variantInfoParts.join(' • ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon indicator
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(typeBadge.icon, color: typeBadge.color, size: 24),
          ),
          const SizedBox(width: 12),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        productName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Text(
                        typeBadge.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: typeBadge.color,
                        ),
                      ),
                    ),
                  ],
                ),
                if (variantInfo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    variantInfo,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'بواسطة: ${log.userName ?? log.userId}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    Text(
                      dateFormatted,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Quantity badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Text(
              '$sign${log.quantity}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isIn ? AppColors.success : AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _TypeBadge _getTypeBadge(String type) {
    switch (type) {
      case 'receive':
      case 'in':
        return _TypeBadge(
          label: 'توريد / استلام',
          color: AppColors.success,
          backgroundColor: const Color(0xFFF1F5F9),
          icon: Icons.arrow_downward_rounded,
        );
      case 'sale':
      case 'out':
        return _TypeBadge(
          label: 'بيع',
          color: AppColors.error,
          backgroundColor: const Color(0xFFF1F5F9),
          icon: Icons.arrow_upward_rounded,
        );
      case 'return':
      case 'return_':
        return _TypeBadge(
          label: 'مرتجع مبيعات',
          color: const Color(0xFF2563EB),
          backgroundColor: const Color(0xFFF1F5F9),
          icon: Icons.replay_rounded,
        );
      case 'purchase_return':
        return _TypeBadge(
          label: 'مرتجع مشتريات',
          color: const Color(0xFFD97706),
          backgroundColor: const Color(0xFFF1F5F9),
          icon: Icons.assignment_return_rounded,
        );
      case 'adjustment':
        return _TypeBadge(
          label: 'تسوية رصيد',
          color: const Color(0xFF475569),
          backgroundColor: const Color(0xFFF1F5F9),
          icon: Icons.tune_rounded,
        );
      case 'stocktake':
        return _TypeBadge(
          label: 'جرد مخزني',
          color: const Color(0xFF475569),
          backgroundColor: const Color(0xFFF1F5F9),
          icon: Icons.fact_check_rounded,
        );
      default:
        return _TypeBadge(
          label: type,
          color: const Color(0xFF475569),
          backgroundColor: const Color(0xFFF1F5F9),
          icon: Icons.sync_alt_rounded,
        );
    }
  }
}

class _TypeBadge {
  final String label;
  final Color color;
  final Color backgroundColor;
  final IconData icon;

  _TypeBadge({
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.icon,
  });
}
