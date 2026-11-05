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
      create: (context) => getIt<PosCubit>()..init(),
      child: const _PosView(),
    );
  }
}

class _PosView extends StatelessWidget {
  const _PosView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left: Cart (440px)
          SizedBox(
            width: 440,
            child: _CartPanel(),
          ),
          const VerticalDivider(width: 1),
          // Right: Products
          Expanded(child: _ProductPanel()),
        ],
      ),
    );
  }
}

class _ProductPanel extends StatefulWidget {
  @override
  State<_ProductPanel> createState() => _ProductPanelState();
}

class _ProductPanelState extends State<_ProductPanel> {
  final _searchCtrl = TextEditingController();
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Search by product code or SKU',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (val) => context.read<PosCubit>().searchProducts(val),
          ),
        ),
        // Category chips
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: ['All', 'Shirts', 'Pants', 'Jackets'].map((c) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(c),
                  selected: _selectedCategory == c,
                  onSelected: (_) => setState(() => _selectedCategory = c),
                ),
              );
            }).toList(),
          ),
        ),
        // Product grid
        Expanded(
          child: BlocBuilder<PosCubit, PosState>(
            builder: (context, state) {
              if (state is PosLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is PosLoaded && state.filteredVariants.isEmpty) {
                return const Center(child: Text('No products found. Add products in the Products screen first.'));
              }
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: (state is PosLoaded) ? state.filteredVariants.length : 0,
                itemBuilder: (context, index) {
                  final variant = (state as PosLoaded).filteredVariants[index];
                  return _ProductCard(variant: variant);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  final VariantEntity variant;
  const _ProductCard({required this.variant});

  @override
  Widget build(BuildContext context) {
    final isOut = variant.quantity == 0;
    final isLow = variant.quantity > 0 && variant.quantity <= variant.minStock;
    return Card(
      elevation: 2,
      color: isOut ? Colors.grey.shade200 : Colors.white,
      child: InkWell(
        onTap: isOut ? null : () => _showVariantModal(context, variant),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.purple.shade100,
                    child: Text(variant.productCode.substring(0, 1).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                  ),
                ),
              ),
              Text(variant.productCode, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('SKU: ${variant.sku}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('\$${variant.salePrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 13)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isOut ? Colors.red.shade100 : (isLow ? Colors.orange.shade100 : Colors.green.shade100),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isOut ? 'Out' : (isLow ? 'Low' : 'Available'),
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isOut ? Colors.red : (isLow ? Colors.orange : Colors.green)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVariantModal(BuildContext context, VariantEntity variant) {
    showDialog(
      context: context,
      builder: (_) => _VariantModal(variant: variant),
    );
  }
}

class _VariantModal extends StatefulWidget {
  final VariantEntity variant;
  const _VariantModal({required this.variant});

  @override
  State<_VariantModal> createState() => _VariantModalState();
}

class _VariantModalState extends State<_VariantModal> {
  int _qty = 1;

  @override
  Widget build(BuildContext context) {
    final v = widget.variant;
    return AlertDialog(
      title: Text(v.productCode),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SKU: ${v.sku}'),
          const SizedBox(height: 8),
          Text('Color: ${v.color}'),
          Text('Size: ${v.size}'),
          Text('Stock: ${v.quantity}'),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(onPressed: () { if (_qty > 1) setState(() => _qty--); }, icon: const Icon(Icons.remove)),
              Text('$_qty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () { if (_qty < v.quantity) setState(() => _qty++); }, icon: const Icon(Icons.add)),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            for (int i = 0; i < _qty; i++) {
              context.read<PosCubit>().addToCart(v);
            }
            Navigator.pop(context);
          },
          child: const Text('Add to Cart'),
        ),
      ],
    );
  }
}

class _CartPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        if (state is! PosLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Current Cart (${state.cart.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Row(
                    children: [
                      TextButton(onPressed: () {}, child: const Text('Hold [F9]')),
                      TextButton(onPressed: () {}, child: const Text('Held Sales')),
                      TextButton(onPressed: () => context.read<PosCubit>().clearCart(), child: const Text('Clear [Esc]')),
                    ],
                  ),
                ],
              ),
              // Customer pill
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Guest', style: TextStyle(fontWeight: FontWeight.bold))),
                    TextButton(onPressed: () {}, child: const Text('Add Customer')),
                  ],
                ),
              ),
              // Cart items
              Expanded(
                child: state.cart.isEmpty
                    ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey), SizedBox(height: 8), Text('Cart is empty', style: TextStyle(color: Colors.grey))]))
                    : ListView.builder(
                        itemCount: state.cart.length,
                        itemBuilder: (context, index) {
                          final item = state.cart[index];
                          return _CartItemTile(item: item);
                        },
                      ),
              ),
              const Divider(),
              // Footer calculations
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal', style: TextStyle(fontSize: 14)),
                    Text(state.subtotal.toStringAsFixed(2), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Discount', style: TextStyle(fontSize: 14)),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                        onChanged: (val) {
                          final n = int.tryParse(val) ?? 0;
                          context.read<PosCubit>().applyDiscount(n.toDouble());
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Grand Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(state.total.toStringAsFixed(2), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Payment method
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                      child: const Text('Cash'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {},
                      child: const Text('Card'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Amount received
              Row(
                children: [
                  const Text('Received:'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('Change:'),
                  const SizedBox(width: 8),
                  Text(state.total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: state.cart.isEmpty || state.isProcessing
                      ? null
                      : () => context.read<PosCubit>().checkout(paymentMethod: 'cash'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                  child: state.isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Checkout [F12]', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
  final dynamic item;
  const _CartItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${item.color} - ${item.size}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(icon: const Icon(Icons.remove, size: 16), onPressed: () => context.read<PosCubit>().decreaseQty(item.variantId)),
                Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.add, size: 16), onPressed: () => context.read<PosCubit>().increaseQty(item.variantId)),
              ],
            ),
            IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () => context.read<PosCubit>().removeFromCart(item.variantId)),
          ],
        ),
      ),
    );
  }
}



