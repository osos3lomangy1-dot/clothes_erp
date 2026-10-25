import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../pos/presentation/screens/pos_screen.dart';
import '../../../products/presentation/screens/product_list_screen.dart';
import '../../../inventory/presentation/screens/inventory_screen.dart';

class CashierDashboardScreen extends StatelessWidget {
  const CashierDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashier Dashboard'),
        actions: [
          IconButton(
            onPressed: () => context.read<AuthCubit>().logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Welcome, Cashier!'),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              padding: const EdgeInsets.symmetric(horizontal: 32),
              children: [
                _NavCard(
                  icon: Icons.point_of_sale,
                  title: 'Open POS',
                  color: Colors.deepPurple,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const PosScreen()),
                  ),
                ),
                _NavCard(
                  icon: Icons.inventory_2,
                  title: 'Products',
                  color: Colors.blue,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const ProductListScreen()),
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
              ],
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
