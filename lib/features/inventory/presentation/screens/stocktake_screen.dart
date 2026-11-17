import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../data/datasources/inventory_local_data_source.dart';

class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key});

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends State<StocktakeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, int> _countedQty = {};

  List<InventoryItemDetail> _allItems = [];
  bool _isLoading = true;
  bool _isCommitting = false;
  bool _barcodeIncrementMode = true;
  String _filter = 'all'; // 'all', 'diff', 'shortage', 'surplus', 'counted', 'uncounted'
  String _searchQuery = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInventory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final ds = getIt<InventoryLocalDataSource>();
      final items = await ds.getInventoryDetails();
      if (!mounted) return;

      for (final c in _qtyControllers.values) {
        c.dispose();
      }
      _qtyControllers.clear();
      _countedQty.clear();

      for (final item in items) {
        _qtyControllers[item.variantId] = TextEditingController();
      }

      setState(() {
        _allItems = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _setCounted(String variantId, int? qty) {
    setState(() {
      if (qty == null || qty < 0) {
        _countedQty.remove(variantId);
        _qtyControllers[variantId]?.text = '';
      } else {
        _countedQty[variantId] = qty;
        final ctrl = _qtyControllers[variantId];
        if (ctrl != null && ctrl.text != '$qty') {
          ctrl.text = '$qty';
        }
      }
    });
  }

  void _handleSearchSubmit(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return;

    if (_barcodeIncrementMode) {
      final lower = code.toLowerCase();
      final match = _allItems.cast<InventoryItemDetail?>().firstWhere(
            (i) => i != null && i.sku.trim().toLowerCase() == lower,
            orElse: () => null,
          );
      if (match != null) {
        final nextQty = (_countedQty[match.variantId] ?? 0) + 1;
        _setCounted(match.variantId, nextQty);
        _searchCtrl.clear();
        setState(() => _searchQuery = '');
        _searchFocus.requestFocus();
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1200),
            backgroundColor: Colors.green.shade800,
            content: Text(
              'تم جرد: ${match.productName} (${match.color} - ${match.size}) ← الفعلي: $nextQty',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1500),
            backgroundColor: AppColors.error,
            content: Text('لم يتم العثور على صنف بالكود: $code'),
          ),
        );
      }
    }
  }

  void _matchAllWithSystem() {
    setState(() {
      for (final item in _allItems) {
        _countedQty[item.variantId] = item.quantity;
        _qtyControllers[item.variantId]?.text = '${item.quantity}';
      }
    });
  }

  void _clearAllCounts() {
    setState(() {
      _countedQty.clear();
      for (final ctrl in _qtyControllers.values) {
        ctrl.clear();
      }
    });
  }

  List<InventoryItemDetail> get _filteredItems {
    final q = _searchQuery.trim().toLowerCase();
    return _allItems.where((item) {
      if (q.isNotEmpty) {
        final matchesSearch = item.productName.toLowerCase().contains(q) ||
            item.sku.toLowerCase().contains(q) ||
            item.color.toLowerCase().contains(q) ||
            item.size.toLowerCase().contains(q);
        if (!matchesSearch) return false;
      }

      final counted = _countedQty[item.variantId];
      switch (_filter) {
        case 'diff':
          return counted != null && counted != item.quantity;
        case 'shortage':
          return counted != null && counted < item.quantity;
        case 'surplus':
          return counted != null && counted > item.quantity;
        case 'counted':
          return counted != null;
        case 'uncounted':
          return counted == null;
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _commitStocktake() async {
    final diffs = <MapEntry<InventoryItemDetail, int>>[];
    int shortageUnits = 0;
    int surplusUnits = 0;
    int netCostVariance = 0;

    for (final item in _allItems) {
      final actual = _countedQty[item.variantId];
      if (actual != null && actual != item.quantity) {
        final delta = actual - item.quantity;
        diffs.add(MapEntry(item, actual));
        if (delta < 0) {
          shortageUnits += delta.abs();
        } else {
          surplusUnits += delta;
        }
        netCostVariance += delta * item.costPrice;
      }
    }

    if (diffs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد أي فروقات بين الرصيد الفعلي ورصيد النظام لاعتمادها'),
        ),
      );
      return;
    }

    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fact_check_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('تأكيد اعتماد الجرد المخزني'),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'سيتم تعديل أرصدة ${diffs.length} صنف وتسجيلها في سجل حركات المخزن:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _summaryRow('أصناف بها فروقات', '${diffs.length} صنف'),
                    const Divider(height: 12),
                    _summaryRow(
                      'إجمالي العجز (-)',
                      '$shortageUnits قطعة',
                      valueColor: Colors.red.shade700,
                    ),
                    const Divider(height: 12),
                    _summaryRow(
                      'إجمالي الزيادة (+)',
                      '$surplusUnits قطعة',
                      valueColor: Colors.green.shade700,
                    ),
                    const Divider(height: 12),
                    _summaryRow(
                      'صافي فرق التكلفة',
                      '${netCostVariance >= 0 ? '+' : '-'}${Money(netCostVariance.abs()).toDisplay()} ج.م',
                      valueColor: netCostVariance < 0
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: 'ملاحظات الجرد (اختياري)',
                  hintText: 'مثال: جرد نهاية الشهر',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('اعتماد وتسوية الأرصدة'),
          ),
        ],
      ),
    );

    final notes = notesCtrl.text.trim();
    notesCtrl.dispose();

    if (confirmed != true || !mounted) return;

    setState(() => _isCommitting = true);
    try {
      final authState = context.read<AuthCubit>().state;
      final userId = authState is AuthAuthenticated ? authState.user.id : 'admin';

      final result = await getIt<InventoryLocalDataSource>().commitStocktake(
        items: diffs
            .map((e) => StocktakeAdjustmentItem(
                  variantId: e.key.variantId,
                  actualQuantity: e.value,
                ))
            .toList(),
        userId: userId,
        notes: notes.isEmpty ? null : notes,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade800,
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم اعتماد الجرد وتسوية ${result.adjustedCount} صنف بنجاح (عجز: ${result.totalShortageUnits} • زيادة: ${result.totalSurplusUnits})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
      await _loadInventory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text('فشل اعتماد الجرد: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCommitting = false);
    }
  }

  Widget _summaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.onSurface,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    int countedItems = 0;
    int diffItems = 0;
    int shortageUnits = 0;
    int surplusUnits = 0;
    int netCostVariance = 0;

    for (final item in _allItems) {
      final actual = _countedQty[item.variantId];
      if (actual != null) {
        countedItems++;
        final delta = actual - item.quantity;
        if (delta != 0) {
          diffItems++;
          if (delta < 0) {
            shortageUnits += delta.abs();
          } else {
            surplusUnits += delta;
          }
          netCostVariance += delta * item.costPrice;
        }
      }
    }

    final filtered = _filteredItems;

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
              'الجرد المخزني',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'مطابقة الرصيد الفعلي مع النظام ورصد العجز والزيادة',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _allItems.isEmpty ? null : _matchAllWithSystem,
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: const Text('مطابقة الكل بالنظام'),
          ),
          TextButton.icon(
            onPressed: _countedQty.isEmpty ? null : _clearAllCounts,
            icon: const Icon(Icons.clear_all_rounded, size: 18, color: Colors.red),
            label: const Text('تصفير الجرد', style: TextStyle(color: Colors.red)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            tooltip: 'تحديث',
            onPressed: _loadInventory,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // KPI Summary Strip
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _kpiBox(
                        'إجمالي الأصناف',
                        '${_allItems.length}',
                        AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _kpiBox(
                        'تم جردها',
                        '$countedItems / ${_allItems.length}',
                        Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _kpiBox(
                        'فروقات (عجز / زيادة)',
                        '$diffItems صنف (-$shortageUnits / +$surplusUnits)',
                        diffItems > 0
                            ? Colors.orange.shade800
                            : Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _kpiBox(
                        'صافي فرق التكلفة',
                        '${netCostVariance >= 0 ? '+' : '-'}${Money(netCostVariance.abs()).toDisplay()} ج.م',
                        netCostVariance < 0
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Search + Barcode Mode Row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        onSubmitted: _handleSearchSubmit,
                        decoration: InputDecoration(
                          hintText: _barcodeIncrementMode
                              ? 'امسح الباركود لإضافة +1 للكمية الفعلية أو ابحث بالاسم...'
                              : 'ابحث باسم المنتج أو الكود أو اللون أو المقاس...',
                          prefixIcon: Icon(
                            _barcodeIncrementMode
                                ? Icons.qr_code_scanner_rounded
                                : Icons.search_rounded,
                            color: AppColors.primary,
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
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
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _barcodeIncrementMode
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _barcodeIncrementMode
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'مسح باركود (+1 تلقائي)',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Switch(
                            value: _barcodeIncrementMode,
                            activeTrackColor:
                                AppColors.primary.withValues(alpha: 0.5),
                            activeThumbColor: AppColors.primary,
                            onChanged: (v) =>
                                setState(() => _barcodeIncrementMode = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('الكل', 'all'),
                      _filterChip('بها فروقات ($diffItems)', 'diff'),
                      _filterChip('عجز (-)', 'shortage'),
                      _filterChip('زيادة (+)', 'surplus'),
                      _filterChip('تم جردها ($countedItems)', 'counted'),
                      _filterChip(
                          'لم تُجرد (${_allItems.length - countedItems})',
                          'uncounted'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Items List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('خطأ: $_error'))
                    : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.fact_check_outlined,
                                    size: 56, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                const Text(
                                  'لا توجد أصناف مطابقة للفلتر الحالي',
                                  style: TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(14),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _buildStocktakeRow(filtered[index]),
                          ),
          ),

          // Bottom Commit Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  diffItems == 0
                      ? 'أدخل الكميات الفعلية للأصناف لرصد الفروقات'
                      : 'جاهز لتسوية $diffItems صنف (عجز: $shortageUnits • زيادة: $surplusUnits)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: diffItems > 0
                        ? AppColors.onSurface
                        : Colors.grey.shade600,
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed:
                      (_isCommitting || diffItems == 0) ? null : _commitStocktake,
                  icon: _isCommitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.fact_check_rounded, size: 20),
                  label: Text(
                    _isCommitting
                        ? 'جارِ الاعتماد...'
                        : 'اعتماد الجرد وتسوية الفروقات ($diffItems)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiBox(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String key) {
    final selected = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        selectedColor: AppColors.primary.withValues(alpha: 0.15),
        checkmarkColor: AppColors.primary,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? AppColors.primary : Colors.grey.shade700,
        ),
        onSelected: (_) => setState(() => _filter = key),
      ),
    );
  }

  Widget _buildStocktakeRow(InventoryItemDetail item) {
    final actual = _countedQty[item.variantId];
    final diff = actual == null ? null : actual - item.quantity;

    Color statusBg = Colors.grey.shade100;
    Color statusFg = Colors.grey.shade600;
    String statusText = 'لم يُجرد';

    if (diff != null) {
      if (diff == 0) {
        statusBg = Colors.green.shade50;
        statusFg = Colors.green.shade800;
        statusText = 'مطابق ✓';
      } else if (diff < 0) {
        statusBg = Colors.red.shade50;
        statusFg = Colors.red.shade800;
        statusText = 'عجز ($diff)';
      } else {
        statusBg = Colors.blue.shade50;
        statusFg = Colors.blue.shade800;
        statusText = 'زيادة (+$diff)';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: diff != null && diff != 0
              ? (diff < 0 ? Colors.red.shade300 : Colors.blue.shade300)
              : Colors.grey.shade200,
          width: diff != null && diff != 0 ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Product info
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.color} • مقاس ${item.size}  |  كود: ${item.sku}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          // System Qty
          SizedBox(
            width: 100,
            child: Column(
              children: [
                Text('بالنظام',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Text(
                  '${item.quantity}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Actual Count Input + Stepper
          SizedBox(
            width: 170,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
                  color: Colors.red.shade600,
                  onPressed: () {
                    final cur = actual ?? item.quantity;
                    if (cur > 0) _setCounted(item.variantId, cur - 1);
                  },
                ),
                SizedBox(
                  width: 66,
                  height: 36,
                  child: TextField(
                    controller: _qtyControllers[item.variantId],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '${item.quantity}',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 6),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (val) {
                      final trimmed = val.trim();
                      if (trimmed.isEmpty) {
                        setState(() => _countedQty.remove(item.variantId));
                      } else {
                        final parsed = int.tryParse(trimmed);
                        if (parsed != null && parsed >= 0) {
                          setState(() => _countedQty[item.variantId] = parsed);
                        }
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
                  color: Colors.green.shade700,
                  onPressed: () {
                    final cur = actual ?? item.quantity;
                    _setCounted(item.variantId, cur + 1);
                  },
                ),
              ],
            ),
          ),

          // Variance Badge
          SizedBox(
            width: 110,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: statusFg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

