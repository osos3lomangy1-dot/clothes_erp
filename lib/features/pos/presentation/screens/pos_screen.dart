import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../cubits/pos_cubit.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';

class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<PosCubit>()..loadVariants(),
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
        actions: const [
          Text('F2 Search  ·  F4 Qty  ·  F12 Checkout', style: TextStyle(fontSize: 10, color: Colors.white70)),
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
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF673AB7),
              child: Row(
                children: [
                  const Text('Cashier', style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 4),
                  const Text('Admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  _ShortcutButton(Icons.search, 'F2 Search', () {}, primary: false),
                  _ShortcutButton(Icons.person_add, 'Add Customer', () {}, primary: false),
                  _ShortcutButton(Icons.pause, 'Hold Sale', () {}, primary: false),
                  _ShortcutButton(Icons.clear, 'Clear Cart', () => context.read<PosCubit>().clearCart(), primary: false),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(flex: 3, child: _SearchPanel()),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 4, child: _CartPanel()),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF673AB7),
              child: Row(
                children: [
                  const Text('Grand Total:', style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 8),
                  BlocBuilder<PosCubit, PosState>(
                    builder: (context, state) => Text(
                      state.total.toStringAsFixed(2),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  _ShortcutButton(Icons.print, 'Print Receipt', () {}, primary: false),
                  _ShortcutButton(Icons.cancel, 'Cancel Sale', () => context.read<PosCubit>().clearCart(), primary: false),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 200,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => context.read<PosCubit>().checkout('cashier_id_placeholder', 'Cashier'),
                      child: const Text('Checkout'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF673AB7),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;
  const _ShortcutButton(this.icon, this.label, this.onPressed, {this.primary = false});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: primary ? Colors.amber : const Color(0xFF673AB7),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              labelText: 'Search by product code',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (val) => context.read<PosCubit>().searchProducts(val),
          ),
        ),
        Expanded(
          child: BlocBuilder<PosCubit, PosState>(
            builder: (context, state) {
              if (state.status == PosStatus.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.searchResults.isEmpty) {
                return const Center(child: Text('No products found. Add products in the Products screen first.'));
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
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            children: [
              Expanded(
                child: state.cart.isEmpty
                    ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.shopping_cart, size: 64, color: Colors.grey), SizedBox(height: 8), Text('Cart is empty')]))
                    : SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('#', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('SKU', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Item Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Qty', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Unit Price', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Discount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Action', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            ],
                            rows: state.cart.asMap().entries.map((entry) {
                              final i = entry.key;
                              final item = entry.value;
                              return DataRow(cells: [
                                DataCell(Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                                DataCell(Text(item.variantId.substring(0, 6), style: const TextStyle(fontSize: 11))),
                                DataCell(Text(item.productName, style: const TextStyle(fontSize: 11))),
                                DataCell(SizedBox(
                                  width: 70,
                                  child: TextField(
                                    controller: TextEditingController(text: item.quantity.toString()),
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                                    onChanged: (val) {
                                      final n = int.tryParse(val);
                                      if (n != null) context.read<PosCubit>().updateQuantity(item.variantId, n);
                                    },
                                  ),
                                )),
                                DataCell(SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: TextEditingController(text: item.price.toString()),
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                                    onChanged: (val) {
                                      final n = int.tryParse(val) ?? item.price;
                                      context.read<PosCubit>().updateUnitPrice(item.variantId, n);
                                    },
                                  ),
                                )),
                                DataCell(SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: TextEditingController(text: item.discount.toString()),
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                                    onChanged: (val) {
                                      final n = int.tryParse(val) ?? item.discount;
                                      context.read<PosCubit>().applyItemDiscount(item.variantId, n);
                                    },
                                  ),
                                )),
                                DataCell(Text(item.total.toStringAsFixed(2), style: const TextStyle(fontSize: 11))),
                                DataCell(IconButton(icon: const Icon(Icons.delete, size: 16), onPressed: () => context.read<PosCubit>().removeFromCart(item.variantId))),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Grand Total:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(state.total.toStringAsFixed(2), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => context.read<PosCubit>().checkout('cashier_id_placeholder', 'Cashier'),
                  child: const Text('Checkout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF673AB7),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
