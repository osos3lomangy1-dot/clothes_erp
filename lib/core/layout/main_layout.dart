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
import '../../features/dashboard/presentation/screens/admin_dashboard_screen.dart';

class MainLayout extends StatefulWidget {
  final Widget child;
  final String currentRoute;

  const MainLayout({super.key, required this.child, required this.currentRoute});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isCollapsed ? 72 : 220,
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
                        _navItem(context, Icons.dashboard, 'Dashboard', const AdminDashboardScreen()),
                        _navItem(context, Icons.point_of_sale, 'POS', const PosScreen()),
                        _navItem(context, Icons.inventory_2, 'Products', const ProductListScreen()),
                        _navItem(context, Icons.category, 'Categories', const CategoryListScreen()),
                        _navItem(context, Icons.warehouse, 'Inventory', const InventoryScreen()),
                        _navItem(context, Icons.history, 'Inv. Logs', const InventoryLogsScreen()),
                        _navItem(context, Icons.people, 'Customers', const CustomerScreen()),
                        _navItem(context, Icons.assignment_return, 'Returns', const ReturnScreen()),
                        _navItem(context, Icons.bar_chart, 'Reports', const ReportsScreen()),
                        _navItem(context, Icons.badge, 'Employees', const EmployeeListScreen()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String title, Widget screen) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: _isCollapsed ? null : Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => screen)),
    );
  }
}

