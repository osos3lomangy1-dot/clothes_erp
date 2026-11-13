import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../employees/presentation/cubits/cashier_payroll_cubit.dart';
import '../../../employees/presentation/widgets/cashier_payroll_card.dart';
import '../../../inventory/presentation/screens/blind_receive_screen.dart';
import '../../../pos/presentation/screens/pos_screen.dart';
import '../../../shifts/presentation/screens/shift_screen.dart';


class CashierDashboardScreen extends StatefulWidget {
  const CashierDashboardScreen({super.key});

  @override
  State<CashierDashboardScreen> createState() => _CashierDashboardScreenState();
}

class _CashierDashboardScreenState extends State<CashierDashboardScreen> {
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
    final authState = context.watch<AuthCubit>().state;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final cashierId = user?.id ?? '';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.point_of_sale_rounded, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              user != null ? 'لوحة تحكم الكاشير (${user.name})' : 'لوحة تحكم الكاشير',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'التحقق من التحديثات',
            onPressed: () => AppUpdateService.checkForUpdate(
              context,
              forceCheck: true,
              showNoUpdateToast: true,
            ),
            icon: const Icon(
              Icons.system_update_rounded,
              color: AppColors.primary,
            ),
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: () => context.read<AuthCubit>().logout(),
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
          ),
        ],
      ),
      body: cashierId.isEmpty
          ? const Center(child: Text('يرجى تسجيل الدخول أولاً'))
          : BlocProvider(
              create: (_) => getIt<CashierPayrollCubit>()..loadSummary(cashierId),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Cashier Profile & Payroll Summary Card
                        CashierPayrollCard(employeeId: cashierId),
                        const SizedBox(height: 24),

                        // Section Title: Quick Actions & Navigation
                        const Row(
                          children: [
                            Icon(Icons.dashboard_customize_rounded, color: AppColors.primary, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'الشاشات والعمليات السريعة',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        GridView.count(
                          crossAxisCount: 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          children: [
                            _NavCard(
                              icon: Icons.point_of_sale_rounded,
                              title: 'شاشة البيع (POS)',
                              subtitle: 'بدء عمليات البيع وإصدار الفواتير وتحصيل المدفوعات',
                              color: AppColors.primary,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const PosScreen(),
                                ),
                              ),
                            ),
                            _NavCard(
                              icon: Icons.warehouse_rounded,
                              title: 'استلام بضاعة',
                              subtitle: 'استلام شحنة جديدة وتحديث كميات المخزن فوراً',
                              color: Colors.teal.shade700,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const BlindReceiveScreen(),
                                ),
                              ),
                            ),
                            _NavCard(
                              icon: Icons.lock_clock_rounded,
                              title: 'الورديات وتصفية الدرج',
                              subtitle: 'فتح/إغلاق الوردية ومراجعة المبيعات النقدية',
                              color: Colors.deepPurple.shade700,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const ShiftScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 36),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
