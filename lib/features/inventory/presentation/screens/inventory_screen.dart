import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/excel_service.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../barcode_printing/domain/models/barcode_label_item.dart';
import '../../../barcode_printing/presentation/dialogs/barcode_print_dialog.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../cubits/inventory_cubit.dart';
import '../cubits/inventory_state.dart';
import '../widgets/inventory_action_dialogs.dart';
import 'blind_receive_screen.dart';

enum _InventoryStatusFilter { all, inStock, lowStock, outOfStock }

enum _InventorySort { lowestQty, highestQty, highestValue, nameAsc }

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _InventoryStatusFilter _statusFilter = _InventoryStatusFilter.all;
  String? _selectedCategory; // null = all categories
  _InventorySort _sort = _InventorySort.lowestQty;
  bool _exporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isAdmin(BuildContext context) {
    try {
      final auth = context.watch<AuthCubit>().state;
      if (auth is AuthAuthenticated) {
        return auth.user.role.toLowerCase() != 'cashier';
      }
    } catch (_) {}
    return true;
  }

  String _currentUserId(BuildContext context) {
    try {
      final auth = context.read<AuthCubit>().state;
      if (auth is AuthAuthenticated) return auth.user.id;
    } catch (_) {}
    return 'admin';
  }

  Future<void> _openReceiveShipmentScreen(BuildContext context) async {
    final cubit = context.read<InventoryCubit>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const BlindReceiveScreen(),
      ),
    );
    if (mounted) {
      cubit.loadInventory();
    }
  }

  Future<void> _exportInventoryExcel() async {
    setState(() => _exporting = true);
    try {
      final path = await ExcelService().exportProducts();
      if (mounted && path != null) {
        AppFeedback.showSuccess(
          context,
          'تم تصدير جرد المخزون بنجاح في:\n$path',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'تعذر تصدير المخزون: $e');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openBarcodePrint(BuildContext context, VariantEntity item) {
    showDialog<void>(
      context: context,
      builder: (_) => BarcodePrintDialog(
        title: 'طباعة باركود: ${item.productName}',
        initialItems: [
          BarcodeLabelItem(
            variantId: item.id,
            productName: item.productName,
            sku: item.productCode,
            color: item.color,
            size: item.size,
            salePricePiasters: item.salePrice,
            copies: item.quantity > 0 ? item.quantity : 1,
          ),
        ],
      ),
    );
  }

  List<VariantEntity> _filterAndSort(List<VariantEntity> raw) {
    var list = raw.where((item) {
      if (_searchQuery.isNotEmpty) {
        final name = item.productName.toLowerCase();
        final code = item.productCode.toLowerCase();
        final color = item.color.toLowerCase();
        final size = item.size.toLowerCase();
        final cat = (item.categoryName ?? '').toLowerCase();
        if (!name.contains(_searchQuery) &&
            !code.contains(_searchQuery) &&
            !color.contains(_searchQuery) &&
            !size.contains(_searchQuery) &&
            !cat.contains(_searchQuery)) {
          return false;
        }
      }
      if (_selectedCategory != null &&
          (item.categoryName ?? 'غير مصنف') != _selectedCategory) {
        return false;
      }
      final isOut = item.quantity == 0;
      final isLow = !isOut && item.quantity <= item.minStock;
      switch (_statusFilter) {
        case _InventoryStatusFilter.all:
          return true;
        case _InventoryStatusFilter.inStock:
          return !isOut && !isLow;
        case _InventoryStatusFilter.lowStock:
          return isLow;
        case _InventoryStatusFilter.outOfStock:
          return isOut;
      }
    }).toList();

    list.sort((a, b) {
      switch (_sort) {
        case _InventorySort.lowestQty:
          return a.quantity.compareTo(b.quantity);
        case _InventorySort.highestQty:
          return b.quantity.compareTo(a.quantity);
        case _InventorySort.highestValue:
          final valA = a.quantity * a.costPrice;
          final valB = b.quantity * b.costPrice;
          return valB.compareTo(valA);
        case _InventorySort.nameAsc:
          return a.productName.compareTo(b.productName);
      }
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _isAdmin(context);

    return BlocProvider(
      create: (context) => getIt<InventoryCubit>()..loadInventory(),
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: AppColors.surface,
            appBar: AppBar(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.onSurface,
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
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إدارة المخزون والتقييم',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 19,
                      color: AppColors.onSurface,
                    ),
                  ),
                  Text(
                    'تقييم رأس المال، متابعة الأرصدة، تسوية التالف، وحركات كل صنف',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              actions: [
                if (isAdmin)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    child: OutlinedButton.icon(
                      key: const Key('export_inventory_excel_btn'),
                      onPressed: _exporting ? null : _exportInventoryExcel,
                      icon: _exporting
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.table_view_rounded, size: 18),
                      label: const Text('تصدير إكسيل'),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  child: ElevatedButton.icon(
                    key: const Key('inventory_receive_shipment_btn'),
                    icon: const Icon(
                      Icons.local_shipping_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: const Text(
                      'استلام شحنة بضاعة',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _openReceiveShipmentScreen(context),
                  ),
                ),
              ],
            ),
            body: BlocBuilder<InventoryCubit, InventoryState>(
              builder: (context, state) {
                if (state is InventoryLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (state is InventoryError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 54,
                          color: AppColors.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          state.message,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () =>
                              context.read<InventoryCubit>().loadInventory(),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                } else if (state is InventoryLoaded) {
                  final allItems = state.items;
                  final categories = <String>{
                    for (final i in allItems) (i.categoryName ?? 'غير مصنف'),
                  }.toList()
                    ..sort();
                  if (_selectedCategory != null &&
                      !categories.contains(_selectedCategory)) {
                    _selectedCategory = null;
                  }

                  final filteredItems = _filterAndSort(allItems);

                  // Valuation & Stock KPIs (on filtered set so manager sees live valuation per category)
                  final totalQty = filteredItems.fold<int>(
                    0,
                    (sum, i) => sum + i.quantity,
                  );
                  final totalCostPiasters = filteredItems.fold<int>(
                    0,
                    (sum, i) => sum + (i.quantity * i.costPrice),
                  );
                  final totalRetailPiasters = filteredItems.fold<int>(
                    0,
                    (sum, i) => sum + (i.quantity * i.salePrice),
                  );
                  final lowCount = allItems
                      .where((i) => i.quantity > 0 && i.quantity <= i.minStock)
                      .length;
                  final outCount =
                      allItems.where((i) => i.quantity == 0).length;

                  return Column(
                    children: [
                      // Valuation KPIs + Search + Category + Sort + Status Chips
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // KPI Cards Row
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _kpiCard(
                                    'الأصناف',
                                    '${filteredItems.length}',
                                    Icons.style_rounded,
                                    AppColors.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  _kpiCard(
                                    'إجمالي القطع',
                                    '$totalQty قطعة',
                                    Icons.inventory_2_rounded,
                                    Colors.indigo,
                                  ),
                                  if (isAdmin) ...[
                                    const SizedBox(width: 10),
                                    _kpiCard(
                                      'قيمة المخزون (بالتكلفة)',
                                      '${Money(totalCostPiasters).toDisplay()} ج.م',
                                      Icons.account_balance_wallet_rounded,
                                      Colors.teal.shade800,
                                    ),
                                    const SizedBox(width: 10),
                                    _kpiCard(
                                      'القيمة البيعية المتوقعة',
                                      '${Money(totalRetailPiasters).toDisplay()} ج.م',
                                      Icons.trending_up_rounded,
                                      Colors.green.shade800,
                                    ),
                                  ],
                                  const SizedBox(width: 10),
                                  _kpiCard(
                                    'منخفض / نفذ',
                                    '$lowCount منخفض • $outCount نفذ',
                                    Icons.warning_amber_rounded,
                                    (lowCount + outCount) > 0
                                        ? AppColors.error
                                        : Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Search + Category + Sort
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 340,
                                  child: TextField(
                                    controller: _searchController,
                                    decoration: InputDecoration(
                                      hintText:
                                          'ابحث بالاسم، الكود، اللون، المقاس، التصنيف...',
                                      prefixIcon: Icon(
                                        Icons.search,
                                        color: AppColors.primary,
                                      ),
                                      suffixIcon: _searchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () {
                                                _searchController.clear();
                                                setState(
                                                  () => _searchQuery = '',
                                                );
                                              },
                                            )
                                          : null,
                                      isDense: true,
                                    ),
                                    onChanged: (val) => setState(
                                      () =>
                                          _searchQuery = val.trim().toLowerCase(),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 200,
                                  child: DropdownButtonFormField<String?>(
                                    initialValue: _selectedCategory,
                                    isDense: true,
                                    decoration: const InputDecoration(
                                      labelText: 'التصنيف',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('كل التصنيفات'),
                                      ),
                                      for (final cat in categories)
                                        DropdownMenuItem<String?>(
                                          value: cat,
                                          child: Text(
                                            cat,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                    onChanged: (v) =>
                                        setState(() => _selectedCategory = v),
                                  ),
                                ),
                                SizedBox(
                                  width: 210,
                                  child: DropdownButtonFormField<_InventorySort>(
                                    initialValue: _sort,
                                    isDense: true,
                                    decoration: const InputDecoration(
                                      labelText: 'ترتيب حسب',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                    ),
                                    items: [
                                      const DropdownMenuItem(
                                        value: _InventorySort.lowestQty,
                                        child: Text('الأقل كمية أولاً'),
                                      ),
                                      const DropdownMenuItem(
                                        value: _InventorySort.highestQty,
                                        child: Text('الأعلى كمية أولاً'),
                                      ),
                                      if (isAdmin)
                                        const DropdownMenuItem(
                                          value: _InventorySort.highestValue,
                                          child: Text('الأعلى قيمة مالية'),
                                        ),
                                      const DropdownMenuItem(
                                        value: _InventorySort.nameAsc,
                                        child: Text('اسم المنتج (أ - ي)'),
                                      ),
                                    ],
                                    onChanged: (v) {
                                      if (v != null) setState(() => _sort = v);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Status Filter Chips
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _statusChip(
                                  _InventoryStatusFilter.all,
                                  'الكل (${allItems.length})',
                                  AppColors.primary,
                                ),
                                _statusChip(
                                  _InventoryStatusFilter.inStock,
                                  'متوفر (${allItems.length - lowCount - outCount})',
                                  Colors.green.shade800,
                                ),
                                _statusChip(
                                  _InventoryStatusFilter.lowStock,
                                  'منخفض ($lowCount)',
                                  Colors.orange.shade900,
                                ),
                                _statusChip(
                                  _InventoryStatusFilter.outOfStock,
                                  'نفذ ($outCount)',
                                  AppColors.error,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Inventory List
                      Expanded(
                        child: filteredItems.isEmpty
                            ? AppEmptyState(
                                icon: Icons.inventory_2_outlined,
                                title: allItems.isEmpty
                                    ? 'المخزن فارغ حالياً'
                                    : 'لا توجد أصناف مطابقة للبحث أو التصفية',
                                subtitle: allItems.isEmpty
                                    ? 'لم يتم تسجيل أي أصناف أو كميات بالمخزن بعد. يمكنك استلام شحنة بضاعة جديدة الآن.'
                                    : 'جرّب تغيير فلتر الحالة أو التصنيف أو مسح نص البحث.',
                                actionLabel: allItems.isEmpty
                                    ? 'استلام شحنة بضاعة'
                                    : null,
                                onAction: allItems.isEmpty
                                    ? () => _openReceiveShipmentScreen(context)
                                    : null,
                              )
                            : RefreshIndicator(
                                onRefresh: () => context
                                    .read<InventoryCubit>()
                                    .loadInventory(),
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  itemCount: filteredItems.length,
                                  itemBuilder: (context, index) {
                                    return _buildItemCard(
                                      context,
                                      filteredItems[index],
                                      isAdmin: isAdmin,
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    VariantEntity item, {
    required bool isAdmin,
  }) {
    final bool isOut = item.quantity == 0;
    final bool isLow = !isOut && item.quantity <= item.minStock;
    final lineCostPiasters = item.quantity * item.costPrice;

    return Card(
      elevation: 0.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOut
              ? AppColors.error.withValues(alpha: 0.35)
              : (isLow
                    ? Colors.orange.withValues(alpha: 0.45)
                    : Colors.grey.shade200),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isOut
                  ? Colors.red.shade50
                  : (isLow ? Colors.orange.shade50 : AppColors.surfaceContainer),
              child: Icon(
                isOut
                    ? Icons.error_outline
                    : (isLow
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline),
                color: isOut
                    ? AppColors.error
                    : (isLow ? Colors.orange.shade800 : AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        item.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                        ),
                      ),
                      if (item.categoryName != null &&
                          item.categoryName!.isNotEmpty)
                        _badge(
                          item.categoryName!,
                          bg: Colors.blue.shade50,
                          fg: Colors.blue.shade900,
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isOut
                              ? AppColors.error.withValues(alpha: 0.1)
                              : (isLow
                                    ? Colors.orange.withValues(alpha: 0.12)
                                    : Colors.green.withValues(alpha: 0.1)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isOut ? 'نفذ المخزون' : (isLow ? 'منخفض' : 'متوفر'),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isOut
                                ? AppColors.error
                                : (isLow
                                      ? Colors.orange.shade900
                                      : Colors.green.shade800),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _badge('SKU: ${item.productCode}'),
                      _badge('اللون: ${item.color}'),
                      _badge('المقاس: ${item.size}'),
                      _badge(
                        'البيع: ${Money(item.salePrice).toDisplay()} ج.م',
                        bg: Colors.teal.shade50,
                        fg: Colors.teal.shade900,
                      ),
                      if (item.wholesalePrice > 0)
                        _badge(
                          'جملة: ${Money(item.wholesalePrice).toDisplay()} ج.م',
                          bg: Colors.purple.shade50,
                          fg: Colors.purple.shade800,
                        ),
                      if (isAdmin) ...[
                        _badge(
                          'التكلفة: ${Money(item.costPrice).toDisplay()} ج.م',
                        ),
                        if (item.quantity > 0)
                          _badge(
                            'قيمة الرصيد: ${Money(lineCostPiasters).toDisplay()} ج.م',
                            bg: Colors.amber.shade50,
                            fg: Colors.amber.shade900,
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.quantity} قطعة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: isOut
                        ? AppColors.error
                        : (isLow ? Colors.orange.shade900 : AppColors.primary),
                  ),
                ),
                Text(
                  'حد الطلب: ${item.minStock}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAdmin)
                  IconButton(
                    tooltip: 'تسوية رصيد / خصم تالف (للمدير فقط)',
                    icon: Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: Colors.teal.shade700,
                    ),
                    onPressed: () => showInventoryAdjustmentDialog(
                      context,
                      item: item,
                      cubit: context.read<InventoryCubit>(),
                      userId: _currentUserId(context),
                    ),
                  ),
                IconButton(
                  tooltip: 'سجل حركات الصنف',
                  icon: Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: Colors.indigo.shade700,
                  ),
                  onPressed: () => showVariantMovementHistoryDialog(
                    context,
                    item: item,
                    cubit: context.read<InventoryCubit>(),
                  ),
                ),
                IconButton(
                  tooltip: 'طباعة باركود الصنف',
                  icon: Icon(
                    Icons.qr_code_2_rounded,
                    size: 20,
                    color: Colors.grey.shade800,
                  ),
                  onPressed: () => _openBarcodePrint(context, item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(
    _InventoryStatusFilter value,
    String label,
    Color activeColor,
  ) {
    final selected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _statusFilter = value),
      selectedColor: activeColor.withValues(alpha: 0.14),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? activeColor : Colors.grey.shade800,
      ),
    );
  }

  Widget _badge(String text, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: bg != null ? FontWeight.w600 : FontWeight.normal,
          color: fg ?? Colors.grey.shade800,
        ),
      ),
    );
  }
}
