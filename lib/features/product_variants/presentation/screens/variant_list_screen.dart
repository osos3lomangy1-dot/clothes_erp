import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../cubits/variant_cubit.dart';
import '../cubits/variant_state.dart';

class VariantListScreen extends StatelessWidget {
  final ProductEntity product;

  const VariantListScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<VariantCubit>()..getVariants(product.id),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Variants: ${product.name}'),
        ),
        body: BlocBuilder<VariantCubit, VariantState>(
          builder: (context, state) {
            if (state is VariantLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is VariantLoaded) {
              return ListView.builder(
                itemCount: state.variants.length,
                itemBuilder: (context, index) {
                  final variant = state.variants[index];
                  return ListTile(
                    title: Text('${variant.productCode} - ${variant.color} / ${variant.size}'),
                    subtitle: Text('Qty: ${variant.quantity} | Price: ${variant.salePrice}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => AppNavigator.push(
                            context,
                            AppRoutes.variantForm,
                            extra: {'product': product, 'variant': variant},
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => context.read<VariantCubit>().deleteVariant(variant.id, product.id),
                        ),
                      ],
                    ),
                  );
                },
              );
            } else if (state is VariantEmpty) {
              return const Center(child: Text('No variants found'));
            } else if (state is VariantError) {
              return Center(child: Text(state.message));
            }
            return const SizedBox.shrink();
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => AppNavigator.push(
            context,
            AppRoutes.variantForm,
            extra: {'product': product},
          ),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
