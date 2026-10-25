import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key});

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final _saleIdController = TextEditingController();
  Map<String, dynamic>? _saleData;
  List<dynamic> _items = [];
  final Set<int> _selectedItems = {};
  bool _loading = false;
  String? _error;

  Future<void> _fetchSale() async {
    setState(() {
      _loading = true;
      _error = null;
      _saleData = null;
      _items = [];
      _selectedItems.clear();
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sales')
          .doc(_saleIdController.text.trim())
          .get();
      if (!doc.exists) {
        setState(() {
          _error = 'Sale not found';
          _loading = false;
        });
        return;
      }
      final data = doc.data()!;
      setState(() {
        _saleData = data;
        _items = (data['items'] as List?) ?? [];
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
    if (_selectedItems.isEmpty) return;
    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final saleRef = FirebaseFirestore.instance
            .collection('sales')
            .doc(_saleIdController.text.trim());
        final saleDoc = await transaction.get(saleRef);
        if (!saleDoc.exists) throw Exception('Sale not found');

        for (final idx in _selectedItems) {
          final item = _items[idx] as Map<String, dynamic>;
          final variantId = item['variantId'] as String?;
          final productId = item['productId'] as String?;
          final qty = (item['quantity'] as num?)?.toInt() ?? 0;
          if (variantId != null && productId != null) {
            final variantRef = FirebaseFirestore.instance
                .collection('product_variants')
                .doc(variantId);
            final variantDoc = await transaction.get(variantRef);
            if (variantDoc.exists) {
              final currentQty = (variantDoc.data()?['quantity'] as num?)?.toInt() ?? 0;
              transaction.update(variantRef, {'quantity': currentQty + qty});
            }
            // Log inventory in
            final logRef = FirebaseFirestore.instance.collection('inventory_logs').doc();
            transaction.set(logRef, {
              'productId': productId,
              'variantId': variantId,
              'type': 'in',
              'quantity': qty,
              'date': Timestamp.now(),
              'userId': 'system',
            });
          }
        }

        transaction.update(saleRef, {'status': 'partially_refunded'});
      });
      setState(() {
        _loading = false;
        _saleData = null;
        _items = [];
        _selectedItems.clear();
        _saleIdController.clear();
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
    _saleIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Returns')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _saleIdController,
              decoration: const InputDecoration(
                labelText: 'Sale ID',
                suffixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _fetchSale, child: const Text('Fetch Sale')),
            if (_loading) const CircularProgressIndicator(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index] as Map<String, dynamic>;
                    return CheckboxListTile(
                      value: _selectedItems.contains(index),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedItems.add(index);
                          } else {
                            _selectedItems.remove(index);
                          }
                        });
                      },
                      title: Text(item['productName'] ?? item['productCode'] ?? 'Item'),
                      subtitle: Text('Qty: ${item['quantity']}'),
                    );
                  },
                ),
              ),
              ElevatedButton(
                onPressed: _confirmReturn,
                child: const Text('Confirm Return'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
