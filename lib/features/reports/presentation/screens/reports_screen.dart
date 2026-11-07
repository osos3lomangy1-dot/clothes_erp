import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../cubits/reports_cubit.dart';
import '../cubits/reports_state.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<ReportsCubit>()
        ..loadReport(_dateRange!.start, _dateRange!.end),
      child: Scaffold(
        appBar: AppBar(title: const Text('Sales Reports')),
        body: Builder(
          builder: (context) {
            return Padding(
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            initialDateRange: _dateRange,
                          );
                          if (picked != null) {
                            setState(() => _dateRange = picked);
                            if (context.mounted) {
                              context.read<ReportsCubit>().loadReport(picked.start, picked.end);
                            }
                          }
                        },
                        icon: const Icon(Icons.date_range),
                        label: const Text('Pick Date Range'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: BlocBuilder<ReportsCubit, ReportsState>(
                      builder: (context, state) {
                        if (state is ReportsLoading) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (state is ReportsError) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(state.message, style: const TextStyle(color: Colors.red)),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: () => context.read<ReportsCubit>().loadReport(_dateRange!.start, _dateRange!.end),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          );
                        }
                        if (state is ReportsLoaded) {
                          final report = state.report;
                          return ListView(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _ReportCard(
                                      title: 'Revenue',
                                      value: '\$${Money(report.totalRevenue).toDisplay()}',
                                      icon: Icons.attach_money,
                                      color: Colors.green,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _ReportCard(
                                      title: 'Total Cost',
                                      value: '\$${Money(report.totalCost).toDisplay()}',
                                      icon: Icons.shopping_bag_outlined,
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _ReportCard(
                                      title: 'Gross Profit',
                                      value: '\$${Money(report.totalProfit).toDisplay()}',
                                      icon: Icons.trending_up,
                                      color: Colors.purple,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _ReportCard(
                                      title: 'Transactions',
                                      value: '${report.totalTransactions}',
                                      icon: Icons.receipt_long,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Payment Method Breakdown',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              const SizedBox(height: 8),
                              if (report.paymentMethodBreakdown.isEmpty)
                                const Card(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text('No sales found for the selected period.'),
                                  ),
                                )
                              else
                                ...report.paymentMethodBreakdown.entries.map(
                                  (e) => Card(
                                    child: ListTile(
                                      leading: Icon(
                                        e.key.toLowerCase() == 'cash' ? Icons.money : Icons.credit_card,
                                        color: Colors.deepPurple,
                                      ),
                                      title: Text(
                                        e.key.toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      trailing: Text(
                                        '\$${Money(e.value).toDisplay()}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ReportCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
