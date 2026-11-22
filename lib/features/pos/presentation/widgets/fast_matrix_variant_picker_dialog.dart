import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../cubits/pos_cubit.dart';

/// Fast Matrix Variant Picker Dialog (Task 17)
/// Allows cashiers in multi-variant businesses (rugs, fabrics, shoes, clothing)
/// to select multiple sizes and colors with quantities simultaneously in one dialog.
class FastMatrixVariantPickerDialog extends StatefulWidget {
  final String productId;
  final String productName;
  final List<VariantEntity> variants;
  final ProductEntity? product;

  const FastMatrixVariantPickerDialog({
    super.key,
    required this.productId,
    required this.productName,
    required this.variants,
    this.product,
  });

  @override
  State<FastMatrixVariantPickerDialog> createState() =>
      _FastMatrixVariantPickerDialogState();
}

class _FastMatrixVariantPickerDialogState
    extends State<FastMatrixVariantPickerDialog> {
  final Map<String, int> _selectedQuantities = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final v in widget.variants) {
      _selectedQuantities[v.id] = 0;
      _controllers[v.id] = TextEditingController(text: '0');
    }
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  int get _totalSelectedPieces =>
      _selectedQuantities.values.fold(0, (sum, q) => sum + q);

  int get _totalSelectedVariantsCount =>
      _selectedQuantities.values.where((q) => q > 0).length;

  int get _totalSelectedPrice {
    var total = 0;
    for (final v in widget.variants) {
      final q = _selectedQuantities[v.id] ?? 0;
      total += v.salePrice * q;
    }
    return total;
  }

  void _increment(VariantEntity v) {
    if (v.quantity <= 0) return;
    final current = _selectedQuantities[v.id] ?? 0;
    if (current < v.quantity) {
      final next = current + 1;
      setState(() {
        _selectedQuantities[v.id] = next;
        _controllers[v.id]?.text = '$next';
      });
    }
  }

  void _decrement(VariantEntity v) {
    final current = _selectedQuantities[v.id] ?? 0;
    if (current > 0) {
      final next = current - 1;
      setState(() {
        _selectedQuantities[v.id] = next;
        _controllers[v.id]?.text = '$next';
      });
    }
  }

  void _onQtyChanged(VariantEntity v, String text) {
    final normalized = Money.normalizeDigits(text.trim());
    final val = int.tryParse(normalized);
    if (val == null || val < 0) return;
    final clamped = val > v.quantity ? v.quantity : val;
    setState(() {
      _selectedQuantities[v.id] = clamped;
    });
  }

  void _onSubmitted(VariantEntity v, String text) {
    _onQtyChanged(v, text);
    _controllers[v.id]?.text = '${_selectedQuantities[v.id] ?? 0}';
  }

  void _submitSelection() {
    final toAdd = <VariantEntity, int>{};
    for (final v in widget.variants) {
      final q = _selectedQuantities[v.id] ?? 0;
      if (q > 0) {
        toAdd[v] = q;
      }
    }
    if (toAdd.isEmpty) return;

    final posCubit = context.read<PosCubit>();
    posCubit.addMultipleToCart(toAdd);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.productName.isNotEmpty
        ? widget.productName
        : (widget.variants.isNotEmpty
              ? widget.variants.first.productName
              : 'مصفوفة المقاسات والألوان');

    return Dialog(
      key: const Key('fast_matrix_variant_picker_dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer.withValues(alpha: 0.12),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.grid_view_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'مصفوفة المقاسات والألوان (${widget.variants.length} مقاس/لون متوفر)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Variants Matrix List
            Expanded(
              child: widget.variants.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد مقاسات أو ألوان مسجلة لهذا الصنف',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: widget.variants.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final v = widget.variants[index];
                        final isOut = v.quantity <= 0;
                        final currentQty = _selectedQuantities[v.id] ?? 0;
                        final isSelected = currentQty > 0;

                        return Container(
                          key: Key('matrix_row_${v.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.05)
                                : AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : (isOut
                                        ? Colors.grey.shade300
                                        : AppColors.outlineVariant),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Size & Color Specs
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (v.size.isNotEmpty &&
                                            v.size != '-')
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  AppColors.surfaceContainerLow,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'مقاس: ${v.size}',
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.onSurface,
                                              ),
                                            ),
                                          ),
                                        if (v.color.isNotEmpty &&
                                            v.color != '-')
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  AppColors.surfaceContainerLow,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'لون: ${v.color}',
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.onSurface,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'كود: ${v.sku}',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10.5,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Stock Badge & Price
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${Money(v.salePrice).toDisplay()} ج.م',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isOut
                                            ? const Color(0xFFFEF2F2)
                                            : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isOut
                                            ? 'نفذت الكمية'
                                            : 'المتاح: ${v.quantity}',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: isOut
                                              ? AppColors.error
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Quantity Stepper
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: Key('matrix_minus_${v.id}'),
                                    onPressed: (currentQty > 0)
                                        ? () => _decrement(v)
                                        : null,
                                    icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                      size: 22,
                                    ),
                                    color: AppColors.primary,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                  ),
                                  Container(
                                    width: 44,
                                    height: 32,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white
                                          : AppColors.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.outlineVariant,
                                      ),
                                    ),
                                    child: TextField(
                                      key: Key('matrix_input_${v.id}'),
                                      controller: _controllers[v.id],
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      enabled: !isOut,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.onSurface,
                                      ),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.zero,
                                        isDense: true,
                                        border: InputBorder.none,
                                      ),
                                      onChanged: (text) =>
                                          _onQtyChanged(v, text),
                                      onSubmitted: (text) =>
                                          _onSubmitted(v, text),
                                    ),
                                  ),
                                  IconButton(
                                    key: Key('matrix_plus_${v.id}'),
                                    onPressed:
                                        (!isOut && currentQty < v.quantity)
                                        ? () => _increment(v)
                                        : null,
                                    icon: const Icon(
                                      Icons.add_circle_outline_rounded,
                                      size: 22,
                                    ),
                                    color: AppColors.primary,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            const Divider(height: 1),

            // Footer with Summary and Add to Cart Action
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'إجمالي المحدد: $_totalSelectedPieces قطعة ($_totalSelectedVariantsCount مقاس)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        Text(
                          '${Money(_totalSelectedPrice).toDisplay()} ج.م',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    key: const Key('matrix_picker_add_btn'),
                    onPressed: _totalSelectedPieces > 0
                        ? _submitSelection
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                    label: Text(
                      _totalSelectedPieces > 0
                          ? 'إضافة الأصناف المحددة ($_totalSelectedPieces قطعة)'
                          : 'إضافة الأصناف المحددة إلى السلة',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
