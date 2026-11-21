import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/entities/pre_order_item_entity.dart';
import '../cubits/pre_orders_cubit.dart';

class EditPreOrderItemDialog extends StatefulWidget {
  final String orderId;
  final PreOrderItemEntity? item;

  const EditPreOrderItemDialog({
    super.key,
    required this.orderId,
    this.item,
  });

  static Future<void> show(
    BuildContext context, {
    required String orderId,
    PreOrderItemEntity? item,
  }) {
    return showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<PreOrdersCubit>(),
        child: EditPreOrderItemDialog(orderId: orderId, item: item),
      ),
    );
  }

  @override
  State<EditPreOrderItemDialog> createState() => _EditPreOrderItemDialogState();
}

class _EditPreOrderItemDialogState extends State<EditPreOrderItemDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _variantCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _commissionCtrl;
  late TextEditingController _unitPriceCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _notesCtrl;

  late String _sourcePlatform;
  bool _isSaving = false;
  bool _isUpdatingFromCostOrComm = false;
  bool _isUpdatingFromSale = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _nameCtrl = TextEditingController(text: item?.productName ?? '');
    _variantCtrl = TextEditingController(text: item?.variantDescription ?? '');
    _qtyCtrl = TextEditingController(text: (item?.quantity ?? 1).toString());

    final initialCost = item != null ? item.costPricePiasters / 100 : 0.0;
    final initialPrice = item != null ? item.unitPricePiasters / 100 : 0.0;
    final initialCommission = item != null
        ? (item.commissionPiasters > 0
            ? item.commissionPiasters / 100
            : (initialPrice - initialCost).clamp(0.0, double.infinity))
        : 50.0;

    _costCtrl = TextEditingController(
      text: initialCost > 0 ? _formatNumber(initialCost) : '',
    );
    _commissionCtrl = TextEditingController(
      text: _formatNumber(initialCommission),
    );
    _unitPriceCtrl = TextEditingController(
      text: initialPrice > 0 ? _formatNumber(initialPrice) : '',
    );

    _urlCtrl = TextEditingController(text: item?.itemUrl ?? '');
    _notesCtrl = TextEditingController(text: item?.notes ?? '');

    _sourcePlatform = item?.sourcePlatform ?? PreOrderPlatforms.shein;
    if (!PreOrderPlatforms.all.contains(_sourcePlatform)) {
      _sourcePlatform = PreOrderPlatforms.localSupplierOther;
    }

    _costCtrl.addListener(_onCostOrCommissionChanged);
    _commissionCtrl.addListener(_onCostOrCommissionChanged);
    _unitPriceCtrl.addListener(_onSalePriceChanged);
    _qtyCtrl.addListener(() => setState(() {}));
  }

  String _formatNumber(double val) {
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    return val.toStringAsFixed(2);
  }

  void _onCostOrCommissionChanged() {
    if (_isUpdatingFromSale) return;
    _isUpdatingFromCostOrComm = true;

    final cost = double.tryParse(_costCtrl.text.trim()) ?? 0.0;
    final commission = double.tryParse(_commissionCtrl.text.trim()) ?? 0.0;
    final calculatedSale = cost + commission;

    if (calculatedSale > 0) {
      final formatted = _formatNumber(calculatedSale);
      if (_unitPriceCtrl.text != formatted) {
        _unitPriceCtrl.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
    _isUpdatingFromCostOrComm = false;
    setState(() {});
  }

  void _onSalePriceChanged() {
    if (_isUpdatingFromCostOrComm) return;
    _isUpdatingFromSale = true;

    final cost = double.tryParse(_costCtrl.text.trim()) ?? 0.0;
    final sale = double.tryParse(_unitPriceCtrl.text.trim()) ?? 0.0;
    final diff = sale - cost;

    if (sale > 0 && cost > 0) {
      final formatted = _formatNumber(diff.clamp(0.0, double.infinity));
      if (_commissionCtrl.text != formatted) {
        _commissionCtrl.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
    _isUpdatingFromSale = false;
    setState(() {});
  }

  @override
  void dispose() {
    _costCtrl.removeListener(_onCostOrCommissionChanged);
    _commissionCtrl.removeListener(_onCostOrCommissionChanged);
    _unitPriceCtrl.removeListener(_onSalePriceChanged);
    _nameCtrl.dispose();
    _variantCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _commissionCtrl.dispose();
    _unitPriceCtrl.dispose();
    _urlCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final variant = _variantCtrl.text.trim();
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
    final costPounds = double.tryParse(_costCtrl.text.trim()) ?? 0.0;
    final commPounds = double.tryParse(_commissionCtrl.text.trim()) ?? 0.0;
    final unitPricePounds = double.tryParse(_unitPriceCtrl.text.trim()) ?? 0.0;
    final url = _urlCtrl.text.trim();
    final notes = _notesCtrl.text.trim();

    final costPiasters = (costPounds * 100).round();
    final commPiasters = (commPounds * 100).round();
    final unitPricePiasters = (unitPricePounds * 100).round();
    final totalPricePiasters = qty * unitPricePiasters;

    setState(() => _isSaving = true);
    final cubit = context.read<PreOrdersCubit>();

    bool ok = false;
    if (widget.item != null) {
      final updated = widget.item!.copyWith(
        productName: name,
        variantDescription: variant.isNotEmpty ? variant : null,
        quantity: qty,
        costPricePiasters: costPiasters,
        commissionPiasters: commPiasters,
        unitPricePiasters: unitPricePiasters,
        totalPricePiasters: totalPricePiasters,
        itemUrl: url.isNotEmpty ? url : null,
        sourcePlatform: _sourcePlatform,
        notes: notes.isNotEmpty ? notes : null,
      );
      ok = await cubit.updateOrderItem(updated);
    } else {
      final newItem = PreOrderItemEntity(
        id: const Uuid().v4(),
        preOrderId: widget.orderId,
        productName: name,
        variantDescription: variant.isNotEmpty ? variant : null,
        quantity: qty,
        costPricePiasters: costPiasters,
        commissionPiasters: commPiasters,
        unitPricePiasters: unitPricePiasters,
        totalPricePiasters: totalPricePiasters,
        itemUrl: url.isNotEmpty ? url : null,
        sourcePlatform: _sourcePlatform,
        notes: notes.isNotEmpty ? notes : null,
        status: 'active',
      );
      ok = await cubit.addOrderItem(widget.orderId, newItem);
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (ok) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.item != null
                  ? 'تم تحديث بيانات الصنف وإعادة احتساب الأوردر بنجاح'
                  : 'تمت إضافة الصنف وإعادة احتساب الأوردر بنجاح',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
    final costPounds = double.tryParse(_costCtrl.text.trim()) ?? 0.0;
    final unitPricePounds = double.tryParse(_unitPriceCtrl.text.trim()) ?? 0.0;
    final totalCost = qty * costPounds;
    final totalSale = qty * unitPricePounds;
    final totalProfit = (totalSale - totalCost).clamp(0.0, double.infinity);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // الترويسة
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isEditing
                              ? Icons.edit_note_rounded
                              : Icons.add_shopping_cart_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEditing
                                  ? 'تعديل بيانات الصنف'
                                  : 'إضافة صنف جديد للطلب',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            Text(
                              isEditing
                                  ? 'تحديث المواصفات، التكلفة، وسعر البيع مع إعادة احتساب المتبقي تلقائياً'
                                  : 'إضافة صنف جديد للطلب وحساب الإجماليات والمتبقي بدقة فورية',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11.5,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.onSurfaceVariant,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),

                  const Divider(height: 24, color: AppColors.outlineVariant),

                  // 1. اسم الصنف والمواصفات
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            labelText: 'اسم الصنف أو كود المنتج (SKU) *',
                            labelStyle: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12.5,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'يرجى إدخال اسم أو كود الصنف';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _variantCtrl,
                          decoration: InputDecoration(
                            labelText: 'المقاس / اللون / الخامة',
                            labelStyle: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 2. الكمية والمنصة
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _qtyCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: 'الكمية *',
                            labelStyle: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                          validator: (val) {
                            final q = int.tryParse(val ?? '');
                            if (q == null || q < 1) {
                              return 'الكمية 1 على الأقل';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: _sourcePlatform,
                          decoration: InputDecoration(
                            labelText: 'مصدر الطلب / المنصة',
                            labelStyle: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: AppColors.onSurface,
                          ),
                          items: PreOrderPlatforms.all.map((p) {
                            return DropdownMenuItem(
                              value: p,
                              child: Text(
                                p,
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _sourcePlatform = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // 3. كارت التسعير والحسابات الفورية
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'التسعير والحسابات الفورية (للقطعة الواحدة):',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _costCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'سعر الجملة (التكلفة) *',
                                  suffixText: 'ج.م',
                                  labelStyle: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  isDense: true,
                                ),
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                validator: (val) {
                                  final num = double.tryParse(val ?? '');
                                  if (num == null || num < 0) {
                                    return 'أدخل تكلفة صحيحة';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _commissionCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'عمولتي',
                                  suffixText: 'ج.م',
                                  labelStyle: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  isDense: true,
                                ),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _unitPriceCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'سعر البيع للعميل *',
                                  suffixText: 'ج.م',
                                  labelStyle: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  isDense: true,
                                ),
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.onSurface,
                                ),
                                validator: (val) {
                                  final num = double.tryParse(val ?? '');
                                  if (num == null || num <= 0) {
                                    return 'أدخل سعر بيع صحيح';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),
                        // ملخص إجمالي الصنف
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'إجمالي التكلفة: ${Money((totalCost * 100).round()).toDisplay()} ج',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'إجمالي البيع: ${Money((totalSale * 100).round()).toDisplay()} ج',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            Text(
                              'صافي الربح: +${Money((totalProfit * 100).round()).toDisplay()} ج',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 4. الرابط والملاحظات
                  TextFormField(
                    controller: _urlCtrl,
                    decoration: InputDecoration(
                      labelText: 'رابط الصنف أو صفحة المتجر (اختياري)',
                      prefixIcon: const Icon(
                        Icons.link_rounded,
                        size: 18,
                        color: AppColors.onSurfaceVariant,
                      ),
                      labelStyle: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5),
                  ),

                  const SizedBox(height: 10),

                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'ملاحظات إضافية على الصنف (اختياري)',
                      labelStyle: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  ),

                  const SizedBox(height: 20),

                  // أزرار الإجراءات
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.onSurfaceVariant,
                          side: const BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text(
                          'إلغاء',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                          ),
                        ),
                        onPressed: _isSaving ? null : () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 16),
                        label: Text(
                          isEditing
                              ? 'حفظ التعديلات وتحديث الحسابات'
                              : 'إضافة الصنف وتحديث الحسابات',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _isSaving ? null : _submit,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
