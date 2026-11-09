import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../constants/app_colors.dart';
import '../services/crash_logger_service.dart';
import '../../features/auth/presentation/cubits/auth_cubit.dart';
import '../../features/auth/presentation/cubits/auth_state.dart';
import '../../features/products/presentation/screens/product_list_screen.dart';
import '../../features/inventory/presentation/screens/inventory_screen.dart';
import '../../features/inventory/presentation/screens/inventory_logs_screen.dart';
import '../../features/customers/presentation/screens/customer_screen.dart';
import '../../features/returns/presentation/screens/return_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/employees/presentation/screens/employee_list_screen.dart';
import '../../features/expenses/presentation/screens/expenses_screen.dart';
import '../../features/partners/presentation/screens/partners_screen.dart';
import '../../features/pos/presentation/screens/pos_screen.dart';
import '../../features/crash_logs/presentation/screens/crash_logs_screen.dart';

class MainLayout extends StatefulWidget {
  final Widget child;
  final String currentRoute;

  const MainLayout({super.key, required this.child, required this.currentRoute});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _isCollapsed = false;
  late Widget _currentScreen;

  @override
  void initState() {
    super.initState();
    _currentScreen = widget.child;
  }

  @override
  void didUpdateWidget(covariant MainLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {
      _currentScreen = widget.child;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: _isCollapsed ? 80 : 250,
            child: Container(
              color: AppColors.primary,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      mainAxisAlignment: _isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
                      children: [
                        if (!_isCollapsed) ...[
                          const Row(
                            children: [
                              Icon(Icons.storefront_rounded, color: Colors.white, size: 24),
                              SizedBox(width: 10),
                              Text(
                                'نظام الملابس',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ],
                        IconButton(
                          icon: Icon(_isCollapsed ? Icons.menu_rounded : Icons.menu_open_rounded, color: Colors.white),
                          tooltip: _isCollapsed ? 'توسيع القائمة' : 'طي القائمة',
                          onPressed: () => setState(() => _isCollapsed = !_isCollapsed),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          _navItem(Icons.dashboard_rounded, 'لوحة التحكم', widget.child),
                          _navItem(Icons.point_of_sale_rounded, 'نقطة البيع (الكاشير)', null, isPos: true),
                          _navItem(Icons.inventory_2_rounded, 'المنتجات والتصنيفات', const ProductListScreen()),
                          _navItem(Icons.warehouse_rounded, 'إدارة المخزون', const InventoryScreen()),
                          _navItem(Icons.history_rounded, 'حركات المخزن', const InventoryLogsScreen()),
                          _navItem(Icons.people_alt_rounded, 'سجل العملاء', const CustomerScreen()),
                          _navItem(Icons.payments_outlined, 'إدارة المصروفات', const ExpensesScreen()),
                          _navItem(Icons.assignment_return_rounded, 'إدارة المرتجعات', const ReturnScreen()),
                          _navItem(Icons.bar_chart_rounded, 'تقارير المبيعات', const ReportsScreen()),
                          _navItem(Icons.handshake_rounded, 'الشركاء وتوزيع الأرباح', const PartnersScreen()),
                          _navItem(Icons.badge_rounded, 'فريق العمل والموظفون', const EmployeeListScreen()),
                          BlocBuilder<AuthCubit, AuthState>(
                            builder: (context, authState) {
                              final isAdmin = authState is! AuthAuthenticated || authState.user.role == 'admin';
                              if (!isAdmin) return const SizedBox.shrink();
                              return _navItem(
                                Icons.bug_report_rounded,
                                'سجلات الأعطال',
                                const CrashLogsScreen(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: Container(color: Colors.white, child: _currentScreen)),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String title, Widget? screen, {bool isPos = false, VoidCallback? onTapOverride}) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: _isCollapsed
          ? null
          : Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
      onTap: () {
        CrashLoggerService.addBreadcrumb('اختيار من القائمة: $title');
        CrashLoggerService.setContext('شاشة: $title');
        if (onTapOverride != null) {
          onTapOverride();
        } else if (isPos) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const PosScreen()));
        } else if (screen != null) {
          setState(() => _currentScreen = screen);
        }
      },
    );
  }
}
