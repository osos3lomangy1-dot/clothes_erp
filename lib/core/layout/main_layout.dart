import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../constants/app_colors.dart';
import '../di/injection.dart';
import '../services/crash_logger_service.dart';
import '../services/rest_sync_service.dart';
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
  bool _isSyncing = false;
  late Widget _currentScreen;
  StreamSubscription<bool>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _currentScreen = widget.child;

    final syncService = getIt<RestSyncService>();
    // Start background auto-sync timer (every 5 minutes + immediate initial check)
    syncService.startAutoSync(interval: const Duration(minutes: 5));

    _syncSubscription = syncService.isSyncingStream.listen((syncing) {
      if (mounted && _isSyncing != syncing) {
        setState(() => _isSyncing = syncing);
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    getIt<RestSyncService>().stopAutoSync();
    super.dispose();
  }

  Future<void> _handleSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      final syncService = getIt<RestSyncService>();
      final result = await syncService.syncPendingData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.total == 0
                ? 'لا توجد بيانات معلقة للمزامنة السحابية'
                : 'تمت مزامنة ${result.synced} من أصل ${result.total} عنصر بنجاح',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor:
              result.isSuccess ? Colors.green.shade700 : AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشلت المزامنة السحابية: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
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
                  const Divider(color: Colors.white24, height: 1),
                  _buildSyncSection(),
                ],
              ),
            ),
          ),
          Expanded(child: Container(color: Colors.white, child: _currentScreen)),
        ],
      ),
    );
  }

  Widget _buildSyncSection() {
    final syncService = getIt<RestSyncService>();
    return StreamBuilder<int>(
      stream: syncService.watchPendingCount(),
      initialData: 0,
      builder: (context, snapshot) {
        final pendingCount = snapshot.data ?? 0;
        final hasPending = pendingCount > 0;

        if (_isCollapsed) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: IconButton(
              tooltip: _isSyncing
                  ? 'جارِ المزامنة السحابية...'
                  : hasPending
                      ? 'مزامنة السحابة ($pendingCount معلقة)'
                      : 'السحابة متزامنة',
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Badge(
                      isLabelVisible: hasPending,
                      label: Text('$pendingCount'),
                      backgroundColor: Colors.amber.shade700,
                      child: Icon(
                        hasPending
                            ? Icons.cloud_upload_rounded
                            : Icons.cloud_done_rounded,
                        color: Colors.white,
                      ),
                    ),
              onPressed: _isSyncing ? null : _handleSync,
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.all(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _isSyncing ? null : _handleSync,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasPending
                      ? Colors.amber.shade300.withValues(alpha: 0.6)
                      : Colors.white24,
                ),
              ),
              child: Row(
                children: [
                  if (_isSyncing)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  else
                    Icon(
                      hasPending
                          ? Icons.cloud_upload_rounded
                          : Icons.cloud_done_rounded,
                      color: hasPending
                          ? Colors.amber.shade300
                          : Colors.greenAccent.shade100,
                      size: 20,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isSyncing
                          ? 'جارِ المزامنة...'
                          : hasPending
                              ? 'مزامنة السحابة'
                              : 'السحابة متزامنة',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (hasPending && !_isSyncing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
