import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../cubits/inventory_log_cubit.dart';

class InventoryLogsScreen extends StatelessWidget {
  const InventoryLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<InventoryLogCubit>(),
      child: const _InventoryLogsView(),
    );
  }
}

class _InventoryLogsView extends StatelessWidget {
  const _InventoryLogsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Logs')),
      body: BlocBuilder<InventoryLogCubit, InventoryLogState>(
        builder: (context, state) {
          if (state.status == InventoryLogStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == InventoryLogStatus.error) {
            return Center(child: Text(state.errorMessage ?? 'Error'));
          }
          if (state.logs.isEmpty) {
            return const Center(child: Text('No inventory logs yet.'));
          }
          return ListView.builder(
            itemCount: state.logs.length,
            itemBuilder: (context, index) {
              final log = state.logs[index];
              return Card(
                child: ListTile(
                  leading: Icon(
                    log.type == 'in' ? Icons.arrow_downward : Icons.arrow_upward,
                    color: log.type == 'in' ? Colors.green : Colors.red,
                  ),
                  title: Text('Product: ${log.productId}${log.variantId != null ? ' / Variant: ${log.variantId}' : ''}'),
                  subtitle: Text('Qty: ${log.quantity} | By: ${log.userId}'),
                  trailing: Text(
                    '${log.date.hour}:${log.date.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
