import 'dart:async';
import 'package:drift/drift.dart' as drift show InsertMode;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/layout/main_layout.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/utils/money.dart';
import '../../../employees/presentation/screens/employee_list_screen.dart';
import '../../../inventory/presentation/screens/blind_receive_screen.dart';
import '../../../partners/presentation/screens/partners_screen.dart';
import '../../../reports/presentation/screens/reports_screen.dart';
import '../../../reports/presentation/widgets/payment_method_pie_chart.dart';
import '../../../reports/presentation/widgets/top_selling_products_widget.dart';
import '../../../settings/presentation/screens/excel_migration_screen.dart';
import '../cubits/dashboard_cubit.dart';
import '../cubits/dashboard_state.dart';
import '../../domain/entities/dashboard_stats_entity.dart';
import '../widgets/hourly_sales_chart.dart';
import '../widgets/store_financial_interview_dialog.dart';
import '../widgets/weekly_sales_chart.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<DashboardCubit>()..loadStats(),
      child: const _AdminDashboardView(),
    );
  }
}

class QuickSetupGuideCard extends StatefulWidget {
  const QuickSetupGuideCard({super.key});

  @override
  State<QuickSetupGuideCard> createState() => _QuickSetupGuideCardState();
}

class _QuickSetupGuideCardState extends State<QuickSetupGuideCard> {
  static const String _quickSetupMetaKey = 'dashboard.quick_setup_state';
  bool _collapsed = false;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    try {
      if (!getIt.isRegistered<AppDatabase>()) return;
      final db = getIt<AppDatabase>();
      final row = await (db.select(
        db.appMeta,
      )..where((t) => t.key.equals(_quickSetupMetaKey))).getSingleOrNull();
      if (!mounted || row == null) return;
      setState(() {
        _hidden = row.value == 'hidden';
        _collapsed = row.value == 'collapsed';
      });
    } catch (_) {}
  }

  Future<void> _saveState(String stateVal) async {
    try {
      if (!getIt.isRegistered<AppDatabase>()) return;
      final db = getIt<AppDatabase>();
      await db
          .into(db.appMeta)
          .insert(
            AppMetaCompanion.insert(
              key: _quickSetupMetaKey,
              value: stateVal,
              updatedAt: DateTime.now(),
            ),
            mode: drift.InsertMode.insertOrReplace,
          );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();

    final steps = [
      (
        key: const Key('quick_setup_partners_btn'),
        icon: Icons.account_balance_rounded,
        title: 'تسجيل رأس المال والشركاء',
        subtitle: 'إدخال رأس المال الافتتاحي ونسب الشركاء',
        screen: const PartnersScreen(),
      ),
      (
        key: const Key('quick_setup_excel_btn'),
        icon: Icons.table_view_rounded,
        title: 'استيراد البضاعة والعملاء (Excel)',
        subtitle: 'ترحيل المنتجات والعملاء والأقساط القديمة',
        screen: const ExcelMigrationScreen(userId: 'admin'),
      ),
      (
        key: const Key('quick_setup_receive_btn'),
        icon: Icons.move_to_inbox_rounded,
        title: 'استلام بضاعة جديدة يدوياً',
        subtitle: 'إضافة شحنة سريعة وتحديث المخزون',
        screen: const BlindReceiveScreen(),
      ),
      (
        key: const Key('quick_setup_employees_btn'),
        icon: Icons.badge_rounded,
        title: 'إضافة الكاشير والموظفين (PIN)',
        subtitle: 'إنشاء حسابات الكاشير وتحديد الصلاحيات',
        screen: const EmployeeListScreen(),
      ),
    ];

    return Container(
      key: const Key('quick_setup_guide_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.rocket_launch_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'خطوات تأسيس المحل السريعة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              IconButton(
                key: const Key('quick_setup_financial_interview_btn'),
                tooltip: 'استبيان الوضع المالي الاختياري',
                onPressed: () => StoreFinancialInterviewDialog.show(context),
                icon: Icon(
                  Icons.tune_rounded,
                  color: AppColors.primary,
                  size: 19,
                ),
              ),
              IconButton(
                key: const Key('quick_setup_toggle_btn'),
                tooltip: _collapsed ? 'توسيع' : 'طي',
                onPressed: () {
                  final nextCollapsed = !_collapsed;
                  setState(() => _collapsed = nextCollapsed);
                  _saveState(nextCollapsed ? 'collapsed' : 'expanded');
                },
                icon: Icon(
                  _collapsed
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                ),
              ),
              IconButton(
                key: const Key('quick_setup_hide_btn'),
                tooltip: 'إخفاء البطاقة',
                onPressed: () {
                  setState(() => _hidden = true);
                  _saveState('hidden');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          if (!_collapsed) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth >= 900
                    ? (constraints.maxWidth - 30) / 4
                    : (constraints.maxWidth >= 540
                          ? (constraints.maxWidth - 10) / 2
                          : constraints.maxWidth);
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final step in steps)
                      SizedBox(
                        width: itemWidth,
                        child: InkWell(
                          key: step.key,
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => step.screen),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.outlineVariant,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  step.icon,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        step.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: AppColors.onSurface,
                                        ),
                                      ),
                                      Text(
                                        step.subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 13,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminDashboardView extends StatefulWidget {
  const _AdminDashboardView();

  @override
  State<_AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<_AdminDashboardView> {
  StreamSubscription<Map<String, bool>>? _featureSub;
  StreamSubscription<String?>? _creditSub;
  bool _installmentsEnabled = false;
  bool _suppliersEnabled = true;
  bool _creditEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService.checkForUpdate(context);
      }
    });

    final featureGate = getIt<FeatureGate>();
    _featureSub = featureGate.watchFeatures().listen((features) {
      if (mounted) {
        setState(() {
          _installmentsEnabled = features[FeatureKeys.installments] ?? false;
          _suppliersEnabled = features[FeatureKeys.suppliers] ?? true;
        });
      }
    });
    _creditSub = featureGate.watchMeta('payment.credit').listen((val) {
      final enabled = val == null
          ? true
          : (val == '1' || val.toLowerCase() == 'true');
      if (mounted) {
        setState(() {
          _creditEnabled = enabled;
        });
      }
    });
  }

  @override
  void dispose() {
    _featureSub?.cancel();
    _creditSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      currentRoute: '/dashboard',
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'لوحة تحكم المدير العام',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'نبض النشاط اللحظي، السيولة، والأرباح اليومية',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            Builder(
              builder: (innerCtx) {
                final screenWidth = MediaQuery.sizeOf(innerCtx).width;
                final isCompact = screenWidth < 850;
                if (isCompact) {
                  return IconButton(
                    tooltip: 'التقرير المالي الشامل',
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.analytics_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(innerCtx).push(
                        MaterialPageRoute(
                          builder: (_) => const ReportsScreen(),
                        ),
                      );
                    },
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(
                      Icons.analytics_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: const Text(
                      'التقرير المالي الشامل',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(innerCtx).push(
                        MaterialPageRoute(
                          builder: (_) => const ReportsScreen(),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'التحقق من التحديثات',
              onPressed: () => AppUpdateService.checkForUpdate(
                context,
                forceCheck: true,
                showNoUpdateToast: true,
              ),
              icon: Icon(Icons.system_update_rounded, color: AppColors.primary),
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
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.errorMessage ?? 'حدث خطأ أثناء تحميل البيانات',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      onPressed: () =>
                          context.read<DashboardCubit>().loadStats(),
                      child: const Text(
                        'إعادة المحاولة',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              );
            }

            final stats = state.stats ?? const DashboardStatsEntity();

            return RefreshIndicator(
              onRefresh: () => context.read<DashboardCubit>().loadStats(),
              child: ListView(
                padding: const EdgeInsets.all(20.0),
                children: [
                  const QuickSetupGuideCard(),
                  const SizedBox(height: 16),

                  // 1. Executive Financial Row (4 Cards)
                  _buildExecutiveKpiRow(context, stats),

                  const SizedBox(height: 16),

                  // 2. Action & Risk Alerts Center (4 Compact Cards)
                  _buildActionCenterRow(context, stats),

                  const SizedBox(height: 24),

                  // 3. Middle Section: Weekly Trend & Payment Methods
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 1050) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: WeeklySalesChart(
                                points: stats.last7DaysSales,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: PaymentMethodPieChart(
                                breakdown: stats.todayPaymentBreakdown,
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          WeeklySalesChart(points: stats.last7DaysSales),
                          const SizedBox(height: 16),
                          PaymentMethodPieChart(
                            breakdown: stats.todayPaymentBreakdown,
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // 4. Lower Section: Hourly Today Activity & Best Sellers
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 1050) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: HourlySalesChart(
                                hourlyPoints: stats.todayHourlySales,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: TopSellingProductsWidget(
                                products: stats.todayTopProducts,
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          HourlySalesChart(
                            hourlyPoints: stats.todayHourlySales,
                          ),
                          const SizedBox(height: 16),
                          TopSellingProductsWidget(
                            products: stats.todayTopProducts,
                          ),
                        ],
                      );
                    },
                  ),

                  // 5. Low Stock Alert Table
                  if (stats.lowStockVariants.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _buildLowStockSection(stats),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildExecutiveKpiRow(
    BuildContext context,
    DashboardStatsEntity stats,
  ) {
    final avgTicket = stats.todayTransactions > 0
        ? stats.todaySales ~/ stats.todayTransactions
        : 0;

    final cardTodaySales = _KpiCard(
      title: 'مبيعات اليوم',
      value: '${Money(stats.todaySales).toDisplay()} ج.م',
      icon: Icons.monetization_on_rounded,
      color: AppColors.primary,
      growthPercent: stats.todaySalesGrowthPercent,
      subtitle: stats.todayReturnsTotal > 0
          ? '${stats.todayTransactions} فاتورة - صافي: ${Money(stats.netTodaySalesAfterReturns).toDisplay()} ج.م'
          : '${stats.todayTransactions} فاتورة صادرة',
    );

    final cardNetProfit = _KpiCard(
      title: 'صافي ربح اليوم (تقديري)',
      value: '${Money(stats.todayEstimatedNetProfit).toDisplay()} ج.م',
      icon: Icons.trending_up_rounded,
      color: stats.todayEstimatedNetProfit >= 0
          ? AppColors.secondary
          : AppColors.error,
      growthPercent: stats.todayNetProfitGrowthPercent,
      subtitle:
          'هامش الربح: ${stats.todayProfitMarginPercent.toStringAsFixed(1)}% | التكلفة: ${Money(stats.todayCost).toDisplay()} ج.م',
      isHighlighted: true,
    );

    final cardLiveCash = _KpiCard(
      title: 'السيولة الحالية بالدرج',
      value: '${Money(stats.liveDrawerCash).toDisplay()} ج.م',
      icon: Icons.point_of_sale_rounded,
      color: AppColors.primary,
      subtitle: stats.hasActiveShift
          ? 'الوردية نشطة (${stats.activeCashierName ?? ""})'
          : 'لا توجد وردية مفتوحة حالياً',
    );

    final cardAvgTicket = _KpiCard(
      title: 'متوسط الفاتورة اليوم',
      value: '${Money(avgTicket).toDisplay()} ج.م',
      icon: Icons.receipt_long_rounded,
      color: AppColors.secondary,
      subtitle: 'المصروفات: ${Money(stats.todayExpenses).toDisplay()} ج.م',
    );

    final cardInventoryCapital = _KpiCard(
      title: 'قيمة المخزون بالتكلفة',
      value: '${Money(stats.inventoryCostCapitalPiasters).toDisplay()} ج.م',
      icon: Icons.inventory_2_rounded,
      color: AppColors.primary,
      subtitle: 'إجمالي رأس المال بالمخزن',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1150) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cardTodaySales),
                  const SizedBox(width: 12),
                  Expanded(child: cardNetProfit),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: cardLiveCash),
                  const SizedBox(width: 12),
                  Expanded(child: cardAvgTicket),
                ],
              ),
              const SizedBox(height: 12),
              cardInventoryCapital,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cardTodaySales),
            const SizedBox(width: 12),
            Expanded(child: cardNetProfit),
            const SizedBox(width: 12),
            Expanded(child: cardLiveCash),
            const SizedBox(width: 12),
            Expanded(child: cardAvgTicket),
            const SizedBox(width: 12),
            Expanded(child: cardInventoryCapital),
          ],
        );
      },
    );
  }

  Widget _buildActionCenterRow(
    BuildContext context,
    DashboardStatsEntity stats,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final alertStock = _MiniAlertCard(
          title: 'نواقص المخزون',
          countText: '${stats.lowStockCount} صنف',
          subtext: 'وصل لحد الأمان',
          icon: Icons.warning_amber_rounded,
          color: stats.lowStockCount > 0
              ? AppColors.warning
              : AppColors.onSurfaceVariant,
          bgColor: stats.lowStockCount > 0
              ? AppColors.warningContainer
              : AppColors.surfaceContainer,
        );

        final showInstallments =
            _installmentsEnabled ||
            stats.overdueInstallmentsCount > 0 ||
            stats.overdueInstallmentsAmount > 0;
        final alertInstallments = _MiniAlertCard(
          title: 'أقساط متأخرة',
          countText: '${stats.overdueInstallmentsCount} عقد',
          subtext:
              '${Money(stats.overdueInstallmentsAmount).toDisplay()} ج.م متأخرة',
          icon: Icons.payments_rounded,
          color: stats.overdueInstallmentsCount > 0
              ? AppColors.error
              : AppColors.onSurfaceVariant,
          bgColor: stats.overdueInstallmentsCount > 0
              ? AppColors.errorContainer
              : AppColors.surfaceContainer,
        );

        final showSuppliers = _suppliersEnabled || stats.totalSupplierDebts > 0;
        final alertSuppliers = _MiniAlertCard(
          title: 'مديونية الموردين',
          countText: '${Money(stats.totalSupplierDebts).toDisplay()} ج.م',
          subtext: 'مستحقات على المحل',
          icon: Icons.local_shipping_rounded,
          color: AppColors.onSurfaceVariant,
          bgColor: AppColors.surfaceContainer,
        );

        final showCustomerCredit =
            _creditEnabled || stats.totalCustomerCreditDebts > 0;
        final alertCustomerCredit = _MiniAlertCard(
          title: 'مديونيات العملاء الآجلة',
          countText: '${Money(stats.totalCustomerCreditDebts).toDisplay()} ج.م',
          subtext: 'مستحقات على الحساب الآجل',
          icon: Icons.account_balance_wallet_rounded,
          color: stats.totalCustomerCreditDebts > 0
              ? AppColors.primary
              : AppColors.onSurfaceVariant,
          bgColor: stats.totalCustomerCreditDebts > 0
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.surfaceContainer,
        );

        final alertReturns = _MiniAlertCard(
          title: 'مرتجعات اليوم',
          countText: '${Money(stats.todayReturnsTotal).toDisplay()} ج.م',
          subtext: '${stats.todayReturnsCount} عملية مرتجع',
          icon: Icons.assignment_return_rounded,
          color: stats.todayReturnsCount > 0
              ? AppColors.secondary
              : AppColors.onSurfaceVariant,
          bgColor: stats.todayReturnsCount > 0
              ? AppColors.secondary.withValues(alpha: 0.08)
              : AppColors.surfaceContainer,
        );

        final visibleCards = <Widget>[
          alertStock,
          if (showInstallments) alertInstallments,
          if (showSuppliers) alertSuppliers,
          if (showCustomerCredit) alertCustomerCredit,
          alertReturns,
        ];

        if (constraints.maxWidth < 700) {
          final rows = <Widget>[];
          for (var i = 0; i < visibleCards.length; i += 2) {
            final chunk = visibleCards.sublist(
              i,
              (i + 2).clamp(0, visibleCards.length),
            );
            if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
            rows.add(
              Row(
                children: [
                  for (int j = 0; j < chunk.length; j++) ...[
                    if (j > 0) const SizedBox(width: 10),
                    Expanded(child: chunk[j]),
                  ],
                ],
              ),
            );
          }
          return Column(children: rows);
        } else if (constraints.maxWidth < 1100) {
          final half = (visibleCards.length / 2).ceil();
          final firstRow = visibleCards.sublist(0, half);
          final secondRow = visibleCards.sublist(half);
          return Column(
            children: [
              Row(
                children: [
                  for (int i = 0; i < firstRow.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(child: firstRow[i]),
                  ],
                ],
              ),
              if (secondRow.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (int i = 0; i < secondRow.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: secondRow[i]),
                    ],
                  ],
                ),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (int i = 0; i < visibleCards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: visibleCards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildLowStockSection(DashboardStatsEntity stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.notification_important_rounded,
              color: AppColors.warning,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'تنبيهات الأصناف منخفضة المخزون',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warningContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '${stats.lowStockVariants.length} أصناف تحتاج للتوريد',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...stats.lowStockVariants.map(
          (v) => Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warningContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                ),
              ),
              title: Text(
                '${v.productName} (${v.color} - مقاس ${v.size})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('كود الصنف: ${v.sku}'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'الرصيد: ${v.quantity} / الحد الأدنى: ${v.minStock}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final bool isHighlighted;
  final double? growthPercent;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.isHighlighted = false,
    this.growthPercent,
  });

  @override
  Widget build(BuildContext context) {
    final g = growthPercent;
    return Card(
      elevation: isHighlighted ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isHighlighted
            ? BorderSide(color: color.withValues(alpha: 0.3), width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isHighlighted ? color : AppColors.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (g != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: g >= 0
                          ? AppColors.successContainer
                          : AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${g >= 0 ? '+' : ''}${g.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: g >= 0 ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniAlertCard extends StatelessWidget {
  final String title;
  final String countText;
  final String subtext;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _MiniAlertCard({
    required this.title,
    required this.countText,
    required this.subtext,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  countText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtext,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
