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
import '../../../reports/presentation/screens/smart_inventory_reports_screen.dart';

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
                IconButton(
                  icon: Icon(Icons.analytics_rounded, color: AppColors.primary),
                  tooltip: 'تقارير المخزون الذكية (النواقص والرواكد وحركة الأصناف)',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SmartInventoryReportsScreen(),
                      ),
                    );
                  },
                ),
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
                  final inStockCount = allItems.length - lowCount - outCount;
                  final expectedMarginPiasters =
                      totalRetailPiasters - totalCostPiasters;
                  final hasActiveFilters = _searchQuery.isNotEmpty ||
                      _selectedCategory != null ||
                      _statusFilter != _InventoryStatusFilter.all;

                  return Column(
                    children: [
                      const Divider(height: 1),
                      // Zone 1: Clean Equal-Width Executive KPI Cards on soft surface
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final cards = <Widget>[
                              _executiveKpiCard(
                                title: 'المخزون المتاح',
                                value: '$totalQty قطعة',
                                subtitle: '${filteredItems.length} صنف معروض',
                                icon: Icons.inventory_2_outlined,
                                accent: AppColors.primary,
                              ),
                              if (isAdmin)
                                _executiveKpiCard(
                                  title: 'رأس المال (بالتكلفة)',
                                  value:
                                      '${Money(totalCostPiasters).toDisplay()} ج.م',
                                  subtitle: 'التكلفة الإجمالية للبضاعة',
                                  icon: Icons.account_balance_wallet_outlined,
                                  accent: Colors.teal.shade700,
                                ),
                              if (isAdmin)
                                _executiveKpiCard(
                                  title: 'القيمة البيعية المتوقعة',
                                  value:
                                      '${Money(totalRetailPiasters).toDisplay()} ج.م',
                                  subtitle: expectedMarginPiasters >= 0
                                      ? 'هامش ربح متوقع: +${Money(expectedMarginPiasters).toDisplay()} ج.م'
                                      : 'هامش متوقع: ${Money(expectedMarginPiasters).toDisplay()} ج.م',
                                  icon: Icons.trending_up_rounded,
                                  accent: Colors.green.shade700,
                                ),
                              _executiveKpiCard(
                                title: 'تنبيهات النقص',
                                value: (lowCount + outCount) == 0
                                    ? 'المخزون سليم'
                                    : '${lowCount + outCount} صنف يحتاج متابعة',
                                subtitle: '$lowCount منخفض • $outCount نفذ',
                                icon: (lowCount + outCount) == 0
                                    ? Icons.verified_outlined
                                    : Icons.warning_amber_rounded,
                                accent: outCount > 0
                                    ? AppColors.error
                                    : (lowCount > 0
                                          ? Colors.orange.shade800
                                          : Colors.teal.shade700),
                              ),
                            ];

                            if (constraints.maxWidth >= 880) {
                              return Row(
                                children: [
                                  for (var i = 0; i < cards.length; i++) ...[
                                    Expanded(child: cards[i]),
                                    if (i < cards.length - 1)
                                      const SizedBox(width: 12),
                                  ],
                                ],
                              );
                            }

                            final cardWidth =
                                (constraints.maxWidth - 12) / 2;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: cards
                                  .map(
                                    (c) => SizedBox(
                                      width: cardWidth > 220
                                          ? cardWidth
                                          : constraints.maxWidth,
                                      child: c,
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                      ),
                      // Zone 2: Unified Compact Search, Filter & Segmented Status Bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LayoutBuilder(
                                builder: (context, c) {
                                  final searchField = TextField(
                                    controller: _searchController,
                                    decoration: InputDecoration(
                                      hintText:
                                          'ابحث بالاسم، الكود (SKU)، اللون، المقاس، أو التصنيف...',
                                      hintStyle: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade500,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.search_rounded,
                                        size: 20,
                                        color: Colors.grey.shade600,
                                      ),
                                      suffixIcon: _searchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.close_rounded,
                                                size: 18,
                                              ),
                                              onPressed: () {
                                                _searchController.clear();
                                                setState(
                                                  () => _searchQuery = '',
                                                );
                                              },
                                            )
                                          : null,
                                      filled: true,
                                      fillColor: const Color(0xFFF8FAFC),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 11,
                                      ),
                                    ),
                                    onChanged: (val) => setState(
                                      () => _searchQuery =
                                          val.trim().toLowerCase(),
                                    ),
                                  );

                                  final categoryDropdown =
                                      DropdownButtonFormField<String?>(
                                    initialValue: _selectedCategory,
                                    isDense: true,
                                    decoration: const InputDecoration(
                                      labelText: 'التصنيف',
                                      filled: true,
                                      fillColor: Color(0xFFF8FAFC),
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
                                  );

                                  final sortDropdown =
                                      DropdownButtonFormField<_InventorySort>(
                                    initialValue: _sort,
                                    isDense: true,
                                    decoration: const InputDecoration(
                                      labelText: 'الترتيب',
                                      filled: true,
                                      fillColor: Color(0xFFF8FAFC),
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
                                  );

                                  if (c.maxWidth >= 720) {
                                    return Row(
                                      children: [
                                        Expanded(child: searchField),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          width: 195,
                                          child: categoryDropdown,
                                        ),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          width: 195,
                                          child: sortDropdown,
                                        ),
                                      ],
                                    );
                                  }

                                  return Column(
                                    children: [
                                      searchField,
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(child: categoryDropdown),
                                          const SizedBox(width: 10),
                                          Expanded(child: sortDropdown),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _segmentTab(
                                              _InventoryStatusFilter.all,
                                              'الكل',
                                              allItems.length,
                                              AppColors.primary,
                                            ),
                                            _segmentTab(
                                              _InventoryStatusFilter.inStock,
                                              'متوفر',
                                              inStockCount,
                                              Colors.teal.shade700,
                                            ),
                                            _segmentTab(
                                              _InventoryStatusFilter.lowStock,
                                              'منخفض',
                                              lowCount,
                                              Colors.orange.shade800,
                                            ),
                                            _segmentTab(
                                              _InventoryStatusFilter.outOfStock,
                                              'نفذ',
                                              outCount,
                                              AppColors.error,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (hasActiveFilters) ...[
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchQuery = '';
                                          _selectedCategory = null;
                                          _statusFilter =
                                              _InventoryStatusFilter.all;
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.filter_alt_off_rounded,
                                        size: 16,
                                      ),
                                      label: const Text(
                                        'مسح الفلاتر',
                                        style: TextStyle(fontSize: 12.5),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
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
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.outlineVariant, width: 1.0),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFF1F5F9),
              child: Icon(
                isOut
                    ? Icons.error_outline_rounded
                    : (isLow
                          ? Icons.warning_amber_rounded
                          : Icons.inventory_2_outlined),
                color: isOut
                    ? AppColors.error
                    : (isLow ? AppColors.warning : AppColors.primary),
                size: 20,
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
                          color: AppColors.onSurface,
                        ),
                      ),
                      if (item.categoryName != null &&
                          item.categoryName!.isNotEmpty)
                        _badge(
                          item.categoryName!,
                          bg: const Color(0xFFF1F5F9),
                          fg: const Color(0xFF475569),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isOut
                              ? const Color(0xFFFEF2F2)
                              : (isLow
                                    ? const Color(0xFFFFFBEB)
                                    : const Color(0xFFF1F5F9)),
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
                                      ? AppColors.warning
                                      : const Color(0xFF475569)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _badge('SKU: ${item.productCode}'),
                      if (item.color.isNotEmpty) _badge('اللون: ${item.color}'),
                      if (item.size.isNotEmpty) _badge('المقاس: ${item.size}'),
                      Text(
                        'البيع: ${Money(item.salePrice).toDisplay()} ج.م',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: AppColors.onSurface,
                        ),
                      ),
                      if (item.wholesalePrice > 0)
                        Text(
                          'الجملة: ${Money(item.wholesalePrice).toDisplay()} ج.م',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      if (isAdmin) ...[
                        Text(
                          'التكلفة: ${Money(item.costPrice).toDisplay()} ج.م',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        if (item.quantity > 0)
                          Text(
                            'قيمة الرصيد: ${Money(lineCostPiasters).toDisplay()} ج.م',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLow)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.warning_amber_rounded,
                            size: 16, color: AppColors.warning),
                      )
                    else if (isOut)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.error_outline_rounded,
                            size: 16, color: AppColors.error),
                      ),
                    Text(
                      '${item.quantity} قطعة',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: isAdmin
                      ? () => showEditMinStockDialog(
                            context,
                            item: item,
                            cubit: context.read<InventoryCubit>(),
                            userId: _currentUserId(context),
                          )
                      : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'حد الطلب: ${item.minStock}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 3),
                          Icon(
                            Icons.edit_outlined,
                            size: 12,
                            color: AppColors.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAdmin) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'تعديل حد إعادة الطلب (حد الأمان)',
                    icon: Icon(
                      Icons.notifications_active_outlined,
                      size: 20,
                      color: Colors.amber.shade900,
                    ),
                    onPressed: () => showEditMinStockDialog(
                      context,
                      item: item,
                      cubit: context.read<InventoryCubit>(),
                      userId: _currentUserId(context),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
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
                ],
                IconButton(
                  visualDensity: VisualDensity.compact,
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
                  visualDensity: VisualDensity.compact,
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

  Widget _executiveKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentTab(
    _InventoryStatusFilter value,
    String label,
    int count,
    Color activeColor,
  ) {
    final selected = _statusFilter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _statusFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? activeColor : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? activeColor.withValues(alpha: 0.12)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: selected ? activeColor : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg ?? const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: fg ?? const Color(0xFF475569),
        ),
      ),
    );
  }
}
