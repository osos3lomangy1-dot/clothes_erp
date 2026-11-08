import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../domain/entities/variant_entity.dart';
import '../cubits/variant_form_cubit.dart';
import '../cubits/variant_form_state.dart';

class VariantFormScreen extends StatelessWidget {
  final ProductEntity product;
  final VariantEntity? variant;

  const VariantFormScreen({super.key, required this.product, this.variant});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<VariantFormCubit>()..init(variant),
      child: BlocConsumer<VariantFormCubit, VariantFormState>(
        listener: (context, state) {
          if (state.status == VariantFormStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.green,
                content: Text('تم حفظ بيانات المقاس بنجاح'),
              ),
            );
            AppNavigator.pop(context);
          } else if (state.status == VariantFormStatus.error && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.error,
                content: Text(state.errorMessage!),
              ),
            );
          }
        },
        builder: (context, state) {
          return Scaffold(
            backgroundColor: AppColors.surface,
            appBar: AppBar(
              backgroundColor: Colors.white,
              title: Text(
                state.isEdit ? 'تعديل المقاس: ${product.name}' : 'إضافة مقاس جديد: ${product.name}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            initialValue: state.productCode,
                            decoration: InputDecoration(
                              labelText: 'كود المنتج / الباركود (SKU)',
                              hintText: 'مثال: TSH-BLK-M',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onChanged: (value) => context.read<VariantFormCubit>().onProductCodeChanged(value),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: state.color,
                                  decoration: InputDecoration(
                                    labelText: 'اللون',
                                    hintText: 'مثال: أسود',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onChanged: (value) => context.read<VariantFormCubit>().onColorChanged(value),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  initialValue: state.size,
                                  decoration: InputDecoration(
                                    labelText: 'المقاس',
                                    hintText: 'مثال: L أو 42',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onChanged: (value) => context.read<VariantFormCubit>().onSizeChanged(value),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            initialValue: state.quantity.toString(),
                            decoration: InputDecoration(
                              labelText: 'الكمية الحالية (الرصيد)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) => context.read<VariantFormCubit>().onQuantityChanged(int.tryParse(value) ?? 0),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: (state.costPrice / 100).toStringAsFixed(2),
                                  decoration: InputDecoration(
                                    labelText: 'سعر التكلفة (ج.م) *',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (value) {
                                    final val = double.tryParse(value) ?? 0.0;
                                    context.read<VariantFormCubit>().onCostPriceChanged((val * 100).toInt());
                                  },
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  initialValue: (state.salePrice / 100).toStringAsFixed(2),
                                  decoration: InputDecoration(
                                    labelText: 'سعر البيع قطاعي (ج.م) *',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (value) {
                                    final val = double.tryParse(value) ?? 0.0;
                                    context.read<VariantFormCubit>().onSalePriceChanged((val * 100).toInt());
                                  },
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: TextFormField(
                                  initialValue: state.wholesalePrice > 0 ? (state.wholesalePrice / 100).toStringAsFixed(2) : '',
                                  decoration: InputDecoration(
                                    labelText: 'سعر الجملة (ج.م)',
                                    hintText: 'اختياري',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (value) {
                                    final val = double.tryParse(value) ?? 0.0;
                                    context.read<VariantFormCubit>().onWholesalePriceChanged((val * 100).toInt());
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            initialValue: state.minStock.toString(),
                            decoration: InputDecoration(
                              labelText: 'حد إعادة الطلب (تنبيه نقص المخزون)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) => context.read<VariantFormCubit>().onMinStockChanged(int.tryParse(value) ?? 0),
                          ),
                          const SizedBox(height: 28),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: state.status == VariantFormStatus.loading
                                ? null
                                : () => context.read<VariantFormCubit>().submit(id: variant?.id, productId: product.id),
                            child: state.status == VariantFormStatus.loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text(
                                    state.isEdit ? 'تحديث المقاس' : 'حفظ المقاس',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
