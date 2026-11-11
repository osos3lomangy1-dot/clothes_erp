import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../data/datasources/variant_local_data_source.dart';
import '../../domain/entities/variant_entity.dart';
import '../cubits/variant_cubit.dart';
import '../cubits/variant_state.dart';
import 'variant_form_screen.dart';

class VariantListScreen extends StatelessWidget {
  final ProductEntity product;

  const VariantListScreen({super.key, required this.product});

  void _openStockAdjustmentDialog(BuildContext context, VariantEntity variant) {
    final qtyCtrl = TextEditingController(text: '${variant.quantity}');
    final reasonCtrl = TextEditingController(text: 'تصحيح خطأ إدخال رصيد');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final enteredQty = int.tryParse(qtyCtrl.text.trim()) ?? variant.quantity;
          final diff = enteredQty - variant.quantity;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.tune_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text('تعديل رصيد المخزون', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الصنف: ${product.name} (${variant.color} - ${variant.size})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('الرصيد الحالي المسجل:'),
                          Text(
                            '${variant.quantity} قطعة',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'الرصيد الفعلي الجديد *',
                        hintText: 'أدخل الكمية الصحيحة',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.inventory_2_outlined),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'يرجى إدخال الكمية';
                        final n = int.tryParse(val.trim());
                        if (n == null || n < 0) return 'الكمية يجب أن تكون 0 أو أكثر';
                        return null;
                      },
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 10),
                    if (diff != 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          diff > 0 ? 'زيادة في المخزون: +$diff قطعة' : 'عجز / نقص في المخزون: $diff قطعة',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: diff > 0 ? Colors.green.shade700 : AppColors.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: reasonCtrl,
                      decoration: InputDecoration(
                        labelText: 'سبب التعديل *',
                        hintText: 'مثال: تصحيح خطأ إدخال، تسوية جردية، بضاعة تالفة...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.edit_note_rounded),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'يرجى كتابة سبب التعديل';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  if (formKey.currentState?.validate() != true) return;
                  final newQ = int.parse(qtyCtrl.text.trim());
                  final reason = reasonCtrl.text.trim();

                  await getIt<VariantLocalDataSource>().adjustStockQuantity(
                    variant.id,
                    newQuantity: newQ,
                    reason: reason,
                  );

                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  if (context.mounted) {
                    context.read<VariantCubit>().getVariants(product.id);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم تعديل رصيد الصنف بنجاح إلى $newQ قطعة'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: const Text('حفظ التعديل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, VariantEntity variant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('تأكيد حذف المقاس', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف المقاس (${variant.color} / ${variant.size}) وكود ${variant.productCode}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف نهائي', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<VariantCubit>().deleteVariant(variant.id, product.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<VariantCubit>()..getVariants(product.id),
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: AppColors.surface,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
                tooltip: 'رجوع للمنتجات',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مقاسات وألوان: ${product.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
                  ),
                  Text(
                    'التصنيف: ${product.categoryName}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    label: const Text('إضافة مقاس', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => VariantFormScreen(product: product)),
                      );
                      if (context.mounted) {
                        context.read<VariantCubit>().getVariants(product.id);
                      }
                    },
                  ),
                ),
              ],
            ),
            body: BlocBuilder<VariantCubit, VariantState>(
              builder: (context, state) {
                if (state is VariantLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (state is VariantLoaded) {
                  if (state.variants.isEmpty) {
                    return _buildEmptyState(context);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.variants.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final variant = state.variants[index];
                      final isOutOfStock = variant.quantity <= 0;
                      final isLowStock = variant.quantity > 0 && variant.quantity <= 10;

                      final stockColor = isOutOfStock
                          ? AppColors.error
                          : isLowStock
                              ? Colors.orange.shade700
                              : Colors.green.shade700;

                      final stockBg = isOutOfStock
                          ? AppColors.error.withValues(alpha: 0.1)
                          : isLowStock
                              ? Colors.orange.shade50
                              : Colors.green.shade50;

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  const Text('المقاس', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                  Text(
                                    variant.size,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'اللون: ${variant.color}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Text(
                                          'الكود: ${variant.productCode}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontFamily: 'monospace'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: stockBg,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'الرصيد: ${variant.quantity} قطعة',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: stockColor),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'قطاعي: ${Money(variant.salePrice).toDisplay()} ج.م',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                                      ),
                                      if (variant.wholesalePrice > 0) ...[
                                        const SizedBox(width: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.purple.shade200),
                                          ),
                                          child: Text(
                                            'جملة: ${Money(variant.wholesalePrice).toDisplay()} ج.م',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade800),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.tune_rounded, size: 20, color: Colors.teal),
                              tooltip: 'تعديل رصيد المخزون (تسوية جردية / تصحيح خطأ)',
                              onPressed: () => _openStockAdjustmentDialog(context, variant),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
                              tooltip: 'تعديل المقاس والأسعار',
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(builder: (context) => VariantFormScreen(product: product, variant: variant)),
                                );
                                if (context.mounted) {
                                  context.read<VariantCubit>().getVariants(product.id);
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                              tooltip: 'حذف المقاس',
                              onPressed: () => _confirmDelete(context, variant),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                } else if (state is VariantEmpty) {
                  return _buildEmptyState(context);
                } else if (state is VariantError) {
                  return Center(child: Text('خطأ: ${state.message}'));
                }
                return const SizedBox.shrink();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.style_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'لا توجد مقاسات أو ألوان مضافة لهذا المنتج بعد',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('إضافة مقاس الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => VariantFormScreen(product: product)),
              );
              if (context.mounted) {
                context.read<VariantCubit>().getVariants(product.id);
              }
            },
          ),
        ],
      ),
    );
  }
}
