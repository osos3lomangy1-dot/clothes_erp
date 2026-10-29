import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../cubits/pos_cubit.dart';

class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<PosCubit>()..init(),
      child: const _PosScreenContent(),
    );
  }
}

class _PosScreenContent extends StatefulWidget {
  const _PosScreenContent();

  @override
  State<_PosScreenContent> createState() => _PosScreenContentState();
}

class _PosScreenContentState extends State<_PosScreenContent> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // --- Header ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1E293B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.indigo,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Cashier: Admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text(
                          DateFormat('hh:mm a').format(DateTime.now()),
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                      onPressed: () {},
                      icon: const Icon(Icons.pause),
                      label: const Text('Held Sales (0)'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade900, foregroundColor: Colors.white),
                      onPressed: () => context.read<PosCubit>().clearCart(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('New Sale'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // --- Main Content ---
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Left Panel (Products & Search) ---
                Expanded(
                  flex: 6,
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by name or SKU...',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            ),
                            onChanged: (val) => context.read<PosCubit>().searchProducts(val),
                          ),
                        ),
                        Expanded(
                          child: BlocBuilder<PosCubit, PosState>(
                            builder: (context, state) {
                              if (state is PosLoading) return const Center(child: CircularProgressIndicator());
                              if (state is PosLoaded) {
                                if (state.filteredVariants.isEmpty) {
                                  return const Center(child: Text('No products found.'));
                                }
                                return GridView.builder(
                                  padding: const EdgeInsets.all(12),
                                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 220,
                                    mainAxisExtent: 100,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                                  itemCount: state.filteredVariants.length,
                                  itemBuilder: (context, index) {
                                    final variant = state.filteredVariants[index];
                                    final isOutOfStock = variant.quantity <= 0;
                                    return InkWell(
                                      onTap: isOutOfStock ? null : () {
                                        context.read<PosCubit>().addToCart(variant);
                                        _searchController.clear();
                                        context.read<PosCubit>().searchProducts('');
                                        FocusScope.of(context).unfocus();
                                      },
                                      child: Card(
                                        elevation: 2,
                                        color: isOutOfStock ? Colors.grey[200] : Colors.white,
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(variant.productName, style: TextStyle(fontWeight: FontWeight.bold, color: isOutOfStock ? Colors.grey : Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                                              Text('SKU: ${variant.sku}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text('\$${Money(variant.salePrice).toDisplay()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                                                  Text('Stock: ${variant.quantity}', style: TextStyle(color: isOutOfStock ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                                                ],
                                              )
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              }
                              return const Center(child: Text('Initializing...'));
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // --- Right Panel (Cart & Checkout) ---
                Expanded(
                  flex: 4,
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 12, right: 12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: BlocBuilder<PosCubit, PosState>(
                      builder: (context, state) {
                        if (state is! PosLoaded) return const Center(child: CircularProgressIndicator());

                        return Column(
                          children: [
                            Expanded(
                              child: state.cart.isEmpty
                                  ? const Center(child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
                                        SizedBox(height: 8),
                                        Text('Cart is empty', style: TextStyle(color: Colors.grey)),
                                      ],
                                    ))
                                  : SingleChildScrollView(
                                      child: DataTable(
                                        columns: const [
                                          DataColumn(label: Text('Item')),
                                          DataColumn(label: Text('Price')),
                                          DataColumn(label: Text('Qty')),
                                          DataColumn(label: Text('Total')),
                                          DataColumn(label: Text('')),
                                        ],
                                        rows: state.cart.map((item) {
                                          return DataRow(cells: [
                                            DataCell(
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                  Text(item.variantId.substring(0, 6), style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                                ],
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 60,
                                                child: TextFormField(
                                                  initialValue: Money(item.price).toDisplay(),
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 4)),
                                                  onFieldSubmitted: (val) {
                                                    final newPrice = Money.fromString(val).minorUnits;
                                                    context.read<PosCubit>().updateUnitPrice(item.variantId, newPrice);
                                                  },
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Row(
                                                children: [
                                                  IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), onPressed: () => context.read<PosCubit>().decreaseQty(item.variantId)),
                                                  SizedBox(
                                                    width: 30,
                                                    child: Text(item.quantity.toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                                                  ),
                                                  IconButton(icon: const Icon(Icons.add_circle_outline, size: 20), onPressed: () => context.read<PosCubit>().increaseQty(item.variantId)),
                                                ],
                                              ),
                                            ),
                                            DataCell(Text('\$${Money(item.total).toDisplay()}', style: const TextStyle(fontWeight: FontWeight.bold))),
                                            DataCell(
                                              IconButton(
                                                icon: const Icon(Icons.delete, color: Colors.red),
                                                onPressed: () => context.read<PosCubit>().removeFromCart(item.variantId),
                                              ),
                                            ),
                                          ]);
                                        }).toList(),
                                      ),
                                    ),
                            ),

                            // Footer
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                                border: const Border(top: BorderSide(color: Colors.black12)),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Subtotal:', style: TextStyle(fontSize: 16)),
                                      Text('\$${Money(state.subtotal).toDisplay()}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Grand Total:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                      Text('\$${Money(state.total).toDisplay()}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade600,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: state.cart.isEmpty || state.isProcessing
                                          ? null
                                          : () => _handleCheckout(context),
                                      child: state.isProcessing
                                          ? const CircularProgressIndicator(color: Colors.white)
                                          : const Text('Checkout (F12)', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleCheckout(BuildContext context) async {
    final cubit = context.read<PosCubit>();
    final success = await cubit.checkout(paymentMethod: 'cash');

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sale completed successfully!'), backgroundColor: Colors.green),
      );
    } else if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(cubit.state is PosError ? (cubit.state as PosError).message : 'Checkout failed'), backgroundColor: Colors.red),
      );
    }
  }
}

