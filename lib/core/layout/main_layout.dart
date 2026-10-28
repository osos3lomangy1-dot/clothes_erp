import 'package:flutter/material.dart';

class MainLayout extends StatefulWidget {
  final Widget child;
  final String currentRoute;

  const MainLayout({super.key, required this.child, required this.currentRoute});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isCollapsed = false;

  static const _items = [
    ('/dashboard', Icons.dashboard, 'Dashboard'),
    ('/pos', Icons.point_of_sale, 'POS'),
    ('/products', Icons.inventory_2, 'Products'),
    ('/categories', Icons.category, 'Categories'),
    ('/inventory', Icons.warehouse, 'Inventory'),
    ('/customers', Icons.people, 'Customers'),
    ('/returns', Icons.assignment_return, 'Returns'),
    ('/reports', Icons.bar_chart, 'Reports'),
    ('/employees', Icons.badge, 'Employees'),
  ];

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
                ..._items.map((item) {
                  final active = widget.currentRoute == item.$1;
                  return ListTile(
                    leading: Icon(item.$2, color: Colors.white),
                    title: _isCollapsed ? null : Text(item.$3, style: const TextStyle(color: Colors.white)),
                    selected: active,
                    selectedTileColor: Colors.white24,
                    onTap: () => Navigator.pushReplacementNamed(context, item.$1),
                  );
                }),
              ],
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
