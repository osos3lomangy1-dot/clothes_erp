import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../products/presentation/screens/product_form_screen.dart';
import '../../data/datasources/inventory_local_data_source.dart';
import '../cubits/goods_receipt_cubit.dart';

class _ReceiptLineItem {
  final String variantId;
  final String productName;
  final String sku;
  final String color;
  final String size;
  int quantity;

  _ReceiptLineItem({
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.color,
    required this.size,
    required this.quantity,
  });
}

class BlindReceiveScreen extends StatelessWidget {
  final VoidCallback? onBack;

  const BlindReceiveScreen({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<GoodsReceiptCubit>(),
      child: _BlindReceiveView(onBack: onBack),
    );
  }
}

class _BlindReceiveView extends StatefulWidget {
  final VoidCallback? onBack;

  const _BlindReceiveView({this.onBack});

  @override
  State<_BlindReceiveView> createState() => _BlindReceiveViewState();
}

class _BlindReceiveViewState extends State<_BlindReceiveView> {
  final _searchController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  final _notesController = TextEditingController();

  final List<_ReceiptLineItem> _lines = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _barcodeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleBarcodeSubmitted(String code) async {
    final query = code.trim();
    if (query.isEmpty) return;
    _barcodeController.clear();

    final db = getIt<AppDatabase>();
    final row = await (db.select(db.productVariants).join([
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productVariants.productId),
      ),
    ])..where(
      db.productVariants.sku.equals(query) &
          db.productVariants.deletedAt.isNull() &
          db.products.deletedAt.isNull(),
    )).getSingleOrNull();

    if (row != null) {
      final v = row.readTable(db.productVariants);
      final p = row.readTable(db.products);
      _addOrIncrementVariant(
        variantId: v.id,
        productName: p.name,
        sku: v.sku,
        color: v.color,
        size: v.size,
      );
    } else {
      _showToast('لم يتم العثور على صنف بالباركود: $query', isError: true);
    }
    _barcodeFocusNode.requestFocus();
  }

  void _addOrIncrementVariant({
    required String variantId,
    required String productName,
    required String sku,
    required String color,
    required String size,
    int addQty = 1,
  }) {
    setState(() {
      final existingIndex = _lines.indexWhere((l) => l.variantId == variantId);
      if (existingIndex >= 0) {
        _lines[existingIndex].quantity += addQty;
      } else {
        _lines.add(_ReceiptLineItem(
          variantId: variantId,
          productName: productName,
          sku: sku,
          color: color,
          size: size,
          quantity: addQty,
        ));
      }
    });
    _showToast('تمت إضافة: $productName ($size - $color)');
  }

  Future<void> _openSearchVariantDialog() async {
    final db = getIt<AppDatabase>();
    final rows = await (db.select(db.productVariants).join([
      innerJoin(
        db.products,
        db.products.id.equalsExp(db.productVariants.productId),
      ),
    ])..where(
      db.productVariants.deletedAt.isNull() &
          db.products.deletedAt.isNull(),
    )).get();

    if (!mounted) return;
    if (rows.isEmpty) {
      _showToast('لا توجد أصناف مسجلة بالمحل حالياً', isError: true);
      return;
    }

    String searchFilter = '';
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = rows.where((r) {
            final v = r.readTable(db.productVariants);
            final p = r.readTable(db.products);
            final q = searchFilter.toLowerCase().trim();
            if (q.isEmpty) return true;
            return p.name.toLowerCase().contains(q) ||
                v.sku.toLowerCase().contains(q) ||
                v.color.toLowerCase().contains(q) ||
                v.size.toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: AppColors.primary),
                SizedBox(width: 8),
                Text('اختيار صنف للاستلام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 520,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'ابحث باسم المنتج، كود SKU، المقاس، أو اللون...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (val) => setDialogState(() => searchFilter = val),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('لا توجد نتائج مطابقة للبحث'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (c, i) => const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final r = filtered[idx];
                              final v = r.readTable(db.productVariants);
                              final p = r.readTable(db.products);

                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                  child: const Icon(Icons.checkroom_rounded, color: AppColors.primary),
                                ),
                                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('المقاس: ${v.size} | اللون: ${v.color} | SKU: ${v.sku}'),
                                trailing: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.add, size: 16, color: Colors.white),
                                  label: const Text('إضافة', style: TextStyle(color: Colors.white)),
                                  onPressed: () {
                                    Navigator.pop(dialogCtx);
                                    _addOrIncrementVariant(
                                      variantId: v.id,
                                      productName: p.name,
                                      sku: v.sku,
                                      color: v.color,
                                      size: v.size,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openQuickAddVariantDialog() async {
    // Open product/variant creation dialog
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ProductFormDialog(),
    );
    if (mounted) {
      _showToast('إذا تم حفظ الصنف الجديد، يمكنك اختياره الآن من البحث أو الباركود');
    }
  }

  Future<void> _saveReceipt() async {
    if (_lines.isEmpty) {
      _showToast('يرجى إضافة صنف واحد على الأقل للشحنة', isError: true);
      return;
    }

    final authState = context.read<AuthCubit>().state;
    String cashierId = 'cashier';
    if (authState is AuthAuthenticated) {
      cashierId = authState.user.name.isNotEmpty ? authState.user.name : authState.user.id;
    }

    setState(() => _isSaving = true);

    try {
      final items = _lines.map((l) => GoodsReceiptDraftItem(
        variantId: l.variantId,
        quantity: l.quantity,
      )).toList();

      final cubit = context.read<GoodsReceiptCubit>();
      final receipt = await cubit.createGoodsReceipt(
        items: items,
        cashierId: cashierId,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (!mounted) return;

      if (receipt != null) {
        _showToast('تم حفظ استلام الشحنة بنجاح وزيادة المخزون مباشرة!');
        setState(() {
          _lines.clear();
          _notesController.clear();
        });
        if (widget.onBack != null) {
          widget.onBack!();
        } else if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      } else {
        _showToast(cubit.state.errorMessage ?? 'فشل حفظ الشحنة', isError: true);
      }
    } catch (e) {
      _showToast('فشل حفظ الشحنة: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  int get _totalItemsCount => _lines.fold(0, (sum, l) => sum + l.quantity);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          tooltip: 'رجوع',
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'استلام بضاعة جديدة (Goods Receipt)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
            ),
            Text(
              'تسجيل الكميات المستلمة للمخزن بدون مورد أو أسعار تكلفة',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.add_box_rounded, color: AppColors.primary, size: 18),
            label: const Text('إضافة صنف جديد كلياً', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _openQuickAddVariantDialog,
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            label: Text(
              _isSaving ? 'جاري الحفظ...' : 'حفظ الشحنة المستلمة ($_totalItemsCount قطعة)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            onPressed: _isSaving ? null : _saveReceipt,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Top Controls Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _barcodeController,
                      focusNode: _barcodeFocusNode,
                      decoration: InputDecoration(
                        labelText: 'مسح بالباركود (Scanner)',
                        hintText: 'امسح باركود القطعة واضغط Enter...',
                        prefixIcon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onSubmitted: _handleBarcodeSubmitted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                    label: const Text('بحث واختيار من القائمة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: _openSearchVariantDialog,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        labelText: 'ملاحظات الشحنة (اختياري)',
                        hintText: 'مثال: كرتونة قادمة مع المندوب أحمد...',
                        prefixIcon: const Icon(Icons.note_alt_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Items Table
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _lines.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'لم يتم إدراج أي أصناف في شحنة الاستلام بعد',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'استخدم قارئ الباركود أو زر البحث لإضافة الأصناف والكميات المستلمة.',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(width: 40, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(flex: 3, child: Text('اسم المنتج / الموديل', style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('كود الصنف / SKU', style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(flex: 1, child: Text('المقاس', style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(flex: 1, child: Text('اللون', style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Center(child: Text('الكمية المستلمة', style: TextStyle(fontWeight: FontWeight.bold)))),
                                SizedBox(width: 50, child: Center(child: Text('حذف', style: TextStyle(fontWeight: FontWeight.bold)))),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              itemCount: _lines.length,
                              separatorBuilder: (c, i) => const Divider(height: 1),
                              itemBuilder: (ctx, idx) {
                                final line = _lines[idx];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 40,
                                        child: Text('${idx + 1}', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(line.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(line.sku, style: TextStyle(color: Colors.grey.shade700)),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Text(line.size, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Text(line.color),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, color: AppColors.primary, size: 22),
                                              onPressed: () {
                                                setState(() {
                                                  if (line.quantity > 1) {
                                                    line.quantity--;
                                                  } else {
                                                    _lines.removeAt(idx);
                                                  }
                                                });
                                              },
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.grey.shade300),
                                              ),
                                              child: Text(
                                                '${line.quantity}',
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 22),
                                              onPressed: () {
                                                setState(() {
                                                  line.quantity++;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: 50,
                                        child: IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                                          tooltip: 'حذف من الشحنة',
                                          onPressed: () {
                                            setState(() => _lines.removeAt(idx));
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
