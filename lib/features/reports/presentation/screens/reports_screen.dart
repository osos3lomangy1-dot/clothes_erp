import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTimeRange? _dateRange;
  bool _loading = false;
  double _totalSales = 0;
  int _totalTransactions = 0;
  Map<String, double> _paymentBreakdown = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (_dateRange == null) return;
    setState(() => _loading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('sales')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_dateRange!.start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(_dateRange!.end))
          .get();

      double total = 0;
      int count = 0;
      final Map<String, double> breakdown = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final saleTotal = (data['total'] as num?)?.toDouble() ?? 0.0;
        final paymentMethod = data['paymentMethod'] as String? ?? 'cash';
        total += saleTotal;
        count++;
        breakdown[paymentMethod] = (breakdown[paymentMethod] ?? 0) + saleTotal;
      }

      setState(() {
        _totalSales = total;
        _totalTransactions = count;
        _paymentBreakdown = breakdown;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _loadReports();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dateRange != null
                        ? '${_dateRange!.start.toLocal().toString().split(' ')[0]} - ${_dateRange!.end.toLocal().toString().split(' ')[0]}'
                        : 'Select date range',
                  ),
                ),
                ElevatedButton(
                  onPressed: _pickDateRange,
                  child: const Text('Pick Date Range'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              Card(
                child: ListTile(
                  title: const Text('Total Sales'),
                  trailing: Text('\$${_totalSales.toStringAsFixed(2)}'),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text('Total Transactions'),
                  trailing: Text('$_totalTransactions'),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Payment Method Breakdown',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ..._paymentBreakdown.entries.map(
                (e) => Card(
                  child: ListTile(
                    title: Text(e.key),
                    trailing: Text('\$${e.value.toStringAsFixed(2)}'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
