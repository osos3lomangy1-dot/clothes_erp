import 'package:flutter/material.dart';
import '../../features/products/presentation/screens/product_list_screen.dart';
import '../../features/categories/presentation/screens/category_list_screen.dart';
import '../../features/inventory/presentation/screens/inventory_screen.dart';
import '../../features/inventory/presentation/screens/inventory_logs_screen.dart';
import '../../features/customers/presentation/screens/customer_screen.dart';
import '../../features/returns/presentation/screens/return_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/employees/presentation/screens/employee_list_screen.dart';
import '../../features/pos/presentation/screens/pos_screen.dart';

class MainLayout extends StatefulWidget {
  final Widget child;
  final String currentRoute;

  const MainLayout({super.key, required this.child, required this.currentRoute});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isCollapsed = false;
  Widget _currentScreen = const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: _isCollapsed ? 80 : 250,
            child: Container(
              color: const Color(0xFF673AB7),
              child: Column(
                children: [
                  IconButton(
                    icon: Icon(_isCollapsed ? Icons.chevron_right : Icons.chevron_left, color: Colors.white),
                    onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _navItem(Icons.dashboard, 'Dashboard', const _DashboardContent()),
                          _navItem(Icons.point_of_sale, 'POS', null, isPos: true),
                          _navItem(Icons.inventory_2, 'Products', const ProductListScreen()),
                          _navItem(Icons.category, 'Categories', const CategoryListScreen()),
                          _navItem(Icons.warehouse, 'Inventory', const InventoryScreen()),
                          _navItem(Icons.history, 'Inv. Logs', const InventoryLogsScreen()),
                          _navItem(Icons.people, 'Customers', const CustomerScreen()),
                          _navItem(Icons.assignment_return, 'Returns', const ReturnScreen()),
                          _navItem(Icons.bar_chart, 'Reports', const ReportsScreen()),
                          _navItem(Icons.badge, 'Employees', const EmployeeListScreen()),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: Container(color: Colors.white, child: widget.child)),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String title, Widget? screen, {bool isPos = false}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: _isCollapsed ? null : Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () {
        if (isPos) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen()));
        } else if (screen != null) {
          setState(() => _currentScreen = screen);
        }
      },
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Dashboard'));
  }
}
