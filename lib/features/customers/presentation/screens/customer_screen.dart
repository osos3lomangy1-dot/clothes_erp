import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../domain/entities/customer_entity.dart';
import '../cubits/customer_cubit.dart';

class CustomerScreen extends StatelessWidget {
  const CustomerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<CustomerCubit>(),
      child: const _CustomerView(),
    );
  }
}

class _CustomerView extends StatelessWidget {
  const _CustomerView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: BlocBuilder<CustomerCubit, CustomerState>(
        builder: (context, state) {
          if (state.status == CustomerStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == CustomerStatus.error) {
            return Center(child: Text(state.errorMessage ?? 'Error'));
          }
          if (state.customers.isEmpty) {
            return const Center(child: Text('No customers yet.'));
          }
          return ListView.builder(
            itemCount: state.customers.length,
            itemBuilder: (context, index) {
              final customer = state.customers[index];
              return Card(
                child: ListTile(
                  title: Text(customer.name),
                  subtitle: Text('${customer.phone} • Points: ${customer.loyaltyPoints}'),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Simple add dialog
          final nameController = TextEditingController();
          final phoneController = TextEditingController();
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Add Customer'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
                  TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    context.read<CustomerCubit>().addCustomer(
                          CustomerEntity(
                            id: '',
                            name: nameController.text,
                            phone: phoneController.text,
                            createdAt: DateTime.now(),
                          ),
                        );
                    Navigator.pop(ctx);
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
