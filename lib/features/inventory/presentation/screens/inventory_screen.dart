import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../../products/presentation/screens/product_form_screen.dart';
import '../../data/datasources/inventory_local_data_source.dart';
import '../cubits/inventory_cubit.dart';
import '../cubits/inventory_state.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openReceiveStockDialog(BuildContext context, {VariantEntity? preselectedVariant}) {
    final cubit = context.read<InventoryCubit>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: _ReceiveStockDialog(preselectedVariant: preselectedVariant),
      ),
    );
  }

  void _openAddProductDialog(BuildContext context) async {
    final cubit = context.read<InventoryCubit>();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ProductFormDialog(),
    );
    if (context.mounted) {
      cubit.loadInventory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<InventoryCubit>()..loadInventory(),
      child: Builder(
        builder: (context) {
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
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إدارة المخزون',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.onSurface),
                  ),
                  Text(
                    'متابعة كميات الأصناف وتوريد شحنات البضاعة',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              actions: [
                BlocBuilder<InventoryCubit, InventoryState>(
                  builder: (context, state) {
                    bool isLowStock = false;
                    if (state is InventoryLoaded) {
                      isLowStock = state.showLowStockOnly;
                    }
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isLowStock ? AppColors.error.withValues(alpha: 0.1) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isLowStock ? AppColors.error : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: isLowStock ? AppColors.error : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'الكميات المنخفضة',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isLowStock ? FontWeight.bold : FontWeight.normal,
                              color: isLowStock ? AppColors.error : Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Switch(
                            value: isLowStock,
                            activeThumbColor: AppColors.error,
                            onChanged: (value) => context.read<InventoryCubit>().toggleLowStockFilter(value),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    icon: const Icon(Icons.add_box_outlined, size: 18),
                    label: const Text('إضافة منتج جديد', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _openAddProductDialog(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    icon: const Icon(Icons.add_shopping_cart, size: 20),
                    label: const Text('استلام بضاعة', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () => _openReceiveStockDialog(context),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                // Top Search Bar
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن صنف بالاسم أو الكود (SKU)...',
                      prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.surfaceContainer,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  ),
                ),
                const Divider(height: 1, thickness: 1),

                // Main Inventory List
                Expanded(
                  child: BlocBuilder<InventoryCubit, InventoryState>(
                    builder: (context, state) {
                      if (state is InventoryLoading) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (state is InventoryLoaded) {
                        var filteredItems = state.items;
                        if (_searchQuery.isNotEmpty) {
                          filteredItems = filteredItems.where((i) {
                            final name = i.productName.toLowerCase();
                            final code = i.productCode.toLowerCase();
                            final color = i.color.toLowerCase();
                            final size = i.size.toLowerCase();
                            return name.contains(_searchQuery) ||
                                code.contains(_searchQuery) ||
                                color.contains(_searchQuery) ||
                                size.contains(_searchQuery);
                          }).toList();
                        }

                        if (filteredItems.isEmpty) {
                          return RefreshIndicator(
                            onRefresh: () => context.read<InventoryCubit>().loadInventory(),
                            child: ListView(
                              children: [
                                const SizedBox(height: 80),
                                Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.inventory_2_outlined, size: 72, color: Colors.grey.shade400),
                                      const SizedBox(height: 16),
                                      Text(
                                        _searchQuery.isNotEmpty
                                            ? 'لا توجد أصناف مطابقة لبحثك'
                                            : (state.showLowStockOnly
                                                ? 'رائع! لا توجد منتجات منخفضة المخزون حالياً'
                                                : 'لا توجد أصناف مسجلة في المخزون بعد'),
                                        style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: () => _openAddProductDialog(context),
                                            icon: const Icon(Icons.add_box_outlined),
                                            label: const Text('إضافة منتج جديد'),
                                          ),
                                          const SizedBox(width: 12),
                                          ElevatedButton.icon(
                                            onPressed: () => _openReceiveStockDialog(context),
                                            icon: const Icon(Icons.add_shopping_cart),
                                            label: const Text('استلام وتوريد بضاعة'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Summary Statistics Header
                        final totalQty = filteredItems.fold<int>(0, (sum, i) => sum + i.quantity);
                        final lowCount = filteredItems.where((i) => i.quantity > 0 && i.quantity <= i.minStock).length;
                        final outCount = filteredItems.where((i) => i.quantity == 0).length;

                        return RefreshIndicator(
                          onRefresh: () => context.read<InventoryCubit>().loadInventory(),
                          child: Column(
                            children: [
                              // Quick Stats
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Row(
                                  children: [
                                    _statChip('الأصناف المعروضة: ${filteredItems.length}', Colors.grey.shade800, Colors.grey.shade100),
                                    const SizedBox(width: 8),
                                    _statChip('إجمالي القطع: $totalQty', AppColors.primary, AppColors.surfaceContainer),
                                    const SizedBox(width: 8),
                                    if (lowCount > 0) ...[
                                      _statChip('منخفض: $lowCount', Colors.orange.shade900, Colors.orange.shade50),
                                      const SizedBox(width: 8),
                                    ],
                                    if (outCount > 0)
                                      _statChip('نفذ: $outCount', AppColors.error, Colors.red.shade50),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  itemCount: filteredItems.length,
                                  itemBuilder: (context, index) {
                                    final item = filteredItems[index];
                                    final bool isOut = item.quantity == 0;
                                    final bool isLow = !isOut && item.quantity <= item.minStock;

                                    return Card(
                                      elevation: 0.5,
                                      margin: const EdgeInsets.only(bottom: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: isOut
                                              ? AppColors.error.withValues(alpha: 0.3)
                                              : (isLow ? Colors.orange.withValues(alpha: 0.4) : Colors.grey.shade200),
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        leading: CircleAvatar(
                                          radius: 24,
                                          backgroundColor: isOut
                                              ? Colors.red.shade50
                                              : (isLow ? Colors.orange.shade50 : AppColors.surfaceContainer),
                                          child: Icon(
                                            isOut
                                                ? Icons.error_outline
                                                : (isLow ? Icons.warning_amber_rounded : Icons.check_circle_outline),
                                            color: isOut
                                                ? AppColors.error
                                                : (isLow ? Colors.orange.shade800 : AppColors.primary),
                                          ),
                                        ),
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item.productName,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isOut
                                                    ? AppColors.error.withValues(alpha: 0.1)
                                                    : (isLow ? Colors.orange.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1)),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                isOut ? 'نفذ المخزون' : (isLow ? 'منخفض' : 'متوفر'),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: isOut ? AppColors.error : (isLow ? Colors.orange.shade900 : Colors.green.shade800),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Row(
                                            children: [
                                              _badge('كود: ${item.productCode}'),
                                              const SizedBox(width: 6),
                                              _badge('اللون: ${item.color}'),
                                              const SizedBox(width: 6),
                                              _badge('المقاس: ${item.size}'),
                                              const SizedBox(width: 12),
                                              Text(
                                                'السعر: ${Money(item.salePrice).toDisplay()} ج.م',
                                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '${item.quantity} قطعة',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 18,
                                                    color: isOut ? AppColors.error : (isLow ? Colors.orange.shade900 : AppColors.primary),
                                                  ),
                                                ),
                                                Text(
                                                  'حد الطلب: ${item.minStock}',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 12),
                                            IconButton.filledTonal(
                                              tooltip: 'توريد كمية إضافية لهذا الصنف',
                                              style: IconButton.styleFrom(
                                                backgroundColor: AppColors.surfaceContainer,
                                                foregroundColor: AppColors.primary,
                                              ),
                                              icon: const Icon(Icons.add_shopping_cart, size: 20),
                                              onPressed: () => _openReceiveStockDialog(context, preselectedVariant: item),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      } else if (state is InventoryError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 54, color: AppColors.error),
                              const SizedBox(height: 16),
                              Text(state.message, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => context.read<InventoryCubit>().loadInventory(),
                                child: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statChip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)),
      child: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
    );
  }
}

/// Dialog for receiving incoming shipments and orders (استلام طلبية بضاعة)
class _ReceiveStockDialog extends StatefulWidget {
  final VariantEntity? preselectedVariant;

  const _ReceiveStockDialog({this.preselectedVariant});

  @override
  State<_ReceiveStockDialog> createState() => _ReceiveStockDialogState();
}

class _ReceiveStockDialogState extends State<_ReceiveStockDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _reasonCtrl = TextEditingController();

  List<InventoryItemDetail> _searchResults = [];
  InventoryItemDetail? _selectedDetail;
  bool _isSearching = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedVariant != null) {
      final v = widget.preselectedVariant!;
      _selectedDetail = InventoryItemDetail(
        variantId: v.id,
        productId: v.productId,
        sku: v.productCode,
        color: v.color,
        size: v.size,
        quantity: v.quantity,
        costPrice: v.costPrice,
        sellPrice: v.salePrice,
        productName: v.productName,
      );
    } else {
      _loadInitialVariants();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialVariants() async {
    setState(() => _isSearching = true);
    final results = await context.read<InventoryCubit>().searchVariants('');
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<void> _onSearchChanged(String query) async {
    setState(() => _isSearching = true);
    final results = await context.read<InventoryCubit>().searchVariants(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _stepQuantity(int delta) {
    final current = int.tryParse(_qtyCtrl.text) ?? 1;
    final next = current + delta;
    if (next >= 1) {
      _qtyCtrl.text = next.toString();
    }
  }

  Future<void> _openQuickAddProduct() async {
    final cubit = context.read<InventoryCubit>();
    final result = await showDialog<InventoryItemDetail>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: _QuickAddProductDialog(initialName: _searchCtrl.text.trim()),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedDetail = result;
        _errorMessage = null;
      });
    }
  }

  Future<void> _openFullProductTableDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ProductFormDialog(),
    );
    if (mounted) {
      _loadInitialVariants();
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (_selectedDetail == null) {
      setState(() => _errorMessage = 'يرجى اختيار الصنف أو المقاس أولاً');
      return;
    }

    final qty = int.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) {
      setState(() => _errorMessage = 'يرجى إدخال كمية صحيحة أكبر من الصفر');
      return;
    }

    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال اسم المورد أو رقم الفاتورة (مطلوب)');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await context.read<InventoryCubit>().receiveStock(
            variantId: _selectedDetail!.variantId,
            quantity: qty,
            reason: reason,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade800,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'تم استلام وتوريد $qty قطعة بنجاح إلى مخزون (${_selectedDetail!.productName})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_shopping_cart, color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'استلام طلبية / توريد بضاعة',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                        ),
                        Text(
                          'تسجيل الشحنات الواردة وتحديث رصيد المخزون وسجل الحركات',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Variant Selection Section
                      if (_selectedDetail == null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '١. اختر أو ابحث عن الصنف المستلم:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('إضافة منتج غير مسجل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              onPressed: _openQuickAddProduct,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'ابحث باسم المنتج، الكود (SKU)، اللون أو المقاس...',
                            prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                            filled: true,
                            fillColor: AppColors.surfaceContainer,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          onChanged: _onSearchChanged,
                        ),
                        const SizedBox(height: 8),
                        if (_isSearching)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_searchResults.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 36, color: AppColors.primary),
                                const SizedBox(height: 8),
                                Text(
                                  _searchCtrl.text.isNotEmpty
                                      ? 'المنتج "${_searchCtrl.text}" غير مسجل في السيستم'
                                      : 'لا توجد منتجات مسجلة حتى الآن',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.table_chart_outlined, size: 16),
                                      label: const Text('إضافة بجدول المقاسات'),
                                      onPressed: _openFullProductTableDialog,
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('إضافة سريعة'),
                                      onPressed: _openQuickAddProduct,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            height: 180,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _searchResults.length,
                              separatorBuilder: (_, index) => const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final item = _searchResults[idx];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    item.productName,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text('كود: ${item.sku} | ${item.color} - ${item.size}'),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'الرصيد: ${item.quantity}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      _selectedDetail = item;
                                      _errorMessage = null;
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                      ] else ...[
                        // Selected Variant Card
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                child: Icon(Icons.check),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedDetail!.productName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'كود: ${_selectedDetail!.sku} | اللون: ${_selectedDetail!.color} | المقاس: ${_selectedDetail!.size}',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'الرصيد الحالي بالمحل: ${_selectedDetail!.quantity} قطعة',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                                    ),
                                  ],
                                ),
                              ),
                              if (widget.preselectedVariant == null)
                                TextButton.icon(
                                  icon: const Icon(Icons.swap_horiz, size: 18),
                                  label: const Text('تغيير الصنف'),
                                  onPressed: () => setState(() => _selectedDetail = null),
                                ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // 2. Incoming Quantity Field
                      const Text(
                        '٢. الكمية الواردة (عدد القطع المستلمة):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            style: IconButton.styleFrom(backgroundColor: AppColors.surfaceContainer),
                            icon: const Icon(Icons.remove),
                            onPressed: () => _stepQuantity(-1),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _qtyCtrl,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary),
                              decoration: InputDecoration(
                                hintText: 'الكمية',
                                prefixIcon: const Icon(Icons.add_box_outlined, color: AppColors.primary),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            style: IconButton.styleFrom(backgroundColor: AppColors.surfaceContainer),
                            icon: const Icon(Icons.add),
                            onPressed: () => _stepQuantity(1),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // 3. Reason / Supplier Field
                      const Text(
                        '٣. اسم المورد / رقم الفاتورة (سبب التوريد):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _reasonCtrl,
                        decoration: InputDecoration(
                          hintText: 'مثال: شركة النصر للملابس - فاتورة توريد #4512',
                          prefixIcon: const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Quick reason suggestions
                      Wrap(
                        spacing: 8,
                        children: [
                          _suggestionChip('فاتورة توريد بضاعة'),
                          _suggestionChip('شحنة مورد جديدة'),
                          _suggestionChip('تسوية مخزون دورية'),
                        ],
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.done_all, size: 20),
                    label: Text(
                      _isSubmitting ? 'جاري التوريد...' : 'تأكيد استلام وتوريد البضاعة',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _suggestionChip(String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: () {
        setState(() {
          _reasonCtrl.text = label;
        });
      },
    );
  }
}

/// Dialog to quickly register a new product and variant and receive it into stock
class _QuickAddProductDialog extends StatefulWidget {
  final String initialName;

  const _QuickAddProductDialog({required this.initialName});

  @override
  State<_QuickAddProductDialog> createState() => _QuickAddProductDialogState();
}

class _QuickAddProductDialogState extends State<_QuickAddProductDialog> {
  late final TextEditingController _nameCtrl;
  final TextEditingController _skuCtrl = TextEditingController();
  final TextEditingController _colorCtrl = TextEditingController(text: 'افتراضي');
  final TextEditingController _sizeCtrl = TextEditingController(text: 'افتراضي');
  final TextEditingController _costCtrl = TextEditingController(text: '100');
  final TextEditingController _sellCtrl = TextEditingController(text: '150');
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _reasonCtrl = TextEditingController(text: 'فاتورة توريد بضاعة جديدة');

  List<dynamic> _categories = [];
  String? _selectedCategoryId;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _generateSku();
    _loadCategories();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _colorCtrl.dispose();
    _sizeCtrl.dispose();
    _costCtrl.dispose();
    _sellCtrl.dispose();
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  void _generateSku() {
    final prefix = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim().substring(0, 1).toUpperCase()
        : 'P';
    final millis = DateTime.now().millisecondsSinceEpoch.toString();
    final suffix = millis.substring(millis.length - 4);
    _skuCtrl.text = '$prefix$suffix';
  }

  Future<void> _loadCategories() async {
    final cats = await context.read<InventoryCubit>().getCategories();
    if (mounted) {
      setState(() {
        _categories = cats;
        if (cats.isNotEmpty) {
          _selectedCategoryId = cats.first.id as String;
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _submitQuickAdd() async {
    setState(() => _errorMsg = null);

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMsg = 'يرجى إدخال اسم المنتج');
      return;
    }

    final sku = _skuCtrl.text.trim();
    if (sku.isEmpty) {
      setState(() => _errorMsg = 'يرجى إدخال كود الصنف (SKU)');
      return;
    }

    final cost = (double.tryParse(_costCtrl.text.trim()) ?? 0.0) * 100;
    final sell = (double.tryParse(_sellCtrl.text.trim()) ?? 0.0) * 100;
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) {
      setState(() => _errorMsg = 'الكمية المستلمة يجب أن تكون أكبر من صفر');
      return;
    }

    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorMsg = 'اسم المورد أو رقم الفاتورة مطلوب');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final detail = await context.read<InventoryCubit>().quickCreateProductAndReceive(
            productName: name,
            categoryId: _selectedCategoryId ?? 'default_cat',
            sku: sku,
            color: _colorCtrl.text.trim(),
            size: _sizeCtrl.text.trim(),
            costPrice: cost.toInt(),
            sellPrice: sell.toInt(),
            quantity: qty,
            reason: reason,
          );
      if (mounted) {
        Navigator.pop(context, detail);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = e.toString().replaceAll('Exception: ', '');
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_box, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'إضافة واستلام منتج جديد فوراً',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              if (_isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Product Name
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم المنتج *',
                            hintText: 'مثال: قميص كتان تركي',
                            prefixIcon: Icon(Icons.checkroom),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _generateSku(),
                        ),
                        const SizedBox(height: 12),

                        // Category Dropdown
                        if (_categories.isNotEmpty)
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCategoryId,
                            decoration: const InputDecoration(
                              labelText: 'التصنيف *',
                              prefixIcon: Icon(Icons.category),
                              border: OutlineInputBorder(),
                            ),
                            items: _categories.map((c) {
                              return DropdownMenuItem<String>(
                                value: c.id as String,
                                child: Text(c.name as String),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedCategoryId = val);
                            },
                          ),
                        const SizedBox(height: 12),

                        // SKU & Color
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _skuCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'كود الصنف / الباركود (SKU) *',
                                  prefixIcon: Icon(Icons.qr_code),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _colorCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'اللون',
                                  prefixIcon: Icon(Icons.palette_outlined),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Size & Quantity
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _sizeCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'المقاس',
                                  prefixIcon: Icon(Icons.straighten),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _qtyCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'الكمية المستلمة *',
                                  prefixIcon: Icon(Icons.numbers),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Cost & Sell Prices
                        Builder(
                          builder: (context) {
                            final authState = context.watch<AuthCubit>().state;
                            final isCashier = authState is AuthAuthenticated && authState.user.role.toLowerCase() == 'cashier';

                            return Row(
                              children: [
                                if (!isCashier) ...[
                                  Expanded(
                                    child: TextFormField(
                                      controller: _costCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'سعر التكلفة (ج.م) *',
                                        prefixIcon: Icon(Icons.attach_money),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: TextFormField(
                                    controller: _sellCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'سعر البيع (ج.م) *',
                                      prefixIcon: Icon(Icons.sell_outlined),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),

                        // Reason / Supplier
                        TextFormField(
                          controller: _reasonCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم المورد / رقم الفاتورة *',
                            hintText: 'مثال: شركة النور - فاتورة #105',
                            prefixIcon: Icon(Icons.receipt_long),
                            border: OutlineInputBorder(),
                          ),
                        ),

                        if (_errorMsg != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              _errorMsg!,
                              style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ واستلام البضاعة فوراً'),
                    onPressed: _isSaving ? null : _submitQuickAdd,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
