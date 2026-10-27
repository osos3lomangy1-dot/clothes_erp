import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../cubits/pos_cubit.dart';
import '../../domain/entities/sale_item_entity.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';

class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<PosCubit>(),
      child: const _PosView(),
    );
  }
}

class _PosView extends StatelessWidget {
  const _PosView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Point of Sale'),
        actions: [
          IconButton(
            onPressed: () => context.read<PosCubit>().clearCart(),
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear Cart',
          ),
        ],
      ),
      body: BlocListener<PosCubit, PosState>(
        listener: (context, state) {
          if (state.status == PosStatus.error && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!)),
            );
          }
          if (state.status == PosStatus.success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sale completed successfully!')),
            );
          }
        },
        child: Row(
          children: [
            // Left: Search & Product List
            Expanded(
              flex: 3,
              child: _SearchPanel(),
            ),
            // Right: Cart
            Expanded(
              flex: 2,
              child: _CartPanel(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPanel extends StatefulWidget {
  @override
  State<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<_SearchPanel> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: 'Search by product code or barcode',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (val) => context.read<PosCubit>().searchVariants(val),
          ),
        ),
        Expanded(
          child: BlocBuilder<PosCubit, PosState>(
            builder: (context, state) {
              if (state.status == PosStatus.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView.builder(
                itemCount: state.searchResults.length,
                itemBuilder: (context, index) {
                  final variant = state.searchResults[index];
                  return _VariantTile(variant: variant);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VariantTile extends StatelessWidget {
  final VariantEntity variant;

  const _VariantTile({required this.variant});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text('${variant.productCode} - ${variant.color} - ${variant.size}'),
        subtitle: Text('Stock: ${variant.quantity} | Price: ${variant.salePrice.toStringAsFixed(2)}'),
        trailing: IconButton(
          icon: const Icon(Icons.add_shopping_cart),
          onPressed: () => context.read<PosCubit>().addToCart(variant),
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        return Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: state.cart.length,
                  itemBuilder: (context, index) {
                    final item = state.cart[index];
                    return _CartItemTile(item: item);
                  },
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      state.total.toStringAsFixed(2),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: state.paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
                  DropdownMenuItem(value: 'credit', child: Text('Credit')),
                ],
                onChanged: (val) {
                  if (val != null) context.read<PosCubit>().changePaymentMethod(val);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: state.status == PosStatus.checkoutLoading
                      ? null
                      : () {
                          context.read<PosCubit>().checkout(
                            'cashier_id_placeholder',
                            'Cashier',
                          );
                        },
                  child: state.status == PosStatus.checkoutLoading
                      ? const CircularProgressIndicator()
                      : const Text('Checkout'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final SaleItemEntity item;

  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(item.productName),
        subtitle: Text('${item.color} - ${item.size} | ${item.price.toStringAsFixed(2)} x ${item.quantity}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: () => context.read<PosCubit>().updateQuantity(item.variantId, item.quantity - 1),
            ),
            Text('${item.quantity}'),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => context.read<PosCubit>().updateQuantity(item.variantId, item.quantity + 1),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => context.read<PosCubit>().removeFromCart(item.variantId),
            ),
          ],
        ),
      ),
    );
  }
}
