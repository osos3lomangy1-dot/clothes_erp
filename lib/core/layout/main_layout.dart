import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../constants/app_colors.dart';
import '../database/app_database.dart';
import '../di/injection.dart';
import '../features/feature_gate.dart';
import '../services/crash_logger_service.dart';
import '../services/rest_sync_service.dart';
import '../services/shortcut_settings_service.dart';
import '../theme/app_branding.dart';
import 'command_palette_dialog.dart';
import '../../features/settings/presentation/widgets/shortcuts_config_dialog.dart';
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
import '../../features/pre_orders/presentation/screens/pre_orders_screen.dart';
import '../../features/auth/domain/models/cashier_permissions_config.dart';
import '../../features/auth/services/cashier_permissions_service.dart';
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

  const MainLayout({
    super.key,
    required this.child,
    required this.currentRoute,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final GlobalKey<NavigatorState> _contentNavKey = GlobalKey<NavigatorState>();
  final Set<String> _collapsedSections = {};
  bool? _userCollapsedOverride;
  bool? _savedCollapsedOverrideBeforePos;
  bool _autoCollapsedForPos = false;
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
    HardwareKeyboard.instance.addHandler(_handleGlobalHardwareKeys);
    _currentScreen = widget.child;
    if (widget.currentRoute == '/pos' || widget.child is PosScreen) {
      _activeTitle = 'نقطة البيع (الكاشير)';
      _userCollapsedOverride = true;
      _autoCollapsedForPos = true;
      _savedCollapsedOverrideBeforePos = null;
    }

    final syncService = getIt.isRegistered<RestSyncService>() ? getIt<RestSyncService>() : null;
    final featureGate = getIt.isRegistered<FeatureGate>() ? getIt<FeatureGate>() : null;

    if (getIt.isRegistered<AppDatabase>()) {
      final db = getIt<AppDatabase>();
      final query = (db.select(db.customerInstallments)
        ..where(
          (t) =>
              t.deletedAt.isNull() & t.status.isIn(const ['active', 'overdue']),
        ));
      _activeInstallmentsSub = query.watch().listen((contracts) {
        final hasActive = contracts.isNotEmpty;
        if (mounted && _hasActiveInstallments != hasActive) {
          setState(() => _hasActiveInstallments = hasActive);
        }
      });
    }

    if (syncService != null && featureGate != null) {
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
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalHardwareKeys);
    _activeInstallmentsSub?.cancel();
    _cloudSyncSub?.cancel();
    _syncSubscription?.cancel();
    if (getIt.isRegistered<RestSyncService>()) {
      getIt<RestSyncService>().stopAutoSync();
    }
    super.dispose();
  }

  bool _handleGlobalHardwareKeys(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    // Avoid triggering when a modal dialog is currently topmost
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final key = event.logicalKey;

    // 1. Ctrl + K -> Command Palette
    if (isCtrl && !isAlt && key == LogicalKeyboardKey.keyK) {
      _openCommandPalette();
      return true;
    }

    final svc = getIt.isRegistered<ShortcutSettingsService>()
        ? getIt<ShortcutSettingsService>()
        : null;

    final posActivator = svc?.getActivator('openPos') ??
        const SingleActivator(LogicalKeyboardKey.f1);
    final shortcutsActivator = svc?.getActivator('openShortcuts') ??
        const SingleActivator(LogicalKeyboardKey.f1, alt: true);

    // 2. Open Shortcuts Guide (Alt + F1 by default)
    if (shortcutsActivator.accepts(event, HardwareKeyboard.instance) ||
        (isAlt && !isCtrl && key == LogicalKeyboardKey.f1)) {
      _openShortcutsGuide();
      return true;
    }

    // 3. Jump to POS Screen (F1 by default)
    if (posActivator.accepts(event, HardwareKeyboard.instance) ||
        (!isCtrl && !isAlt && key == LogicalKeyboardKey.f1)) {
      _handleItemTap('نقطة البيع (الكاشير)', const PosScreen(), true, null);
      return true;
    }

    return false;
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
          backgroundColor: result.isSuccess
              ? Colors.green.shade700
              : AppColors.error,
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
      if (widget.currentRoute == '/pos' || widget.child is PosScreen) {
        _activeTitle = 'نقطة البيع (الكاشير)';
        if (!_isCollapsed) {
          _savedCollapsedOverrideBeforePos = _userCollapsedOverride;
          _autoCollapsedForPos = true;
          _userCollapsedOverride = true;
        } else {
          _autoCollapsedForPos = false;
          _savedCollapsedOverrideBeforePos = null;
          _userCollapsedOverride = true;
        }
      }
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
        final svc = getIt.isRegistered<ShortcutSettingsService>() ? getIt<ShortcutSettingsService>() : null;
        final posAct = svc?.getActivator('openPos') ?? const SingleActivator(LogicalKeyboardKey.f1);
        final shortcutsAct = svc?.getActivator('openShortcuts') ?? const SingleActivator(LogicalKeyboardKey.f1, alt: true);
        final cmdAct = svc?.getActivator('openCommandPalette') ?? const SingleActivator(LogicalKeyboardKey.keyK, control: true);

        return CallbackShortcuts(
          bindings: {
            cmdAct: _openCommandPalette,
            shortcutsAct: _openShortcutsGuide,
            posAct: () => _handleItemTap('نقطة البيع (الكاشير)', const PosScreen(), true, null),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: collapsed ? 66 : 232,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final targetWidth = collapsed ? 66.0 : 232.0;
                    return ClipRect(
                      child: OverflowBox(
                        alignment: AlignmentDirectional.topStart,
                        minWidth: 0,
                        maxWidth: 232,
                        minHeight: constraints.maxHeight,
                        maxHeight: constraints.maxHeight,
                        child: SizedBox(
                          width: targetWidth,
                          height: constraints.maxHeight,
                          child: Material(
                            color: branding.primaryColor,
                            child: Column(
                              children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: collapsed ? 0 : 14,
                          vertical: 14,
                        ),
                        child: collapsed
                            ? Center(
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.menu_rounded,
                                    color: Colors.white,
                                  ),
                                  tooltip: 'توسيع القائمة',
                                  onPressed: () => setState(() {
                                    _autoCollapsedForPos = false;
                                    _savedCollapsedOverrideBeforePos = null;
                                    _userCollapsedOverride = !collapsed;
                                  }),
                                ),
                              )
                            : Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            7,
                                          ),
                                          child: Image.asset(
                                            'assets/icons/bay3ah-128.png',
                                            width: 28,
                                            height: 28,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) =>
                                                const Icon(
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
                                  IconButton(
                                    icon: const Icon(
                                      Icons.menu_open_rounded,
                                      color: Colors.white,
                                    ),
                                    tooltip: 'طي القائمة',
                                    onPressed: () => setState(() {
                                      _autoCollapsedForPos = false;
                                      _savedCollapsedOverrideBeforePos = null;
                                      _userCollapsedOverride = !collapsed;
                                    }),
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
                            final features =
                                snapshot.data ?? const <String, bool>{};
                            return BlocBuilder<AuthCubit, AuthState>(
                              builder: (context, authState) {
                                final isAdmin = _isAdmin(authState);
                                return ValueListenableBuilder<
                                  CashierPermissionsConfig
                                >(
                                  valueListenable:
                                      CashierPermissionsService.notifier,
                                  builder: (context, cashierPerms, _) {
                                    return SingleChildScrollView(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          // Command Palette Trigger
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            child: InkWell(
                                              key: const Key('command_palette_trigger_btn'),
                                              onTap: _openCommandPalette,
                                              borderRadius: BorderRadius.circular(8),
                                              child: Container(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: collapsed ? 6 : 10,
                                                  vertical: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.white24),
                                                ),
                                                child: collapsed
                                                    ? const Center(child: Icon(Icons.search_rounded, color: Colors.white, size: 20))
                                                    : const Row(
                                                        children: [
                                                          Icon(Icons.search_rounded, color: Colors.white70, size: 18),
                                                          SizedBox(width: 8),
                                                          Expanded(
                                                            child: Text(
                                                              'بحث أو أمر...',
                                                              style: TextStyle(color: Colors.white70, fontSize: 12),
                                                            ),
                                                          ),
                                                          Text(
                                                            'Ctrl+K',
                                                            style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),

                                          // Direct Top Actions
                                          if (isAdmin)
                                            _navItem(
                                              Icons.dashboard_rounded,
                                              'لوحة التحكم',
                                              widget.child,
                                            ),
                                          if (_featureEnabled(
                                            features,
                                            FeatureKeys.pos,
                                          ))
                                            _navItem(
                                              Icons.point_of_sale_rounded,
                                              'نقطة البيع (الكاشير)',
                                              const PosScreen(),
                                            ),

                                          // Sales & Orders Group
                                          _navGroup(
                                            title: 'المبيعات والطلبات',
                                            icon: Icons.receipt_long_rounded,
                                            children: [
                                              if (isAdmin ||
                                                  cashierPerms
                                                      .allowViewInvoicesHistory)
                                                _navItem(
                                                  Icons.receipt_long_rounded,
                                                  'سجل فواتير المبيعات',
                                                  const InvoicesScreen(),
                                                  isSubItem: true,
                                                ),
                                              _navItem(
                                                Icons.assignment_return_rounded,
                                                'إدارة المرتجعات',
                                                const ReturnScreen(),
                                                isSubItem: true,
                                              ),
                                              if (_featureEnabled(
                                                features,
                                                FeatureKeys.delivery,
                                              ))
                                                _navItem(
                                                  Icons.moped_rounded,
                                                  'إدارة الدليفري والطيارين',
                                                  const DeliveryOrdersScreen(),
                                                  isSubItem: true,
                                                ),
                                              if (_featureEnabled(
                                                features,
                                                FeatureKeys.preOrders,
                                              ))
                                                _navItem(
                                                  Icons.bookmark_added_rounded,
                                                  'الحجز المسبق والعربونات',
                                                  const PreOrdersScreen(),
                                                  isSubItem: true,
                                                ),
                                              if (_featureEnabled(
                                                features,
                                                FeatureKeys.shifts,
                                              ))
                                                _navItem(
                                                  Icons.lock_clock_rounded,
                                                  'الورديات وتصفية الدرج',
                                                  const ShiftScreen(),
                                                  isSubItem: true,
                                                ),
                                            ],
                                          ),

                                          // Inventory Group
                                          if (isAdmin ||
                                              cashierPerms.allowGoodsIntake)
                                            _navGroup(
                                              title: 'المخزون والمستودع',
                                              icon: Icons.warehouse_rounded,
                                              children: [
                                                if (isAdmin &&
                                                    _featureEnabled(
                                                      features,
                                                      FeatureKeys.inventory,
                                                    )) ...[
                                                  _navItem(
                                                    Icons.inventory_2_rounded,
                                                    'المنتجات والتصنيفات',
                                                    const ProductListScreen(),
                                                    isSubItem: true,
                                                  ),
                                                  _navItem(
                                                    Icons.warehouse_rounded,
                                                    'إدارة المخزون',
                                                    const InventoryScreen(),
                                                    isSubItem: true,
                                                  ),
                                                  _navItem(
                                                    Icons.fact_check_rounded,
                                                    'الجرد المخزني',
                                                    const StocktakeScreen(),
                                                    isSubItem: true,
                                                  ),
                                                ],
                                                if (isAdmin ||
                                                    cashierPerms
                                                        .allowGoodsIntake)
                                                  _navItem(
                                                    Icons.move_to_inbox_rounded,
                                                    'استلام بضاعة (شحنة جديدة)',
                                                    const BlindReceiveScreen(),
                                                    isSubItem: true,
                                                  ),
                                                if (isAdmin &&
                                                    _featureEnabled(
                                                      features,
                                                      FeatureKeys.inventoryLogs,
                                                    ))
                                                  _navItem(
                                                    Icons.history_rounded,
                                                    'حركات المخزن',
                                                    const InventoryLogsScreen(),
                                                    isSubItem: true,
                                                  ),
                                              ],
                                            ),

                                          // Purchases & Suppliers Group
                                          if (isAdmin &&
                                              _featureEnabled(
                                                features,
                                                FeatureKeys.purchases,
                                              ) &&
                                              _featureEnabled(
                                                features,
                                                FeatureKeys.suppliers,
                                              ))
                                            _navGroup(
                                              title: 'المشتريات والموردين',
                                              icon:
                                                  Icons.local_shipping_rounded,
                                              children: [
                                                _navItem(
                                                  Icons.local_shipping_rounded,
                                                  'المشتريات والموردين',
                                                  const PurchasesScreen(),
                                                  isSubItem: true,
                                                ),
                                              ],
                                            ),

                                          // Customers & Finance Group
                                          if (isAdmin ||
                                              cashierPerms
                                                  .allowManageCustomers ||
                                              cashierPerms.allowInstallments ||
                                              cashierPerms.allowCashExpenses)
                                            _navGroup(
                                              title: 'العملاء والمالية',
                                              icon: Icons
                                                  .account_balance_wallet_rounded,
                                              children: [
                                                if (_featureEnabled(
                                                      features,
                                                      FeatureKeys.customers,
                                                    ) &&
                                                    (isAdmin ||
                                                        cashierPerms
                                                            .allowManageCustomers))
                                                  _navItem(
                                                    Icons.people_alt_rounded,
                                                    'سجل العملاء',
                                                    const CustomerScreen(),
                                                    isSubItem: true,
                                                  ),
                                                if ((isAdmin ||
                                                        cashierPerms
                                                            .allowInstallments) &&
                                                    (_featureEnabled(
                                                          features,
                                                          FeatureKeys
                                                              .installments,
                                                        ) ||
                                                        _hasActiveInstallments))
                                                  _navItem(
                                                    Icons.payments_rounded,
                                                    'التقسيط',
                                                    const InstallmentsListScreen(),
                                                    isSubItem: true,
                                                  ),
                                                if (_featureEnabled(
                                                      features,
                                                      FeatureKeys.expenses,
                                                    ) &&
                                                    (isAdmin ||
                                                        cashierPerms
                                                            .allowCashExpenses))
                                                  _navItem(
                                                    Icons.payments_outlined,
                                                    'إدارة المصروفات',
                                                    const ExpensesScreen(),
                                                    isSubItem: true,
                                                  ),
                                                if (isAdmin &&
                                                    _featureEnabled(
                                                      features,
                                                      FeatureKeys.promotions,
                                                    ))
                                                  _navItem(
                                                    Icons.local_offer_rounded,
                                                    'العروض الترويجية',
                                                    const PromotionsScreen(),
                                                    isSubItem: true,
                                                  ),
                                              ],
                                            ),

                                          // Administration & Reports Group
                                          if (isAdmin)
                                            _navGroup(
                                              title: 'الإدارة والتقارير',
                                              icon: Icons
                                                  .admin_panel_settings_rounded,
                                              children: [
                                                if (_featureEnabled(
                                                  features,
                                                  FeatureKeys.reports,
                                                ))
                                                  _navItem(
                                                    Icons.bar_chart_rounded,
                                                    'تقارير المبيعات',
                                                    const ReportsScreen(),
                                                    isSubItem: true,
                                                  ),
                                                if (_featureEnabled(
                                                  features,
                                                  FeatureKeys.partners,
                                                ))
                                                  _navItem(
                                                    Icons.handshake_rounded,
                                                    'الشركاء وتوزيع الأرباح',
                                                    const PartnersScreen(),
                                                    isSubItem: true,
                                                  ),
                                                if (_featureEnabled(
                                                  features,
                                                  FeatureKeys.employees,
                                                ))
                                                  _navItem(
                                                    Icons.badge_rounded,
                                                    'فريق العمل والموظفون',
                                                    const EmployeeListScreen(),
                                                    isSubItem: true,
                                                  ),
                                                _navItem(
                                                  Icons.settings_rounded,
                                                  'إعدادات النظام',
                                                  const SystemSettingsScreen(),
                                                  isSubItem: true,
                                                ),
                                                _navItem(
                                                  Icons.bug_report_rounded,
                                                  'سجلات الأعطال',
                                                  const CrashLogsScreen(),
                                                  isSubItem: true,
                                                ),
                                              ],
                                            ),
                                          const SizedBox(height: 16),
                                        ],
                                      ),
                                    );
                                  },
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
                      // ── Logout Button ──
                      const Divider(color: Colors.white24, height: 1),
                      _buildLogoutButton(collapsed),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
              Expanded(
                child: ClipRect(
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        Expanded(
                          child: Navigator(
                            key: _contentNavKey,
                            onGenerateRoute: (settings) => MaterialPageRoute(
                              settings: settings,
                              builder: (_) => _currentScreen,
                            ),
                          ),
                        ),
                        if (_activeTitle != 'نقطة البيع (الكاشير)')
                          _buildContextualHotkeyStrip(),
                      ],
                    ),
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
                        horizontal: 6,
                        vertical: 2,
                      ),
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

  Widget _buildLogoutButton(bool collapsed) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 0 : 12,
        vertical: 10,
      ),
      child: collapsed
          ? Center(
              child: Tooltip(
                message: 'تسجيل الخروج',
                waitDuration: const Duration(milliseconds: 200),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _confirmLogout(),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : Material(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _confirmLogout(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.logout_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'تسجيل الخروج',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.error),
            SizedBox(width: 10),
            Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('خروج'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<AuthCubit>().logout();
    }
  }

  void _ensureSectionExpandedFor(String title) {
    const salesTitles = {
      'سجل فواتير المبيعات',
      'إدارة المرتجعات',
      'إدارة الدليفري والطيارين',
      'الورديات وتصفية الدرج',
    };
    const invTitles = {
      'المنتجات والتصنيفات',
      'إدارة المخزون',
      'طباعة وتخصيص الباركود',
      'الجرد المخزني',
      'استلام بضاعة (شحنة جديدة)',
      'حركات المخزن',
    };
    const purchTitles = {'المشتريات والموردين'};
    const financeTitles = {
      'سجل العملاء',
      'التقسيط',
      'إدارة المصروفات',
      'العروض الترويجية',
    };
    const adminTitles = {
      'تقارير المبيعات',
      'الشركاء وتوزيع الأرباح',
      'فريق العمل والموظفون',
      'إعدادات النظام',
      'سجلات الأعطال',
    };

    if (salesTitles.contains(title)) {
      _collapsedSections.remove('المبيعات والطلبات');
    }
    if (invTitles.contains(title)) {
      _collapsedSections.remove('المخزون والمستودع');
    }
    if (purchTitles.contains(title)) {
      _collapsedSections.remove('المشتريات والموردين');
    }
    if (financeTitles.contains(title)) {
      _collapsedSections.remove('العملاء والمالية');
    }
    if (adminTitles.contains(title)) {
      _collapsedSections.remove('الإدارة والتقارير');
    }
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
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

  void _handleItemTap(
    String title,
    Widget? screen,
    bool isPos,
    VoidCallback? onTapOverride,
  ) {
    CrashLoggerService.addBreadcrumb('اختيار من القائمة: $title');
    CrashLoggerService.setContext('شاشة: $title');
    if (onTapOverride != null) {
      onTapOverride();
    } else if (screen != null) {
      if (title == 'لوحة التحكم') {
        try {
          context.read<DashboardCubit>().loadStats(silent: true);
        } catch (_) {}
      }
      final isPosScreen =
          title == 'نقطة البيع (الكاشير)' || screen is PosScreen || isPos;
      if (_activeTitle == title) {
        if (_contentNavKey.currentState?.canPop() == true) {
          _contentNavKey.currentState?.popUntil((route) => route.isFirst);
        }
        if (isPosScreen && _userCollapsedOverride != true) {
          setState(() {
            _userCollapsedOverride = true;
            _autoCollapsedForPos = true;
          });
        }
        return;
      }
      _ensureSectionExpandedFor(title);
      final wasCollapsed = _isCollapsed;
      setState(() {
        _activeTitle = title;
        _currentScreen = screen;
        if (isPosScreen) {
          if (!wasCollapsed) {
            _savedCollapsedOverrideBeforePos = _userCollapsedOverride;
            _autoCollapsedForPos = true;
            _userCollapsedOverride = true;
          } else {
            _autoCollapsedForPos = false;
            _savedCollapsedOverrideBeforePos = null;
            _userCollapsedOverride = true;
          }
        } else if (_autoCollapsedForPos) {
          _userCollapsedOverride = _savedCollapsedOverrideBeforePos;
          _autoCollapsedForPos = false;
          _savedCollapsedOverrideBeforePos = null;
        }
      });
      _contentNavKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => screen),
        (route) => false,
      );
    }
  }

  bool _isPaletteOpen = false;
  Future<void> _openCommandPalette() async {
    if (_isPaletteOpen) return;
    _isPaletteOpen = true;
    try {
      final authState = context.read<AuthCubit>().state;
      final isAdmin = _isAdmin(authState);

      final items = <CommandPaletteItem>[
      // Screens
      CommandPaletteItem(
        id: 'nav_pos',
        title: 'نقطة البيع (الكاشير)',
        category: 'شاشات النظام',
        icon: Icons.point_of_sale_rounded,
        subtitle: 'المبيعات السريعة وتسجيل الفواتير [F1]',
        onSelect: () => _handleItemTap('نقطة البيع (الكاشير)', const PosScreen(), true, null),
      ),
      CommandPaletteItem(
        id: 'nav_products',
        title: 'المنتجات والتصنيفات',
        category: 'شاشات النظام',
        icon: Icons.inventory_2_rounded,
        subtitle: 'دليل الأصناف والمقاسات والأسعار',
        onSelect: () => _handleItemTap('المنتجات والتصنيفات', const ProductListScreen(), false, null),
      ),
      CommandPaletteItem(
        id: 'nav_purchases',
        title: 'فواتير المشتريات والموردين',
        category: 'شاشات النظام',
        icon: Icons.shopping_cart_rounded,
        subtitle: 'توريد البضائع وإدخال الشحنات',
        onSelect: () => _handleItemTap('المشتريات والموردين', const PurchasesScreen(), false, null),
      ),
      CommandPaletteItem(
        id: 'nav_invoices',
        title: 'سجل فواتير المبيعات',
        category: 'شاشات النظام',
        icon: Icons.receipt_long_rounded,
        subtitle: 'سجل الفواتير السابقة وطباعتها',
        onSelect: () => _handleItemTap('سجل فواتير المبيعات', const InvoicesScreen(), false, null),
      ),
      CommandPaletteItem(
        id: 'nav_treasury',
        title: 'الخزينة وحركات الدرج والمصروفات',
        category: 'شاشات النظام',
        icon: Icons.account_balance_wallet_rounded,
        subtitle: 'سندات الصرف والقبض والمصروفات النثرية',
        onSelect: () => _handleItemTap('إدارة المصروفات', const ExpensesScreen(), false, null),
      ),
      CommandPaletteItem(
        id: 'nav_shifts',
        title: 'الورديات وتصفية الدرج',
        category: 'شاشات النظام',
        icon: Icons.timer_rounded,
        subtitle: 'فتح وتقفيل الورديات والجرد الأعمى',
        onSelect: () => _handleItemTap('الورديات وتصفية الدرج', const ShiftScreen(), false, null),
      ),
      CommandPaletteItem(
        id: 'nav_customers',
        title: 'سجل العملاء والحسابات',
        category: 'شاشات النظام',
        icon: Icons.people_alt_rounded,
        subtitle: 'بيانات العملاء والديون والولاء',
        onSelect: () => _handleItemTap('سجل العملاء', const CustomerScreen(), false, null),
      ),
      CommandPaletteItem(
        id: 'nav_installments',
        title: 'إدارة عقود الأقساط',
        category: 'شاشات النظام',
        icon: Icons.payments_rounded,
        subtitle: 'متابعة الدفعات والأقساط المستحقة',
        onSelect: () => _handleItemTap('التقسيط', const InstallmentsListScreen(), false, null),
      ),
      CommandPaletteItem(
        id: 'nav_delivery',
        title: 'إدارة الدليفري والطيارين',
        category: 'شاشات النظام',
        icon: Icons.delivery_dining_rounded,
        subtitle: 'طلبات التوصيل ومتابعة الكباتن',
        onSelect: () => _handleItemTap('إدارة الدليفري والطيارين', const DeliveryOrdersScreen(), false, null),
      ),
      CommandPaletteItem(
        id: 'nav_blind_receive',
        title: 'استلام بضاعة (شحنة جديدة)',
        category: 'شاشات النظام',
        icon: Icons.move_to_inbox_rounded,
        subtitle: 'فحص الباركود واستلام الشحنات وتحديث المخزون',
        onSelect: () => _handleItemTap('استلام بضاعة (شحنة جديدة)', const BlindReceiveScreen(), false, null),
      ),
      if (isAdmin) ...[
        CommandPaletteItem(
          id: 'nav_stocktake',
          title: 'الجرد المخزني',
          category: 'شاشات النظام',
          icon: Icons.fact_check_rounded,
          subtitle: 'مطابقة الأرصدة الفعلية وحساب الفروقات والتسوية',
          onSelect: () => _handleItemTap('الجرد المخزني', const StocktakeScreen(), false, null),
        ),
        CommandPaletteItem(
          id: 'nav_inventory_logs',
          title: 'حركات المخزن',
          category: 'شاشات النظام',
          icon: Icons.history_rounded,
          subtitle: 'سجل حركات دخول وخروج وتعديل المخزون',
          onSelect: () => _handleItemTap('حركات المخزن', const InventoryLogsScreen(), false, null),
        ),
        CommandPaletteItem(
          id: 'nav_settings',
          title: 'مركز إعدادات النظام الموحد',
          category: 'شاشات النظام',
          icon: Icons.settings_rounded,
          subtitle: 'تخصيص كامل للنظام والمزايا والطباعة',
          onSelect: () => _handleItemTap('إعدادات النظام', const SystemSettingsScreen(), false, null),
        ),
        CommandPaletteItem(
          id: 'nav_reports',
          title: 'تقارير المبيعات والأرباح',
          category: 'شاشات النظام',
          icon: Icons.bar_chart_rounded,
          subtitle: 'الرسوم البيانية والتحليلات المالية',
          onSelect: () => _handleItemTap('تقارير المبيعات', const ReportsScreen(), false, null),
        ),
      ],

      // Quick Actions
      CommandPaletteItem(
        id: 'act_add_product',
        title: 'إضافة منتج جديد وسريع',
        category: 'إجراءات سريعة',
        icon: Icons.add_business_rounded,
        subtitle: 'تسجيل صنف ومقاساته مباشرة في النظام',
        onSelect: () => _handleItemTap('المنتجات والتصنيفات', const ProductListScreen(), false, null),
      ),
      CommandPaletteItem(
        id: 'act_quick_expense',
        title: 'تسجيل حركة درج / مصروف نثري',
        category: 'إجراءات سريعة',
        icon: Icons.payments_outlined,
        subtitle: 'إثبات مصروف أو سحب نقدي من الدرج',
        onSelect: () => _handleItemTap('إدارة المصروفات', const ExpensesScreen(), false, null),
      ),
      CommandPaletteItem(
        id: 'act_close_shift',
        title: 'تقفيل الوردية الحالية',
        category: 'إجراءات سريعة',
        icon: Icons.lock_clock_rounded,
        subtitle: 'جرد الدرج وتقفيل الحساب وطباعة التقرير Z',
        onSelect: () => _handleItemTap('الورديات وتصفية الدرج', const ShiftScreen(), false, null),
      ),

      // Quick Settings
      CommandPaletteItem(
        id: 'set_shortcuts',
        title: 'دليل وتخصيص اختصارات لوحة المفاتيح [F1]',
        category: 'إعدادات سريعة',
        icon: Icons.keyboard_rounded,
        subtitle: 'تعديل وتعيين أزرار الكيبورد لكل العمليات',
        onSelect: _openShortcutsGuide,
      ),
      if (isAdmin) ...[
        CommandPaletteItem(
          id: 'set_printers',
          title: 'إعدادات الطابعات والورق الحراري',
          category: 'إعدادات سريعة',
          icon: Icons.print_rounded,
          subtitle: 'تخصيص مقاس الورق وترويسة الفاتورة',
          onSelect: () => _handleItemTap('إعدادات النظام', const SystemSettingsScreen(initialCategory: 'printing'), false, null),
        ),
        CommandPaletteItem(
          id: 'set_store_name',
          title: 'تعديل اسم وبيانات المتجر',
          category: 'إعدادات سريعة',
          icon: Icons.storefront_rounded,
          subtitle: 'الهاتف، العنوان، والألوان الرسمية',
          onSelect: () => _handleItemTap('إعدادات النظام', const SystemSettingsScreen(initialCategory: 'store'), false, null),
        ),
      ],
    ];

      await showDialog(
        context: context,
        builder: (_) => CommandPaletteDialog(items: items),
      );
    } finally {
      _isPaletteOpen = false;
    }
  }

  bool _isShortcutsGuideOpen = false;
  Future<void> _openShortcutsGuide() async {
    if (_isShortcutsGuideOpen) return;
    _isShortcutsGuideOpen = true;
    try {
      await showDialog(
        context: context,
        builder: (_) => const ShortcutsConfigDialog(),
      );
    } finally {
      _isShortcutsGuideOpen = false;
    }
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

    if (_isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Center(
          child: Tooltip(
            message: title,
            waitDuration: const Duration(milliseconds: 200),
            child: Material(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () =>
                    _handleItemTap(title, screen, isPos, onTapOverride),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected
                        ? Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1.2,
                          )
                        : null,
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : Colors.white70,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        right: isSubItem ? 16 : 8,
        left: 8,
        top: 1.5,
        bottom: 1.5,
      ),
      child: Material(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ),
          leading: Icon(
            icon,
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.85),
            size: isSubItem ? 18 : 20,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: isSelected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.9),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: isSubItem ? 12.5 : 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _handleItemTap(title, screen, isPos, onTapOverride),
        ),
      ),
    );
  }

  Widget _buildContextualHotkeyStrip() {
    final title = _activeTitle.toLowerCase();
    final bool isStocktake = title.contains('جرد');
    final bool isProducts = !isStocktake &&
        (title.contains('منتجات') ||
            title.contains('تصنيفات') ||
            title.contains('مخزون') ||
            title.contains('بضاعة'));
    final bool isDelivery = title.contains('دليفري') ||
        title.contains('توصيل') ||
        title.contains('طيار') ||
        title.contains('شحن');
    final bool isPurchases =
        title.contains('مشتريات') || title.contains('مورد');

    final String stripKey = isStocktake
        ? 'contextual_hotkey_strip_stocktake'
        : isProducts
            ? 'contextual_hotkey_strip_products'
            : isDelivery
                ? 'contextual_hotkey_strip_delivery'
                : isPurchases
                    ? 'contextual_hotkey_strip_purchases'
                    : 'contextual_hotkey_strip_general';

    final List<_ContextualHotkeyItem> items;
    if (isStocktake) {
      items = [
        const _ContextualHotkeyItem(
          key: 'hotkey_stocktake_confirm_qty',
          label: 'Enter تأكيد الكمية',
          icon: Icons.keyboard_return_rounded,
        ),
        const _ContextualHotkeyItem(
          key: 'hotkey_stocktake_search',
          label: 'F2 بحث صنف',
          icon: Icons.search_rounded,
        ),
        const _ContextualHotkeyItem(
          key: 'hotkey_stocktake_commit',
          label: 'Ctrl+S اعتماد الجرد',
          icon: Icons.check_circle_rounded,
        ),
        _ContextualHotkeyItem(
          key: 'hotkey_stocktake_shortcuts',
          label: 'F1 اختصارات',
          icon: Icons.keyboard_rounded,
          onTap: _openShortcutsGuide,
        ),
      ];
    } else if (isProducts) {
      items = [
        const _ContextualHotkeyItem(
          key: 'hotkey_products_new_size',
          label: 'F3 سطر مقاس جديد',
          icon: Icons.add_box_rounded,
        ),
        const _ContextualHotkeyItem(
          key: 'hotkey_products_save',
          label: 'Ctrl+S حفظ المنتجات',
          icon: Icons.save_rounded,
        ),
        const _ContextualHotkeyItem(
          key: 'hotkey_products_barcode',
          label: 'F4 طباعة باركود',
          icon: Icons.qr_code_rounded,
        ),
        const _ContextualHotkeyItem(
          key: 'hotkey_products_grid_nav',
          label: 'تنقل شبكي بالأسهم',
          icon: Icons.grid_view_rounded,
        ),
        _ContextualHotkeyItem(
          key: 'hotkey_products_shortcuts',
          label: 'F1 اختصارات',
          icon: Icons.keyboard_rounded,
          onTap: _openShortcutsGuide,
        ),
      ];
    } else if (isDelivery) {
      items = [
        const _ContextualHotkeyItem(
          key: 'hotkey_delivery_new_order',
          label: 'طلب دليفري جديد',
          icon: Icons.add_circle_outline_rounded,
        ),
        const _ContextualHotkeyItem(
          key: 'hotkey_delivery_settle_courier',
          label: 'تصفية كاش طيار',
          icon: Icons.account_balance_wallet_rounded,
        ),
        const _ContextualHotkeyItem(
          key: 'hotkey_delivery_company_payout',
          label: 'تسجيل دفعة شركة',
          icon: Icons.payments_rounded,
        ),
        _ContextualHotkeyItem(
          key: 'hotkey_delivery_palette',
          label: 'Ctrl+K لوحة الأوامر',
          icon: Icons.terminal_rounded,
          onTap: _openCommandPalette,
        ),
      ];
    } else if (isPurchases) {
      items = [
        const _ContextualHotkeyItem(
          key: 'hotkey_purchases_new_bill',
          label: 'فاتورة مشتريات جديدة',
          icon: Icons.post_add_rounded,
        ),
        const _ContextualHotkeyItem(
          key: 'hotkey_purchases_save',
          label: 'Ctrl+S اعتماد وحفظ',
          icon: Icons.save_rounded,
        ),
        const _ContextualHotkeyItem(
          key: 'hotkey_purchases_supplier',
          label: 'F2 اختيار مورد',
          icon: Icons.person_search_rounded,
        ),
        _ContextualHotkeyItem(
          key: 'hotkey_purchases_shortcuts',
          label: 'F1 اختصارات',
          icon: Icons.keyboard_rounded,
          onTap: _openShortcutsGuide,
        ),
      ];
    } else {
      items = [
        _ContextualHotkeyItem(
          key: 'hotkey_general_palette',
          label: 'Ctrl+K لوحة الأوامر العامة',
          icon: Icons.terminal_rounded,
          onTap: _openCommandPalette,
        ),
        _ContextualHotkeyItem(
          key: 'hotkey_general_shortcuts',
          label: 'F1 دليل ومفاتيح النظام',
          icon: Icons.keyboard_rounded,
          onTap: _openShortcutsGuide,
        ),
        _ContextualHotkeyItem(
          key: 'hotkey_general_search',
          label: 'Ctrl+F بحث فوري',
          icon: Icons.search_rounded,
          onTap: _openCommandPalette,
        ),
      ];
    }

    return Container(
      key: Key(stripKey),
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: InkWell(
                      key: Key(item.key),
                      onTap: item.onTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF334155),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item.icon,
                              size: 13,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              item.label,
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          InkWell(
            key: const Key('contextual_hotkey_palette_shortcut'),
            onTap: _openCommandPalette,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Ctrl+K',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextualHotkeyItem {
  final String key;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _ContextualHotkeyItem({
    required this.key,
    required this.label,
    required this.icon,
    this.onTap,
  });
}
