import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/layout/main_layout.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../cubits/dashboard_cubit.dart';
import '../cubits/dashboard_state.dart';
import '../widgets/hourly_sales_chart.dart';
import '../widgets/weekly_sales_chart.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<DashboardCubit>(),
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
          title: const Text(
            'لوحة تحكم المدير العام',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
          ),
          actions: [
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
                    Text(state.errorMessage ?? 'حدث خطأ أثناء تحميل البيانات', style: const TextStyle(fontWeight: FontWeight.bold)),
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
            final stats = state.stats;
            return RefreshIndicator(
              onRefresh: () => context.read<DashboardCubit>().loadStats(),
              child: ListView(
                padding: const EdgeInsets.all(20.0),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          title: 'مبيعات اليوم',
                          value: '${Money(stats?.todaySales ?? 0).toDisplay()} ج.م',
                          icon: Icons.monetization_on_rounded,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _SummaryCard(
                          title: 'عدد فواتير اليوم',
                          value: '${stats?.todayTransactions ?? 0}',
                          icon: Icons.receipt_long_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _SummaryCard(
                          title: 'نواقص المخزون',
                          value: '${stats?.lowStockCount ?? 0}',
                          icon: Icons.warning_amber_rounded,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                  if (stats != null) ...[
                    const SizedBox(height: 24),
                    WeeklySalesChart(points: stats.last7DaysSales),
                    const SizedBox(height: 20),
                    HourlySalesChart(hourlyPoints: stats.todayHourlySales),
                  ],
                  if (stats != null && stats.lowStockVariants.isNotEmpty) ...[
                    const SizedBox(height: 28),
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
                    ...stats.lowStockVariants.map((v) => Card(
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
                        )),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.onSurface)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade600), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
