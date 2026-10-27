import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../../domain/entities/product_entity.dart';
import '../cubits/product_form_cubit.dart';
import '../cubits/product_form_state.dart';

class ProductFormScreen extends StatelessWidget {
  final ProductEntity? product;

  const ProductFormScreen({super.key, this.product});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<ProductFormCubit>()..init(product),
      child: BlocConsumer<ProductFormCubit, ProductFormState>(
        listener: (context, state) {
          if (state.status == ProductFormStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Product saved successfully')),
            );
            AppNavigator.pop(context);
          } else if (state.status == ProductFormStatus.error && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!)),
            );
          }
        },
        builder: (context, state) {
          if (state.status == ProductFormStatus.loading && state.categories.isEmpty) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(state.isEdit ? 'Edit Product' : 'Add Product'),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextFormField(
                    initialValue: state.name,
                    decoration: const InputDecoration(labelText: 'Product Name'),
                    onChanged: (value) => context.read<ProductFormCubit>().onNameChanged(value),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: state.description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    onChanged: (value) => context.read<ProductFormCubit>().onDescriptionChanged(value),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: state.categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: state.categories.map((category) {
                      return DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        final category = state.categories.firstWhere((c) => c.id == value);
                        context.read<ProductFormCubit>().onCategoryChanged(category.id, category.name);
                      }
                    },
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: state.status == ProductFormStatus.loading
                          ? null
                          : () => context.read<ProductFormCubit>().submit(product?.id),
                      child: state.status == ProductFormStatus.loading
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
