import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../cubits/inventory_cubit.dart';
import '../cubits/inventory_state.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<InventoryCubit>()..loadInventory(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventory Management'),
          actions: [
            BlocBuilder<InventoryCubit, InventoryState>(
              builder: (context, state) {
                bool isLowStock = false;
                if (state is InventoryLoaded) {
                  isLowStock = state.showLowStockOnly;
                }
                return Row(
                  children: [
                    const Text('Low Stock'),
                    Switch(
                      value: isLowStock,
                      onChanged: (value) => context.read<InventoryCubit>().toggleLowStockFilter(value),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        body: BlocBuilder<InventoryCubit, InventoryState>(
          builder: (context, state) {
            if (state is InventoryLoading) {
              return const Center(child: CircularProgressIndicator());
            } else if (state is InventoryLoaded) {
              if (state.items.isEmpty) {
                return const Center(child: Text('No items found in inventory'));
              }
              return ListView.builder(
                itemCount: state.items.length,
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  final bool isLow = item.quantity <= item.minStock;
                  return ListTile(
                    title: Text(item.productCode),
                    subtitle: Text('${item.color} / ${item.size}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Qty: ${item.quantity}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isLow ? Colors.red : Colors.green,
                          ),
                        ),
                        Text('Min: ${item.minStock}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  );
                },
              );
            } else if (state is InventoryError) {
              return Center(child: Text(state.message));
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
