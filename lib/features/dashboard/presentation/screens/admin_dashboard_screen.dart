import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../cubits/dashboard_cubit.dart';
import '../cubits/dashboard_state.dart';
import '../../../products/presentation/cubits/product_cubit.dart';
import '../../../products/presentation/screens/product_list_screen.dart';
import '../../../categories/presentation/screens/category_list_screen.dart';
import '../../../inventory/presentation/screens/inventory_screen.dart';
import '../../../inventory/presentation/screens/inventory_logs_screen.dart';
import '../../../customers/presentation/screens/customer_screen.dart';
import '../../../returns/presentation/screens/return_screen.dart';
import '../../../reports/presentation/screens/reports_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<DashboardCubit>(),
      child: const _AdminDashboardView(),
    );
  }
}

class _AdminDashboardView extends StatelessWidget {
  const _AdminDashboardView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: () => context.read<AuthCubit>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (context, state) {
          if (state.status == DashboardStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status == DashboardStatus.failure) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(state.errorMessage ?? 'Something went wrong'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<DashboardCubit>().loadStats(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final stats = state.stats;
          return RefreshIndicator(
            onRefresh: () => context.read<DashboardCubit>().loadStats(),
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        title: "Today's Sales",
                        value: '\$${stats?.todaySales.toStringAsFixed(2) ?? '0.00'}',
                        icon: Icons.attach_money,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Transactions',
                        value: '${stats?.todayTransactions ?? 0}',
                        icon: Icons.receipt_long,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Low Stock',
                        value: '${stats?.lowStockCount ?? 0}',
                        icon: Icons.warning,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Quick Actions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    _NavCard(
                      icon: Icons.inventory_2,
                      title: 'Products',
                      color: Colors.blue,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => BlocProvider(
                          create: (_) => getIt<ProductCubit>()..getProducts(),
                          child: const ProductListScreen(),
                        )),
                      ),
                    ),
                    _NavCard(
                      icon: Icons.category,
                      title: 'Categories',
                      color: Colors.teal,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const CategoryListScreen()),
                      ),
                    ),
                    _NavCard(
                      icon: Icons.warehouse,
                      title: 'Inventory',
                      color: Colors.brown,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const InventoryScreen()),
                      ),
                    ),
                    _NavCard(
                      icon: Icons.history,
                      title: 'Inv. Logs',
                      color: Colors.grey,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const InventoryLogsScreen()),
                      ),
                    ),
                    _NavCard(
                      icon: Icons.people_outline,
                      title: 'Customers',
                      color: Colors.pink,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const CustomerScreen()),
                      ),
                    ),
                    _NavCard(
                      icon: Icons.assignment_return,
                      title: 'Returns',
                      color: Colors.deepOrange,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const ReturnScreen()),
                      ),
                    ),
                    _NavCard(
                      icon: Icons.bar_chart,
                      title: 'Reports',
                      color: Colors.indigo,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const ReportsScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Low Stock Items',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (stats == null || stats.lowStockVariants.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('No low stock items. 🎉'),
                  )
                else
                  ...stats.lowStockVariants.map((variant) => Card(
                        child: ListTile(
                          leading: Icon(
                            Icons.inventory_2,
                            color: variant.quantity == 0 ? Colors.red : Colors.orange,
                          ),
                          title: Text('${variant.productCode} - ${variant.color} - ${variant.size}'),
                          subtitle: Text('Stock: ${variant.quantity} (min: ${variant.minStock})'),
                          trailing: Text(
                            variant.quantity == 0 ? 'OUT OF STOCK' : 'Low',
                            style: TextStyle(
                              color: variant.quantity == 0 ? Colors.red : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
