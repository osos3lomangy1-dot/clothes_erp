import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../cubits/inventory_cubit.dart';

/// Opens a clean modal dialog to adjust (increase or decrease/write-off) stock
/// for [item] with a mandatory reason and real logged-in [userId].
Future<bool?> showInventoryAdjustmentDialog(
  BuildContext context, {
  required VariantEntity item,
  required InventoryCubit cubit,
  required String userId,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _InventoryAdjustmentDialog(
      item: item,
      cubit: cubit,
      userId: userId,
    ),
  );
}

class _InventoryAdjustmentDialog extends StatefulWidget {
  final VariantEntity item;
  final InventoryCubit cubit;
  final String userId;

  const _InventoryAdjustmentDialog({
    required this.item,
    required this.cubit,
    required this.userId,
  });

  @override
  State<_InventoryAdjustmentDialog> createState() =>
      _InventoryAdjustmentDialogState();
}

class _InventoryAdjustmentDialogState
    extends State<_InventoryAdjustmentDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  final _reasonCtrl = TextEditingController();
  bool _isDecrease = true;
  bool _submitting = false;
  String? _error;

  static const _quickReasons = [
    'قطعة تالفة / هالك',
    'تصحيح خطأ جرد',
    'فقد / عجز مخزني',
    'فائض جرد',
  ];

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  int get _enteredQty => int.tryParse(_qtyCtrl.text.trim()) ?? 0;

  int get _delta => _isDecrease ? -_enteredQty : _enteredQty;

  int get _newQty => widget.item.quantity + _delta;

  Future<void> _submit() async {
    final qty = _enteredQty;
    final reason = _reasonCtrl.text.trim();
    if (qty <= 0) {
      setState(() => _error = 'يرجى إدخال كمية صحيحة أكبر من صفر');
      return;
    }
    if (_newQty < 0) {
      setState(
        () => _error =
            'لا يمكن خصم كمية أكبر من الرصيد الحالي (${widget.item.quantity})',
      );
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'يرجى إدخال سبب التسوية');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.cubit.adjustStock(
        variantId: widget.item.id,
        qtyDelta: _delta,
        reason: reason,
        userId: widget.userId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppFeedback.showSuccess(
        context,
        'تم تسجيل التسوية بنجاح — الرصيد الجديد: $_newQty قطعة',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final invalidNegative = _newQty < 0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: Colors.teal.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تسوية رصيد المخزون',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16.5,
                          ),
                        ),
                        Text(
                          '${widget.item.productName} (${widget.item.color} / ${widget.item.size})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('خصم / تالف (-)')),
                          selected: _isDecrease,
                          selectedColor: Colors.red.shade50,
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _isDecrease
                                ? AppColors.error
                                : Colors.grey.shade700,
                          ),
                          onSelected: (_) => setState(() => _isDecrease = true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('إضافة / فائض (+)')),
                          selected: !_isDecrease,
                          selectedColor: Colors.green.shade50,
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: !_isDecrease
                                ? Colors.green.shade800
                                : Colors.grey.shade700,
                          ),
                          onSelected: (_) =>
                              setState(() => _isDecrease = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الكمية المراد تعديلها *',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: invalidNegative
                          ? Colors.red.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        Text('الرصيد الحالي: ${widget.item.quantity} قطعة'),
                        Text(
                          'الرصيد الجديد: $_newQty قطعة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: invalidNegative
                                ? AppColors.error
                                : Colors.teal.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'سبب التسوية *',
                      hintText: 'مثال: قطعة تالفة أو تصحيح جرد',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _quickReasons
                        .map(
                          (r) => ActionChip(
                            label: Text(r, style: const TextStyle(fontSize: 11.5)),
                            onPressed: () {
                              _reasonCtrl.text = r;
                              setState(() => _error = null);
                            },
                          ),
                        )
                        .toList(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    key: const Key('confirm_stock_adjust_btn'),
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDecrease
                          ? AppColors.error
                          : Colors.teal.shade700,
                      foregroundColor: Colors.white,
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('تأكيد التسوية'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a modal dialog showing the recent inventory movement history for [item].
Future<void> showVariantMovementHistoryDialog(
  BuildContext context, {
  required VariantEntity item,
  required InventoryCubit cubit,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: AppColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: _VariantHistoryBody(item: item, cubit: cubit),
      ),
    ),
  );
}

class _VariantHistoryBody extends StatefulWidget {
  final VariantEntity item;
  final InventoryCubit cubit;

  const _VariantHistoryBody({required this.item, required this.cubit});

  @override
  State<_VariantHistoryBody> createState() => _VariantHistoryBodyState();
}

class _VariantHistoryBodyState extends State<_VariantHistoryBody> {
  List<InventoryLog>? _logs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.cubit.getVariantLogs(widget.item.id);
      if (mounted) setState(() => _logs = rows);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر تحميل سجل الحركات: $e');
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'sale':
        return 'بيع';
      case 'return_':
      case 'return':
        return 'مرتجع';
      case 'receive':
      case 'in':
        return 'توريد / إضافة';
      case 'adjustment':
        return 'تسوية يدوية';
      case 'stocktake':
        return 'جرد مخزني';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.history_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'سجل حركات الصنف',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16.5,
                      ),
                    ),
                    Text(
                      '${widget.item.productName} • SKU: ${widget.item.productCode} • الرصيد: ${widget.item.quantity}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
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
        ),
        const Divider(height: 1),
        Expanded(
          child: _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                )
              : _logs == null
                  ? const Center(child: CircularProgressIndicator())
                  : _logs!.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد حركات مسجلة لهذا الصنف حتى الآن',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(14),
                          itemCount: _logs!.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final log = _logs![i];
                            final isPositive = log.qtyDelta >= 0;
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isPositive
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,
                                  child: Icon(
                                    isPositive
                                        ? Icons.arrow_downward_rounded
                                        : Icons.arrow_upward_rounded,
                                    size: 18,
                                    color: isPositive
                                        ? Colors.green.shade700
                                        : AppColors.error,
                                  ),
                                ),
                                title: Text(
                                  '${_typeLabel(log.type)}${log.reason != null && log.reason!.trim().isNotEmpty ? ' — ${log.reason}' : ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                                subtitle: Text(
                                  fmt.format(log.createdAt.toLocal()),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: Text(
                                  '${isPositive ? '+' : ''}${log.qtyDelta}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isPositive
                                        ? Colors.green.shade800
                                        : AppColors.error,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

/// Opens a clean modal dialog to edit the reorder limit (minimum stock) for [item].
Future<bool?> showEditMinStockDialog(
  BuildContext context, {
  required VariantEntity item,
  required InventoryCubit cubit,
  String userId = 'admin',
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _EditMinStockDialog(
      item: item,
      cubit: cubit,
      userId: userId,
    ),
  );
}

class _EditMinStockDialog extends StatefulWidget {
  final VariantEntity item;
  final InventoryCubit cubit;
  final String userId;

  const _EditMinStockDialog({
    required this.item,
    required this.cubit,
    required this.userId,
  });

  @override
  State<_EditMinStockDialog> createState() => _EditMinStockDialogState();
}

class _EditMinStockDialogState extends State<_EditMinStockDialog> {
  late final TextEditingController _minStockCtrl;
  bool _submitting = false;
  String? _error;

  static const _quickOptions = [2, 3, 5, 10, 15, 20];

  @override
  void initState() {
    super.initState();
    _minStockCtrl = TextEditingController(text: '${widget.item.minStock}');
    _minStockCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _minStockCtrl.dispose();
    super.dispose();
  }

  int get _parsedMinStock => int.tryParse(_minStockCtrl.text.trim()) ?? widget.item.minStock;

  void _step(int delta) {
    final next = (_parsedMinStock + delta).clamp(0, 99999);
    _minStockCtrl.text = '$next';
  }

  Future<void> _submit() async {
    final val = int.tryParse(_minStockCtrl.text.trim());
    if (val == null || val < 0) {
      setState(() => _error = 'يرجى إدخال رقم صحيح أكبر من أو يساوي صفر');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.cubit.updateMinStock(
        productId: widget.item.productId,
        minStock: val,
        variantId: widget.item.id,
        userId: widget.userId,
      );
      if (mounted) {
        AppFeedback.showSuccess(
          context,
          'تم تحديث حد إعادة الطلب بنجاح إلى ($val قطعة)',
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'فشل تحديث حد الطلب: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final newMin = _parsedMinStock;
    final currentQty = widget.item.quantity;
    final willBeLow = currentQty <= newMin && currentQty > 0;
    final willBeOut = currentQty == 0;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.notifications_active_outlined,
                      color: Colors.amber.shade900,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تعديل حد إعادة الطلب (حد الأمان)',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'تحديد أقل كمية مسموحة قبل إطلاق تنبيه بالنواقص',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Item Info Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.productName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'المقاس: ${widget.item.size} • اللون: ${widget.item.color} • SKU: ${widget.item.productCode}',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'الرصيد: $currentQty قطعة',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Min Stock Input with +/- Stepper
              const Text(
                'الحد الأدنى الجديد للمخزون:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.remove),
                    tooltip: 'تقليل 1',
                    onPressed: _submitting ? null : () => _step(-1),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _minStockCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                      decoration: InputDecoration(
                        hintText: '5',
                        suffixText: 'قطعة',
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add),
                    tooltip: 'زيادة 1',
                    onPressed: _submitting ? null : () => _step(1),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Quick presets
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _quickOptions.map((n) {
                  final isSelected = newMin == n;
                  return ChoiceChip(
                    label: Text('$n قطع'),
                    selected: isSelected,
                    onSelected: _submitting
                        ? null
                        : (selected) {
                            if (selected) {
                              _minStockCtrl.text = '$n';
                            }
                          },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Status Impact Warning / Info Box
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: willBeOut
                      ? Colors.red.shade50
                      : (willBeLow ? Colors.orange.shade50 : Colors.green.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: willBeOut
                        ? Colors.red.shade200
                        : (willBeLow ? Colors.orange.shade200 : Colors.green.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      willBeOut
                          ? Icons.error_outline_rounded
                          : (willBeLow ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded),
                      size: 18,
                      color: willBeOut
                          ? Colors.red.shade800
                          : (willBeLow ? Colors.orange.shade900 : Colors.green.shade800),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        willBeOut
                            ? 'الرصيد الحالي 0، الصنف مسجل كـ "نفذ المخزون".'
                            : (willBeLow
                                ? 'الرصيد الحالي ($currentQty) يصل أو يقل عن حد الطلب ($newMin) — سيظهر في تنبيهات النواقص.'
                                : 'الرصيد الحالي ($currentQty) أكبر من حد الطلب ($newMin) — الصنف في وضع آمن.'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: willBeOut
                              ? Colors.red.shade900
                              : (willBeLow ? Colors.orange.shade900 : Colors.green.shade900),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                      label: Text(
                        _submitting ? 'جارِ الحفظ...' : 'حفظ حد الطلب',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      onPressed: _submitting ? null : _submit,
                    ),
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
