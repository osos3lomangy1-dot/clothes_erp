import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key});

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _variants = [];
  Map<String, dynamic>? _selectedVariant;
  final _qtyController = TextEditingController(text: '1');
  final _refundController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _searchVariants() async {
    setState(() {
      _loading = true;
      _error = null;
      _variants = [];
      _selectedVariant = null;
    });
    try {
      final query = _searchController.text.trim().toLowerCase();
      final snapshot = await FirebaseFirestore.instance
          .collection('product_variants')
          .get();
      final results = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((v) =>
              (v['productCode'] as String? ?? '').toLowerCase().contains(query) ||
              (v['color'] as String? ?? '').toLowerCase().contains(query) ||
              (v['size'] as String? ?? '').toLowerCase().contains(query))
          .toList();
      setState(() {
        _variants = results;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _confirmReturn() async {
    if (_selectedVariant == null) return;
    final qty = int.tryParse(_qtyController.text) ?? 0;
    if (qty <= 0) return;
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final variantRef = FirebaseFirestore.instance
            .collection('product_variants')
            .doc(_selectedVariant!['id']);
        final variantDoc = await transaction.get(variantRef);
        if (!variantDoc.exists) throw Exception('Variant not found');
        final currentQty = (variantDoc.data()?['quantity'] as num?)?.toInt() ?? 0;
        transaction.update(variantRef, {'quantity': currentQty + qty});

        final logRef = FirebaseFirestore.instance.collection('inventory_logs').doc();
        transaction.set(logRef, {
          'productId': _selectedVariant!['productId'],
          'variantId': _selectedVariant!['id'],
          'type': 'in',
          'quantity': qty,
          'date': Timestamp.now(),
          'userId': 'cashier',
          'note': 'Return',
        });
      });
      setState(() {
        _loading = false;
        _selectedVariant = null;
        _variants = [];
        _searchController.clear();
        _qtyController.text = '1';
        _refundController.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Return processed successfully')),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _qtyController.dispose();
    _refundController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Returns')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by product name or SKU',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _searchVariants(),
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _searchVariants, child: const Text('Search')),
            if (_loading) const CircularProgressIndicator(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_variants.isNotEmpty) ...[
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _variants.length,
                  itemBuilder: (context, index) {
                    final v = _variants[index];
                    final isSelected = _selectedVariant?['id'] == v['id'];
                    return Card(
                      color: isSelected ? theme.colorScheme.primaryContainer : null,
                      child: ListTile(
                        title: Text('${v['productCode']} - ${v['color']} / ${v['size']}'),
                        subtitle: Text('In stock: ${v['quantity']}'),
                        trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
                        onTap: () => setState(() => _selectedVariant = v),
                      ),
                    );
                  },
                ),
              ),
              if (_selectedVariant != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Quantity to return'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _refundController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Refund amount'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _confirmReturn,
                    child: const Text('Confirm Return'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
