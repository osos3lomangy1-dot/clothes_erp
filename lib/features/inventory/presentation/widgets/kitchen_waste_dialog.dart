import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../data/datasources/inventory_local_data_source.dart';
import 'kitchen_waste_audit_dialog.dart';

class KitchenWasteDialog extends StatefulWidget {
  final String? defaultVariantId;
  final String userId;

  const KitchenWasteDialog({
    super.key,
    this.defaultVariantId,
    this.userId = 'pos_cashier',
  });

  static const List<String> wasteReasons = [
    'تلف وتخزين / انتهاء صلاحية',
    'حرق أو خطأ تشغيل بالطهي',
    'هالك تنظيف وتجهيز إضافي',
    'سكب / كسر أثناء التقديم',
    'تجربة وتذوق الشيف',
  ];

  static Future<bool?> show(
    BuildContext context, {
    String? defaultVariantId,
    String userId = 'pos_cashier',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => KitchenWasteDialog(
        defaultVariantId: defaultVariantId,
        userId: userId,
      ),
    );
  }

  @override
  State<KitchenWasteDialog> createState() => _KitchenWasteDialogState();
}

class _KitchenWasteDialogState extends State<KitchenWasteDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  final _unitCtrl = TextEditingController(text: 'حبة');
  final _notesCtrl = TextEditingController();

  String _selectedReason = KitchenWasteDialog.wasteReasons.first;
  String? _selectedVariantId;
  List<Map<String, dynamic>> _availableItems = [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _unitCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    try {
      final db = getIt<AppDatabase>();
      final query = db.select(db.productVariants).join([
        innerJoin(
          db.products,
          db.products.id.equalsExp(db.productVariants.productId),
        ),
      ])..where(
          db.productVariants.deletedAt.isNull() &
              db.products.deletedAt.isNull(),
        );

      final rows = await query.get();
      final items = rows.map((r) {
        final v = r.readTable(db.productVariants);
        final p = r.readTable(db.products);
        return {
          'variantId': v.id,
          'productId': p.id,
          'productName': p.name,
          'sku': v.sku,
          'size': v.size,
          'color': v.color,
          'stock': v.quantity,
          'unit': v.size,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _availableItems = items;
          if (widget.defaultVariantId != null &&
              items.any((it) => it['variantId'] == widget.defaultVariantId)) {
            _selectedVariantId = widget.defaultVariantId;
          } else if (items.isNotEmpty) {
            _selectedVariantId = items.first['variantId'] as String;
          }

          if (_selectedVariantId != null) {
            final found = items.firstWhere(
              (it) => it['variantId'] == _selectedVariantId,
              orElse: () => items.first,
            );
            _unitCtrl.text = (found['size'] as String? ?? 'حبة');
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitWaste() async {
    if (_selectedVariantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى اختيار الصنف أو الخامة أولاً'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('يرجى إدخال كمية هالك صحيحة أكبر من صفر'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final reasonText = 'هالك مطبخ: $_selectedReason${_notesCtrl.text.trim().isNotEmpty ? " - ${_notesCtrl.text.trim()}" : ""}';
      
      if (getIt.isRegistered<InventoryLocalDataSource>()) {
        try {
          await getIt<InventoryLocalDataSource>().applyStockMovement(
            variantId: _selectedVariantId!,
            qtyDelta: -qty,
            type: StockMovementType.adjustment,
            reason: reasonText,
            userId: widget.userId,
            refType: 'kitchen_waste',
          );
        } catch (_) {
          // Direct fallback if strictly checked
          await _fallbackDirectStockDeduct(qty);
        }
      } else {
        await _fallbackDirectStockDeduct(qty);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم تسجيل إذن هالك المطبخ وتعديل رصيد المخزن بنجاح'),
            backgroundColor: AppColors.primary,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تسجيل الهالك: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _fallbackDirectStockDeduct(int qty) async {
    if (getIt.isRegistered<AppDatabase>()) {
      final db = getIt<AppDatabase>();
      final row = await (db.select(db.productVariants)
            ..where((t) => t.id.equals(_selectedVariantId!)))
          .getSingleOrNull();
      if (row != null) {
        final newQty = (row.quantity - qty).clamp(0, 999999);
        await (db.update(db.productVariants)
              ..where((t) => t.id.equals(_selectedVariantId!)))
            .write(
          ProductVariantsCompanion(
            quantity: Value(newQty),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('kitchen_waste_dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 24),
          const SizedBox(width: 8),
          const Text(
            'إذن هالك وفاقد مطبخ (Kitchen Spoilage)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: _loading
            ? const SizedBox(
                height: 150,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تسجيل الهالك يخصم الكمية فورياً من المخزن الفعلي ويوثق سبب التلف للمراقبة والتكاليف.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),

                    // Variant Dropdown
                    DropdownButtonFormField<String>(
                      key: const Key('waste_item_dropdown'),
                      initialValue: _selectedVariantId,
                      decoration: const InputDecoration(
                        labelText: 'الصنف أو الخامة التالفة *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.restaurant_menu_rounded),
                      ),
                      items: _availableItems.map((it) {
                        return DropdownMenuItem<String>(
                          value: it['variantId'] as String,
                          child: Text(
                            '${it['productName']} (${it['size']}) - رصيد: ${it['stock']}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedVariantId = val;
                            final found = _availableItems.firstWhere(
                              (it) => it['variantId'] == val,
                              orElse: () => _availableItems.first,
                            );
                            _unitCtrl.text = (found['size'] as String? ?? 'حبة');
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Quantity and Unit
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            key: const Key('waste_quantity_field'),
                            controller: _qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'الكمية الهالكة *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.exposure_minus_1_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            key: const Key('waste_unit_field'),
                            controller: _unitCtrl,
                            decoration: const InputDecoration(
                              labelText: 'وحدة القياس',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Reason Dropdown
                    DropdownButtonFormField<String>(
                      key: const Key('waste_reason_dropdown'),
                      initialValue: _selectedReason,
                      decoration: const InputDecoration(
                        labelText: 'سبب الهالك / الفاقد *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.report_problem_outlined),
                      ),
                      items: KitchenWasteDialog.wasteReasons.map((r) {
                        return DropdownMenuItem<String>(
                          value: r,
                          child: Text(r, style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedReason = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Free Notes
                    TextField(
                      key: const Key('waste_notes_field'),
                      controller: _notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'تفاصيل أو ملاحظات إضافية (اختياري)',
                        hintText: 'مثال: سقوط طبق أثناء التقديم للترابيزة 4...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        OutlinedButton.icon(
          key: const Key('open_waste_audit_btn'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
          ),
          onPressed: () => KitchenWasteAuditDialog.show(context),
          icon: const Icon(Icons.analytics_outlined, size: 16),
          label: const Text(
            'تقرير وتكلفة الهالك',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: const Key('cancel_kitchen_waste_btn'),
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton.icon(
          key: const Key('confirm_kitchen_waste_btn'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check, size: 18),
          label: const Text(
            'اعتماد وخصم من المخزن',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: _submitting ? null : _submitWaste,
        ),
      ],
    );
  }
}
