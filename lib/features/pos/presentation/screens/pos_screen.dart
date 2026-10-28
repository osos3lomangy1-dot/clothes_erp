import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          _ShortcutsHint(),
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
            // Top Action Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF673AB7),
              child: Row(
                children: [
                  const Text('Cashier', style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 4),
                  const Text('Admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  _ShortcutButton(Icons.search, 'F2 Search', () {}),
                  _ShortcutButton(Icons.person_add, 'Add Customer', () {}),
                  _ShortcutButton(Icons.pause, 'Hold Sale', () {}),
                  _ShortcutButton(Icons.clear, 'Clear Cart', () => context.read<PosCubit>().clearCart()),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  // Left: Search & Product List
                  Expanded(
                    flex: 3,
                    child: _SearchPanel(),
                  ),
                  const VerticalDivider(width: 1),
                  // Right: Cart
                  Expanded(
                    flex: 4,
                    child: _CartPanel(),
                  ),
                ],
              ),
            ),
            // Bottom Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF673AB7),
              child: Row(
                children: [
                  const Text('Subtotal:', style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 8),
                  BlocBuilder<PosCubit, PosState>(
                    builder: (context, state) => Text(
                      state.total.toStringAsFixed(2),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  _ShortcutButton(Icons.keyboard, 'F12 Checkout', () {
                    context.read<PosCubit>().checkout('cashier_id_placeholder', 'Cashier');
                  }, primary: true),
                  _ShortcutButton(Icons.print, 'Print Receipt', () {}),
                  _ShortcutButton(Icons.cancel, 'Cancel Sale', () => context.read<PosCubit>().clearCart()),
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

class _ShortcutsHint extends StatelessWidget {
  const _ShortcutsHint();

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message: 'Shortcuts: F2 Search · F4 Qty · F12 Checkout',
      child: Text('F2 Search · F4 Qty · F12 Checkout', style: TextStyle(fontSize: 10, color: Colors.white70)),
    );
  }
}

class _SearchPanel extends StatefulWidget {
  @override
  State<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<_SearchPanel> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: (event) {
        if (event.isKeyPressed(LogicalKeyboardKey.keyF)) {
          context.read<PosCubit>().searchProducts(_searchController.text);
        }
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              decoration: const InputDecoration(
                labelText: 'Search by product code or SKU',
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
      ),
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
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('#')),
                              DataColumn(label: Text('SKU')),
                              DataColumn(label: Text('Item Name')),
                              DataColumn(label: Text('Qty')),
                              DataColumn(label: Text('Unit Price')),
                              DataColumn(label: Text('Discount')),
                              DataColumn(label: Text('Total')),
                              DataColumn(label: Text('Action')),
                            ],
                            rows: state.cart.asMap().entries.map((entry) {
                              final i = entry.key;
                              final item = entry.value;
                              return DataRow(cells: [
                                DataCell(Text('${i + 1}')),
                                DataCell(Text(item.variantId.substring(0, 6))),
                                DataCell(Text(item.productName)),
                                DataCell(SizedBox(
                                  width: 70,
                                  child: TextField(
                                    controller: TextEditingController(text: '${item.quantity}'),
                                    keyboardType: TextInputType.number,
                                    onChanged: (val) {
                                      final n = int.tryParse(val);
                                      if (n != null) context.read<PosCubit>().updateQuantity(item.variantId, n);
                                    },
                                  ),
                                )),
                                DataCell(SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: TextEditingController(text: '${item.price}'),
                                    keyboardType: TextInputType.number,
                                    onChanged: (val) {
                                      final n = int.tryParse(val);
                                      if (n != null) context.read<PosCubit>().updateUnitPrice(item.variantId, n);
                                    },
                                  ),
                                )),
                                DataCell(SizedBox(
                                  width: 90,
                                  child: TextField(
                                    controller: TextEditingController(text: '${item.discount}'),
                                    keyboardType: TextInputType.number,
                                    onChanged: (val) {
                                      final n = int.tryParse(val);
                                      if (n != null) context.read<PosCubit>().applyItemDiscount(item.variantId, n);
                                    },
                                  ),
                                )),
                                DataCell(Text((item.total).toStringAsFixed(2))),
                                DataCell(IconButton(icon: const Icon(Icons.delete), onPressed: () => context.read<PosCubit>().removeFromCart(item.variantId))),
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
                  onPressed: state.status == PosStatus.checkoutLoading
                      ? null
                      : () {
                          context.read<PosCubit>().checkout('cashier_id_placeholder', 'Cashier');
                        },
                  child: state.status == PosStatus.checkoutLoading
                      ? const CircularProgressIndicator()
                      : Text('Checkout (${state.total.toStringAsFixed(2)})'),
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
