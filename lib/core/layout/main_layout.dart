import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../constants/app_colors.dart';
import '../database/app_database.dart';
import '../di/injection.dart';
import '../features/feature_gate.dart';
import '../services/crash_logger_service.dart';
import '../services/rest_sync_service.dart';
import '../theme/app_branding.dart';
import '../../features/auth/presentation/cubits/auth_cubit.dart';
import '../../features/auth/presentation/cubits/auth_state.dart';
import '../../features/crash_logs/presentation/screens/crash_logs_screen.dart';
import '../../features/customers/presentation/screens/customer_screen.dart';
import '../../features/dashboard/presentation/cubits/dashboard_cubit.dart';
import '../../features/delivery/presentation/screens/delivery_orders_screen.dart';
import '../../features/employees/presentation/screens/employee_list_screen.dart';
import '../../features/expenses/presentation/screens/expenses_screen.dart';
import '../../features/installments/presentation/screens/installments_list_screen.dart';
import '../../features/inventory/presentation/screens/blind_receive_screen.dart';
import '../../features/inventory/presentation/screens/inventory_logs_screen.dart';
import '../../features/inventory/presentation/screens/inventory_screen.dart';
import '../../features/inventory/presentation/screens/stocktake_screen.dart';
import '../../features/invoices/presentation/screens/invoices_screen.dart';
import '../../features/partners/presentation/screens/partners_screen.dart';
import '../../features/pos/presentation/screens/pos_screen.dart';
import '../../features/barcode_printing/presentation/screens/barcode_customizer_screen.dart';
import '../../features/products/presentation/screens/product_list_screen.dart';
import '../../features/promotions/presentation/screens/promotions_screen.dart';
import '../../features/purchases/presentation/screens/purchases_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/returns/presentation/screens/return_screen.dart';
import '../../features/settings/presentation/screens/system_settings_screen.dart';
import '../../features/shifts/presentation/screens/shift_screen.dart';

class MainLayout extends StatefulWidget {
  final Widget child;
  final String currentRoute;

  const MainLayout({super.key, required this.child, required this.currentRoute});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();
  final Set<String> _collapsedSections = {};
  bool? _userCollapsedOverride;
  bool _isSyncing = false;
  bool _cloudSyncEnabled = false;
  String _activeTitle = 'لوحة التحكم';
  late Widget _currentScreen;
  StreamSubscription<bool>? _syncSubscription;
  StreamSubscription<String?>? _cloudSyncSub;
  StreamSubscription<List<CustomerInstallment>>? _activeInstallmentsSub;
  bool _hasActiveInstallments = false;

  @override
  void initState() {
    super.initState();
    _currentScreen = widget.child;

    final syncService = getIt<RestSyncService>();
    final featureGate = getIt<FeatureGate>();

    if (getIt.isRegistered<AppDatabase>()) {
      final db = getIt<AppDatabase>();
      final query = (db.select(db.customerInstallments)
        ..where((t) => t.deletedAt.isNull() & t.status.isIn(const ['active', 'overdue'])));
      _activeInstallmentsSub = query.watch().listen((contracts) {
        final hasActive = contracts.isNotEmpty;
        if (mounted && _hasActiveInstallments != hasActive) {
          setState(() => _hasActiveInstallments = hasActive);
        }
      });
    }

    _cloudSyncSub = featureGate.watchMeta('sync.cloud_enabled').listen((val) {
      final enabled = val == '1' || val == 'true';
      if (enabled) {
        syncService.startAutoSync(interval: const Duration(minutes: 5));
      } else {
        syncService.stopAutoSync();
      }
      if (mounted && _cloudSyncEnabled != enabled) {
        setState(() => _cloudSyncEnabled = enabled);
      }
    });

    _syncSubscription = syncService.isSyncingStream.listen((syncing) {
      if (mounted && _isSyncing != syncing) {
        setState(() => _isSyncing = syncing);
      }
    });
  }

  @override
  void dispose() {
    _activeInstallmentsSub?.cancel();
    _cloudSyncSub?.cancel();
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
    if (oldWidget.currentRoute != widget.currentRoute) {
      _currentScreen = widget.child;
      _contentNavKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => widget.child),
        (route) => false,
      );
    }
  }

  bool _isAdmin(AuthState authState) {
    if (authState is! AuthAuthenticated) return true;
    return authState.user.role != 'cashier';
  }

  bool _featureEnabled(Map<String, bool> features, String key) {
    final def = FeatureKeys.byKey[key];
    if (def == null) return false;
    if (def.coreAlwaysEnabled) return true;
    return features[key] ?? def.defaultEnabled;
  }

  bool get _isCollapsed {
    if (_userCollapsedOverride != null) return _userCollapsedOverride!;
    final width = MediaQuery.maybeSizeOf(context)?.width ?? 1280;
    // Auto-collapse sidebar on narrow screens (< 720) to prevent horizontal cramping
    return width < 720;
  }

  @override
  Widget build(BuildContext context) {
    final featureGate = getIt<FeatureGate>();
    final collapsed = _isCollapsed;
    return ValueListenableBuilder<AppBrandingConfig>(
      valueListenable: AppBranding.notifier,
      builder: (context, branding, _) {
        return Scaffold(
          body: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: collapsed ? 76 : 232,
                child: Material(
                  color: branding.primaryColor,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        child: Row(
                          mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
                          children: [
                            if (!collapsed) ...[
                              Expanded(
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: Image.asset(
                                        'assets/icons/bay3ah-128.png',
                                        width: 28,
                                        height: 28,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.storefront_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        branding.appName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                        IconButton(
                          icon: Icon(collapsed ? Icons.menu_rounded : Icons.menu_open_rounded, color: Colors.white),
                          tooltip: collapsed ? 'توسيع القائمة' : 'طي القائمة',
                          onPressed: () => setState(() => _userCollapsedOverride = !collapsed),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 1),
                  Expanded(
                    child: StreamBuilder<Map<String, bool>>(
                      stream: featureGate.watchFeatures(),
                      initialData: const <String, bool>{},
                      builder: (context, snapshot) {
                        final features = snapshot.data ?? const <String, bool>{};
                        return BlocBuilder<AuthCubit, AuthState>(
                          builder: (context, authState) {
                            final isAdmin = _isAdmin(authState);
                            return SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Direct Top Actions
                                  _navItem(Icons.dashboard_rounded, 'لوحة التحكم', widget.child),
                                  if (_featureEnabled(features, FeatureKeys.pos))
                                    _navItem(Icons.point_of_sale_rounded, 'نقطة البيع (الكاشير)', null, isPos: true),

                                  // Sales & Orders Group
                                  _navGroup(
                                    title: 'المبيعات والطلبات',
                                    icon: Icons.receipt_long_rounded,
                                    children: [
                                      _navItem(Icons.receipt_long_rounded, 'سجل فواتير المبيعات', const InvoicesScreen(), isSubItem: true),
                                      _navItem(Icons.assignment_return_rounded, 'إدارة المرتجعات', const ReturnScreen(), isSubItem: true),
                                      _navItem(Icons.moped_rounded, 'إدارة الدليفري والطيارين', const DeliveryOrdersScreen(), isSubItem: true),
                                      if (_featureEnabled(features, FeatureKeys.shifts))
                                        _navItem(Icons.lock_clock_rounded, 'الورديات وتصفية الدرج', const ShiftScreen(), isSubItem: true),
                                    ],
                                  ),

                                  // Inventory Group
                                  _navGroup(
                                    title: 'المخزون والمستودع',
                                    icon: Icons.warehouse_rounded,
                                    children: [
                                      if (_featureEnabled(features, FeatureKeys.inventory)) ...[
                                        _navItem(Icons.inventory_2_rounded, 'المنتجات والتصنيفات', const ProductListScreen(), isSubItem: true),
                                        _navItem(Icons.warehouse_rounded, 'إدارة المخزون', const InventoryScreen(), isSubItem: true),
                                        _navItem(Icons.qr_code_2_rounded, 'طباعة وتخصيص الباركود', const BarcodeCustomizerScreen(), isSubItem: true),
                                        if (isAdmin)
                                          _navItem(Icons.fact_check_rounded, 'الجرد المخزني', const StocktakeScreen(), isSubItem: true),
                                        _navItem(Icons.move_to_inbox_rounded, 'استلام بضاعة (شحنة جديدة)', const BlindReceiveScreen(), isSubItem: true),
                                      ],
                                      if (_featureEnabled(features, FeatureKeys.inventoryLogs))
                                        _navItem(Icons.history_rounded, 'حركات المخزن', const InventoryLogsScreen(), isSubItem: true),
                                    ],
                                  ),

                                  // Purchases & Suppliers Group
                                  if (isAdmin &&
                                      _featureEnabled(features, FeatureKeys.purchases) &&
                                      _featureEnabled(features, FeatureKeys.suppliers))
                                    _navGroup(
                                      title: 'المشتريات والموردين',
                                      icon: Icons.local_shipping_rounded,
                                      children: [
                                        _navItem(Icons.local_shipping_rounded, 'المشتريات والموردين', const PurchasesScreen(), isSubItem: true),
                                      ],
                                    ),

                                  // Customers & Finance Group
                                  _navGroup(
                                    title: 'العملاء والمالية',
                                    icon: Icons.account_balance_wallet_rounded,
                                    children: [
                                      if (_featureEnabled(features, FeatureKeys.customers))
                                        _navItem(Icons.people_alt_rounded, 'سجل العملاء', const CustomerScreen(), isSubItem: true),
                                      if (_featureEnabled(features, FeatureKeys.installments) || _hasActiveInstallments)
                                        _navItem(Icons.payments_rounded, 'التقسيط', const InstallmentsListScreen(), isSubItem: true),
                                      if (_featureEnabled(features, FeatureKeys.expenses))
                                        _navItem(Icons.payments_outlined, 'إدارة المصروفات', const ExpensesScreen(), isSubItem: true),
                                      if (isAdmin && _featureEnabled(features, FeatureKeys.promotions))
                                        _navItem(Icons.local_offer_rounded, 'العروض الترويجية', const PromotionsScreen(), isSubItem: true),
                                    ],
                                  ),

                                  // Administration & Reports Group
                                  if (isAdmin)
                                    _navGroup(
                                      title: 'الإدارة والتقارير',
                                      icon: Icons.admin_panel_settings_rounded,
                                      children: [
                                        if (_featureEnabled(features, FeatureKeys.reports))
                                          _navItem(Icons.bar_chart_rounded, 'تقارير المبيعات', const ReportsScreen(), isSubItem: true),
                                        if (_featureEnabled(features, FeatureKeys.partners))
                                          _navItem(Icons.handshake_rounded, 'الشركاء وتوزيع الأرباح', const PartnersScreen(), isSubItem: true),
                                        if (_featureEnabled(features, FeatureKeys.employees))
                                          _navItem(Icons.badge_rounded, 'فريق العمل والموظفون', const EmployeeListScreen(), isSubItem: true),
                                        _navItem(Icons.settings_rounded, 'إعدادات النظام', const SystemSettingsScreen(), isSubItem: true),
                                        _navItem(Icons.bug_report_rounded, 'سجلات الأعطال', const CrashLogsScreen(), isSubItem: true),
                                      ],
                                    ),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (_cloudSyncEnabled) ...[
                    const Divider(color: Colors.white24, height: 1),
                    _buildSyncSection(),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: Container(
                color: Colors.white,
                child: Navigator(
                  key: _contentNavKey,
                  onGenerateRoute: (settings) => MaterialPageRoute(
                    settings: settings,
                    builder: (_) => _currentScreen,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
      },
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

  void _ensureSectionExpandedFor(String title) {
    const salesTitles = {'سجل فواتير المبيعات', 'إدارة المرتجعات', 'إدارة الدليفري والطيارين', 'الورديات وتصفية الدرج'};
    const invTitles = {'المنتجات والتصنيفات', 'إدارة المخزون', 'طباعة وتخصيص الباركود', 'الجرد المخزني', 'استلام بضاعة (شحنة جديدة)', 'حركات المخزن'};
    const purchTitles = {'المشتريات والموردين'};
    const financeTitles = {'سجل العملاء', 'التقسيط', 'إدارة المصروفات', 'العروض الترويجية'};
    const adminTitles = {'تقارير المبيعات', 'الشركاء وتوزيع الأرباح', 'فريق العمل والموظفون', 'إعدادات النظام', 'سجلات الأعطال'};

    if (salesTitles.contains(title)) _collapsedSections.remove('المبيعات والطلبات');
    if (invTitles.contains(title)) _collapsedSections.remove('المخزون والمستودع');
    if (purchTitles.contains(title)) _collapsedSections.remove('المشتريات والموردين');
    if (financeTitles.contains(title)) _collapsedSections.remove('العملاء والمالية');
    if (adminTitles.contains(title)) _collapsedSections.remove('الإدارة والتقارير');
  }

  Widget _navGroup({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    if (_isCollapsed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Divider(color: Colors.white24, height: 1),
          ),
          ...children,
        ],
      );
    }

    final isExpanded = !_collapsedSections.contains(title);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _collapsedSections.add(title);
                  } else {
                    _collapsedSections.remove(title);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white70, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.0 : -0.25,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isExpanded) ...children,
      ],
    );
  }

  Widget _navItem(
    IconData icon,
    String title,
    Widget? screen, {
    bool isPos = false,
    bool isSubItem = false,
    VoidCallback? onTapOverride,
  }) {
    final isSelected = !isPos && _activeTitle == title;
    return Padding(
      padding: EdgeInsets.only(
        right: _isCollapsed ? 6 : (isSubItem ? 16 : 8),
        left: _isCollapsed ? 6 : 8,
        top: 1.5,
        bottom: 1.5,
      ),
      child: Tooltip(
        message: _isCollapsed ? title : '',
        waitDuration: const Duration(milliseconds: 300),
        child: Material(
          color: isSelected ? Colors.white.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: EdgeInsets.symmetric(
              horizontal: _isCollapsed ? 0 : 10,
              vertical: 0,
            ),
            leading: Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.85),
              size: isSubItem ? 18 : 20,
            ),
            title: _isCollapsed
                ? null
                : Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: isSubItem ? 12.5 : 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
            onTap: () {
              CrashLoggerService.addBreadcrumb('اختيار من القائمة: $title');
              CrashLoggerService.setContext('شاشة: $title');
              if (onTapOverride != null) {
                onTapOverride();
              } else if (isPos) {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(builder: (_) => const PosScreen()),
                );
              } else if (screen != null) {
                if (title == 'لوحة التحكم') {
                  try {
                    context.read<DashboardCubit>().loadStats(silent: true);
                  } catch (_) {}
                }
                if (_activeTitle == title) {
                  if (_contentNavKey.currentState?.canPop() == true) {
                    _contentNavKey.currentState?.popUntil((route) => route.isFirst);
                  }
                  return;
                }
                _ensureSectionExpandedFor(title);
                setState(() {
                  _activeTitle = title;
                  _currentScreen = screen;
                });
                _contentNavKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => screen),
                  (route) => false,
                );
              }
            },
          ),
        ),
      ),
    );
  }
}
