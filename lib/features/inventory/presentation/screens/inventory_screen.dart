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
          title: const Text('Inventory'),
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
                return RefreshIndicator(
                  onRefresh: () => context.read<InventoryCubit>().loadInventory(),
                  child: ListView(
                    children: const [
                      SizedBox(height: 100),
                      Center(
                        child: Column(
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No inventory items found', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () => context.read<InventoryCubit>().loadInventory(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: state.items.length,
                  itemBuilder: (context, index) {
                    final item = state.items[index];
                    final bool isLow = item.quantity <= item.minStock;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isLow ? Colors.red.shade100 : Colors.green.shade100,
                          child: Icon(
                            isLow ? Icons.warning : Icons.check,
                            color: isLow ? Colors.red : Colors.green,
                          ),
                        ),
                        title: Text(
                          item.productCode,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
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
                      ),
                    );
                  },
                ),
              );
            } else if (state is InventoryError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(state.message),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.read<InventoryCubit>().loadInventory(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
