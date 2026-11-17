import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../data/datasources/purchases_local_data_source.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/entities/purchase_item_entity.dart';

class CreatePurchaseReturnDialog extends StatefulWidget {
  final PurchaseEntity purchase;
  final Future<void> Function({
    required List<PurchaseReturnItemDraft> items,
    required String refundType,
    String? reason,
  }) onConfirm;

  const CreatePurchaseReturnDialog({
    super.key,
    required this.purchase,
    required this.onConfirm,
  });

  @override
  State<CreatePurchaseReturnDialog> createState() => _CreatePurchaseReturnDialogState();
}

class _CreatePurchaseReturnDialogState extends State<CreatePurchaseReturnDialog> {
  final Map<String, int> _returnQuantities = {};
  final Map<String, int> _availableStock = {};
  bool _isLoadingStock = true;
  bool _isSubmitting = false;
  String _refundType = 'credit'; // 'credit' or 'cash'
  final TextEditingController _reasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAvailableStock();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableStock() async {
    final db = getIt<AppDatabase>();
    final variantIds = widget.purchase.items.map((i) => i.variantId).toList();

    final variants = await (db.select(db.productVariants)
          ..where((v) => v.id.isIn(variantIds)))
        .get();

    final stockMap = {for (final v in variants) v.id: v.quantity};

    if (mounted) {
      setState(() {
        for (final item in widget.purchase.items) {
          _availableStock[item.id] = stockMap[item.variantId] ?? 0;
          _returnQuantities[item.id] = 0;
        }
        _isLoadingStock = false;
      });
    }
  }

  int get _totalReturnPieces {
    return _returnQuantities.values.fold(0, (sum, q) => sum + q);
  }

  int get _totalReturnAmountPiasters {
    int sum = 0;
    for (final item in widget.purchase.items) {
      final qty = _returnQuantities[item.id] ?? 0;
      sum += (qty * item.costPrice);
    }
    return sum;
  }

  void _updateItemQty(PurchaseItemEntity item, int newQty) {
    final avail = _availableStock[item.id] ?? 0;
    final maxAllowed = min(item.qty, max(0, avail));
    final clamped = newQty.clamp(0, maxAllowed);
    setState(() {
      _returnQuantities[item.id] = clamped;
    });
  }

  Future<void> _handleSubmit() async {
    if (_totalReturnPieces <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد كمية قطعة واحدة على الأقل لإرجاعها'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final drafts = <PurchaseReturnItemDraft>[];
    for (final it in widget.purchase.items) {
      final qty = _returnQuantities[it.id] ?? 0;
      if (qty > 0) {
        drafts.add(PurchaseReturnItemDraft(
          variantId: it.variantId,
          productName: it.productName ?? 'صنف',
          variantInfo: '${it.color ?? ''} - ${it.size ?? ''}'.trim(),
          sku: it.sku ?? '',
          qty: qty,
          costPrice: it.costPrice,
        ));
      }
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.onConfirm(
        items: drafts,
        refundType: _refundType,
        reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تسجيل المرتجع: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.purchase;
    final formattedTotalRefund = '${Money(_totalReturnAmountPiasters).toDisplay()} ج.م';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Icon(Icons.assignment_return_rounded, color: Colors.orange.shade800, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مرتجع مشتريات: ${p.supplierName ?? 'مورد'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.invoiceNumber != null && p.invoiceNumber!.isNotEmpty
                              ? 'فاتورة #${p.invoiceNumber} | إجمالي الفاتورة: ${p.formattedTotalAmount}'
                              : 'فاتورة #${p.id.substring(0, 8)} | إجمالي الفاتورة: ${p.formattedTotalAmount}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Items List or Loading
              if (_isLoadingStock)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('جاري فحص أرصدة المخزن الحالية...'),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: p.items.length,
                    separatorBuilder: (c, i) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final item = p.items[idx];
                      final currentStock = _availableStock[item.id] ?? 0;
                      final returnQty = _returnQuantities[item.id] ?? 0;
                      final maxReturnable = min(item.qty, max(0, currentStock));
                      final lineTotalReturn = returnQty * item.costPrice;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName ?? 'صنف',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item.color ?? ''} - ${item.size ?? ''} | كود: ${item.sku ?? ''}',
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        'تم شراء: ${item.qty} قطعة | سعر التكلفة: ${item.formattedCostPrice}',
                                        style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: currentStock > 0 ? Colors.green.shade50 : Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'المخزون الحالي: $currentStock',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: currentStock > 0 ? Colors.green.shade800 : Colors.red.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Quantity Controls
                            SizedBox(
                              width: 140,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 22),
                                    color: returnQty > 0 ? Colors.red.shade700 : Colors.grey.shade400,
                                    onPressed: returnQty > 0
                                        ? () => _updateItemQty(item, returnQty - 1)
                                        : null,
                                  ),
                                  Text(
                                    '$returnQty',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 22),
                                    color: returnQty < maxReturnable ? Colors.green.shade700 : Colors.grey.shade400,
                                    onPressed: returnQty < maxReturnable
                                        ? () => _updateItemQty(item, returnQty + 1)
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                            // Line Total
                            SizedBox(
                              width: 110,
                              child: Text(
                                '${Money(lineTotalReturn).toDisplay()} ج.م',
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: lineTotalReturn > 0 ? Colors.orange.shade900 : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 12),
              // Refund Settlement Method
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('طريقة تسوية المرتجع المالي:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _refundType = 'credit'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _refundType == 'credit' ? Colors.blue.shade50 : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _refundType == 'credit' ? AppColors.primary : Colors.grey.shade300,
                                  width: _refundType == 'credit' ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _refundType == 'credit' ? Icons.radio_button_checked : Icons.radio_button_off,
                                    size: 18,
                                    color: _refundType == 'credit' ? AppColors.primary : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('خصم من مديونية المورد', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        Text('يخفض رصيد المورد المستحق لدينا', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _refundType = 'cash'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _refundType == 'cash' ? Colors.green.shade50 : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _refundType == 'cash' ? Colors.green.shade700 : Colors.grey.shade300,
                                  width: _refundType == 'cash' ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _refundType == 'cash' ? Icons.radio_button_checked : Icons.radio_button_off,
                                    size: 18,
                                    color: _refundType == 'cash' ? Colors.green.shade700 : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('استرداد نقدي فوري بالدرج', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        Text('يسجل حركة استرداد بالوردية الحالية', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),
              // Reason Input
              TextField(
                controller: _reasonCtrl,
                decoration: InputDecoration(
                  labelText: 'سبب الإرجاع (اختياري)',
                  hintText: 'مثال: عيوب تصنيع / تلف / مقاسات زائدة عن الحاجة',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),

              const SizedBox(height: 16),
              // Footer
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إجمالي القطع المرتجعة: $_totalReturnPieces قطعة',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                      Text(
                        'إجمالي قيمة المرتجع: $formattedTotalRefund',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange.shade900),
                      ),
                    ],
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 18),
                    label: Text(
                      _isSubmitting ? 'جاري الحفظ...' : 'تأكيد مرتجع المشتريات ($formattedTotalRefund)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isSubmitting ? null : _handleSubmit,
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
