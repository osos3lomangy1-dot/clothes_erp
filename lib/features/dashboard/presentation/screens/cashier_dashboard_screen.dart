import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../pos/presentation/screens/pos_screen.dart';
import '../../../products/presentation/screens/product_list_screen.dart';
import '../../../inventory/presentation/screens/inventory_screen.dart';

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
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'لوحة تحكم الكاشير',
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.point_of_sale_rounded, size: 50, color: AppColors.primary),
                ),
                const SizedBox(height: 16),
                const Text(
                  'أهلاً بك في نقطة البيع!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  'اختر الشاشة المطلوبة لبدء العمليات',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _NavCard(
                      icon: Icons.point_of_sale_rounded,
                      title: 'شاشة الكاشير (POS)',
                      subtitle: 'بدء عمليات البيع وإصدار الفواتير',
                      color: AppColors.primary,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const PosScreen()),
                      ),
                    ),
                    _NavCard(
                      icon: Icons.inventory_2_rounded,
                      title: 'دليل المنتجات',
                      subtitle: 'استعراض الأصناف والمقاسات والأسعار',
                      color: Colors.blue.shade700,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const ProductListScreen()),
                      ),
                    ),
                    _NavCard(
                      icon: Icons.warehouse_rounded,
                      title: 'إدارة المخزون',
                      subtitle: 'فحص كميات وتوريد البضاعة',
                      color: Colors.teal.shade700,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const InventoryScreen()),
                      ),
                    ),
                  ],
                ),
              ],
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
