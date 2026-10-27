import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
              const SnackBar(content: Text('Variant saved successfully')),
            );
            AppNavigator.pop(context);
          } else if (state.status == VariantFormStatus.error && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!)),
            );
          }
        },
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: Text(state.isEdit ? 'Edit Variant' : 'Add Variant'),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextFormField(
                    initialValue: state.productCode,
                    decoration: const InputDecoration(labelText: 'Product Code (Unique)'),
                    onChanged: (value) => context.read<VariantFormCubit>().onProductCodeChanged(value),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: state.color,
                          decoration: const InputDecoration(labelText: 'Color'),
                          onChanged: (value) => context.read<VariantFormCubit>().onColorChanged(value),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          initialValue: state.size,
                          decoration: const InputDecoration(labelText: 'Size'),
                          onChanged: (value) => context.read<VariantFormCubit>().onSizeChanged(value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: state.quantity.toString(),
                    decoration: const InputDecoration(labelText: 'Quantity'),
                    keyboardType: TextInputType.number,
                    onChanged: (value) => context.read<VariantFormCubit>().onQuantityChanged(int.tryParse(value) ?? 0),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: state.costPrice.toString(),
                          decoration: const InputDecoration(labelText: 'Cost Price'),
                          keyboardType: TextInputType.number,
                          onChanged: (value) => context.read<VariantFormCubit>().onCostPriceChanged(int.tryParse(value) ?? 0),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          initialValue: state.salePrice.toString(),
                          decoration: const InputDecoration(labelText: 'Sale Price'),
                          keyboardType: TextInputType.number,
                          onChanged: (value) => context.read<VariantFormCubit>().onSalePriceChanged(int.tryParse(value) ?? 0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: state.minStock.toString(),
                    decoration: const InputDecoration(labelText: 'Min Stock Alert'),
                    keyboardType: TextInputType.number,
                    onChanged: (value) => context.read<VariantFormCubit>().onMinStockChanged(int.tryParse(value) ?? 0),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: state.status == VariantFormStatus.loading
                          ? null
                          : () => context.read<VariantFormCubit>().submit(id: variant?.id, productId: product.id),
                      child: state.status == VariantFormStatus.loading
                          ? const CircularProgressIndicator()
                          : Text(state.isEdit ? 'Update' : 'Save'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
