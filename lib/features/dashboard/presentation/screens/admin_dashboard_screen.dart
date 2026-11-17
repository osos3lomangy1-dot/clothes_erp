import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/layout/main_layout.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../reports/presentation/screens/reports_screen.dart';
import '../../../reports/presentation/widgets/payment_method_pie_chart.dart';
import '../../../reports/presentation/widgets/top_selling_products_widget.dart';
import '../cubits/dashboard_cubit.dart';
import '../cubits/dashboard_state.dart';
import '../../domain/entities/dashboard_stats_entity.dart';
import '../widgets/hourly_sales_chart.dart';
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

class _AdminDashboardView extends StatefulWidget {
  const _AdminDashboardView();

  @override
  State<_AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<_AdminDashboardView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService.checkForUpdate(context);
      }
    });
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
            children: [
              Text(
                'لوحة تحكم المدير العام',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
              ),
              Text(
                'نبض النشاط اللحظي، السيولة، والأرباح اليومية',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                icon: const Icon(Icons.analytics_rounded, color: Colors.white, size: 18),
                label: const Text(
                  'التقرير المالي الشامل',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportsScreen()),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'التحقق من التحديثات',
              onPressed: () => AppUpdateService.checkForUpdate(
                context,
                forceCheck: true,
                showNoUpdateToast: true,
              ),
              icon: const Icon(Icons.system_update_rounded, color: AppColors.primary),
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: () => context.read<AuthCubit>().logout(),
              icon: const Icon(Icons.logout_rounded, color: AppColors.error),
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
                    const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text(
                      state.errorMessage ?? 'حدث خطأ أثناء تحميل البيانات',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: () => context.read<DashboardCubit>().loadStats(),
                      child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
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
                  // 1. Executive Financial Row (4 Cards)
                  _buildExecutiveKpiRow(context, stats),

                  const SizedBox(height: 16),

                  // 2. Action & Risk Alerts Center (4 Compact Cards)
                  _buildActionCenterRow(context, stats),

                  const SizedBox(height: 24),

                  // 3. Middle Section: Weekly Trend & Payment Methods
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: WeeklySalesChart(points: stats.last7DaysSales),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: PaymentMethodPieChart(breakdown: stats.todayPaymentBreakdown),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          WeeklySalesChart(points: stats.last7DaysSales),
                          const SizedBox(height: 16),
                          PaymentMethodPieChart(breakdown: stats.todayPaymentBreakdown),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // 4. Lower Section: Hourly Today Activity & Best Sellers
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: HourlySalesChart(hourlyPoints: stats.todayHourlySales),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: TopSellingProductsWidget(products: stats.todayTopProducts),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          HourlySalesChart(hourlyPoints: stats.todayHourlySales),
                          const SizedBox(height: 16),
                          TopSellingProductsWidget(products: stats.todayTopProducts),
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

  Widget _buildExecutiveKpiRow(BuildContext context, DashboardStatsEntity stats) {
    final avgTicket = stats.todayTransactions > 0
        ? stats.todaySales ~/ stats.todayTransactions
        : 0;

    final cardTodaySales = _KpiCard(
      title: 'مبيعات اليوم',
      value: '${Money(stats.todaySales).toDisplay()} ج.م',
      icon: Icons.monetization_on_rounded,
      color: Colors.green.shade700,
      subtitle: '${stats.todayTransactions} فاتورة صادرة',
    );

    final cardNetProfit = _KpiCard(
      title: 'صافي ربح اليوم (تقديري)',
      value: '${Money(stats.todayEstimatedNetProfit).toDisplay()} ج.م',
      icon: Icons.trending_up_rounded,
      color: stats.todayEstimatedNetProfit >= 0 ? AppColors.primary : AppColors.error,
      subtitle: 'تكلفة البضاعة: ${Money(stats.todayCost).toDisplay()} ج.م',
      isHighlighted: true,
    );

    final cardLiveCash = _KpiCard(
      title: 'السيولة الحالية بالدرج',
      value: '${Money(stats.liveDrawerCash).toDisplay()} ج.م',
      icon: Icons.point_of_sale_rounded,
      color: Colors.blue.shade700,
      subtitle: stats.hasActiveShift
          ? 'الوردية نشطة (${stats.activeCashierName ?? ""})'
          : 'لا توجد وردية مفتوحة حالياً',
    );

    final cardAvgTicket = _KpiCard(
      title: 'متوسط الفاتورة اليوم',
      value: '${Money(avgTicket).toDisplay()} ج.م',
      icon: Icons.receipt_long_rounded,
      color: Colors.purple.shade700,
      subtitle: 'المصروفات: ${Money(stats.todayExpenses).toDisplay()} ج.م',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              Row(children: [Expanded(child: cardTodaySales), const SizedBox(width: 12), Expanded(child: cardNetProfit)]),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: cardLiveCash), const SizedBox(width: 12), Expanded(child: cardAvgTicket)]),
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
          ],
        );
      },
    );
  }

  Widget _buildActionCenterRow(BuildContext context, DashboardStatsEntity stats) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final alertStock = _MiniAlertCard(
          title: 'نواقص المخزون',
          countText: '${stats.lowStockCount} صنف',
          subtext: 'وصل لحد الأمان',
          icon: Icons.warning_amber_rounded,
          color: stats.lowStockCount > 0 ? Colors.orange.shade800 : Colors.grey.shade600,
          bgColor: stats.lowStockCount > 0 ? Colors.orange.shade50 : Colors.grey.shade50,
        );

        final alertInstallments = _MiniAlertCard(
          title: 'أقساط متأخرة',
          countText: '${stats.overdueInstallmentsCount} عقد',
          subtext: '${Money(stats.overdueInstallmentsAmount).toDisplay()} ج.م متأخرة',
          icon: Icons.payments_rounded,
          color: stats.overdueInstallmentsCount > 0 ? AppColors.error : Colors.grey.shade600,
          bgColor: stats.overdueInstallmentsCount > 0 ? Colors.red.shade50 : Colors.grey.shade50,
        );

        final alertSuppliers = _MiniAlertCard(
          title: 'مديونية الموردين',
          countText: '${Money(stats.totalSupplierDebts).toDisplay()} ج.م',
          subtext: 'مستحقات على المحل',
          icon: Icons.local_shipping_rounded,
          color: Colors.blueGrey.shade800,
          bgColor: Colors.blueGrey.shade50,
        );

        final alertReturns = _MiniAlertCard(
          title: 'مرتجعات اليوم',
          countText: '${Money(stats.todayReturnsTotal).toDisplay()} ج.م',
          subtext: '${stats.todayReturnsCount} عملية مرتجع',
          icon: Icons.assignment_return_rounded,
          color: stats.todayReturnsCount > 0 ? Colors.indigo.shade800 : Colors.grey.shade600,
          bgColor: stats.todayReturnsCount > 0 ? Colors.indigo.shade50 : Colors.grey.shade50,
        );

        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              Row(children: [Expanded(child: alertStock), const SizedBox(width: 10), Expanded(child: alertInstallments)]),
              const SizedBox(height: 10),
              Row(children: [Expanded(child: alertSuppliers), const SizedBox(width: 10), Expanded(child: alertReturns)]),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: alertStock),
            const SizedBox(width: 10),
            Expanded(child: alertInstallments),
            const SizedBox(width: 10),
            Expanded(child: alertSuppliers),
            const SizedBox(width: 10),
            Expanded(child: alertReturns),
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
            const Icon(Icons.notification_important_rounded, color: Colors.orange, size: 22),
            const SizedBox(width: 8),
            const Text(
              'تنبيهات الأصناف منخفضة المخزون',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onSurface),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                '${stats.lowStockVariants.length} أصناف تحتاج للتوريد',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...stats.lowStockVariants.map(
          (v) => Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              ),
              title: Text(
                '${v.productName} (${v.color} - مقاس ${v.size})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('كود الصنف: ${v.sku}'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'الرصيد: ${v.quantity} / الحد الأدنى: ${v.minStock}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 12),
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

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isHighlighted ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isHighlighted ? BorderSide(color: color.withValues(alpha: 0.3), width: 1.5) : BorderSide.none,
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
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isHighlighted ? color : AppColors.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
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
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  countText,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
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
