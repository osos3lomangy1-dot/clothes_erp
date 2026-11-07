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

class _CustomerView extends StatefulWidget {
  const _CustomerView();

  @override
  State<_CustomerView> createState() => _CustomerViewState();
}

class _CustomerViewState extends State<_CustomerView> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: BlocConsumer<CustomerCubit, CustomerState>(
        listener: (context, state) {
          if (state.status == CustomerStatus.error && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!), backgroundColor: Colors.red),
            );
          }
        },
        builder: (context, state) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: 'Search customers by name or phone',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              context.read<CustomerCubit>().searchCustomers('');
                            },
                          )
                        : null,
                  ),
                  onChanged: (val) => context.read<CustomerCubit>().searchCustomers(val),
                ),
                const SizedBox(height: 16),
                // Customer list
                Expanded(
                  child: Builder(
                    builder: (context) {
                      if (state.status == CustomerStatus.loading && state.customers.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (state.customers.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.person_off_outlined, size: 64, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(
                                _searchCtrl.text.isEmpty
                                    ? 'No customers registered yet. Click "+" to add one.'
                                    : 'No customers found matching "${_searchCtrl.text}".',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: state.customers.length,
                        itemBuilder: (context, index) {
                          final customer = state.customers[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.purple.shade100,
                                child: Text(
                                  customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple),
                                ),
                              ),
                              title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Row(
                                children: [
                                  Text(customer.phone),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.purple.shade200),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star, size: 14, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${customer.loyaltyPoints} pts',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    onPressed: () => _showCustomerDialog(context, customer: customer),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _confirmDelete(context, customer),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCustomerDialog(context),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Customer'),
      ),
    );
  }

  void _showCustomerDialog(BuildContext context, {CustomerEntity? customer}) {
    final nameCtrl = TextEditingController(text: customer?.name ?? '');
    final phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    final pointsCtrl = TextEditingController(text: '${customer?.loyaltyPoints ?? 0}');
    final isEditing = customer != null;
    final cubit = context.read<CustomerCubit>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(isEditing ? 'Edit Customer' : 'Add Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Full Name *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Phone Number *', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pointsCtrl,
              decoration: const InputDecoration(labelText: 'Loyalty Points', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              final points = int.tryParse(pointsCtrl.text.trim()) ?? 0;

              if (name.isEmpty || phone.isEmpty) return;

              if (isEditing) {
                await cubit.updateCustomer(
                  customer.copyWith(name: name, phone: phone, loyaltyPoints: points),
                );
              } else {
                await cubit.addCustomer(
                  CustomerEntity(
                    id: '',
                    name: name,
                    phone: phone,
                    loyaltyPoints: points,
                    createdAt: DateTime.now(),
                  ),
                );
              }
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            },
            child: Text(isEditing ? 'Save Changes' : 'Add'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, CustomerEntity customer) {
    final cubit = context.read<CustomerCubit>();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text('Are you sure you want to delete "${customer.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await cubit.deleteCustomer(customer.id);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
