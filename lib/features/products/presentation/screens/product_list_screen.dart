import 'package:flutter/material.dart';
import '../../../../core/services/excel_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import './product_form_screen.dart';
import '../../../product_variants/presentation/screens/variant_list_screen.dart';
import '../cubits/product_cubit.dart';
import '../cubits/product_state.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<ProductCubit>()..getProducts(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Products'),
          actions: [
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () async {
                try {
                  await ExcelService().exportProducts();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Export completed')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Export failed: $e')),
                    );
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.upload),
              onPressed: () async {
                try {
                  // Import logic would use file_picker here
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Import not yet implemented')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Import failed: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
        body: BlocBuilder<ProductCubit, ProductState>(
          builder: (context, state) {
            if (state is ProductLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is ProductLoaded) {
              return ListView.builder(
                itemCount: state.products.length,
                itemBuilder: (context, index) {
                  final product = state.products[index];
                   return ListTile(
                     title: Text(product.name),
                     subtitle: Text(product.categoryName),
                     leading: const Icon(Icons.inventory_2),
                     trailing: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         IconButton(
                           icon: Icon(product.isActive ? Icons.toggle_on : Icons.toggle_off, color: product.isActive ? Colors.green : Colors.grey),
                           tooltip: product.isActive ? 'Deactivate' : 'Activate',
                           onPressed: () {
                             // Toggle isActive - would need cubit method
                           },
                         ),
                         IconButton(
                           icon: const Icon(Icons.add_circle_outline),
                           tooltip: 'Add Variant',
                           onPressed: () => Navigator.of(context).push(
                             MaterialPageRoute(builder: (context) => VariantListScreen(product: product)),
                           ),
                         ),
                         IconButton(
                           icon: const Icon(Icons.edit),
                           onPressed: () => Navigator.of(context).push(
                             MaterialPageRoute(builder: (context) => ProductFormScreen(product: product)),
                           ),
                         ),
                         IconButton(
                           icon: const Icon(Icons.delete, color: Colors.red),
                           onPressed: () => context.read<ProductCubit>().deleteProduct(product.id),
                         ),
                         const Icon(Icons.chevron_right),
                       ],
                     ),
                     onTap: () => Navigator.of(context).push(
                       MaterialPageRoute(builder: (context) => VariantListScreen(product: product)),
                     ),
                   );
                },
              );
            } else if (state is ProductEmpty) {
              return const Center(child: Text('No products found'));
            } else if (state is ProductError) {
              return Center(child: Text(state.message));
            }
            return const SizedBox.shrink();
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const ProductFormScreen()),
          ),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
