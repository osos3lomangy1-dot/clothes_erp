import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/excel_service.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../cubits/reports_cubit.dart';
import '../cubits/reports_state.dart';
import '../widgets/financial_comparison_bar_chart.dart';
import '../widgets/payment_method_pie_chart.dart';
import '../widgets/top_selling_products_widget.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
  }

  String _formatPaymentMethod(String method) {
    final lower = method.toLowerCase();
    if (lower == 'cash' || lower == 'نقدي') return 'نقدي (كاش)';
    if (lower == 'card' || lower == 'visa' || lower == 'فيزا') {
      return 'بطاقة / فيزا';
    }
    return method;
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final isCashier = authState is AuthAuthenticated && authState.user.role.toLowerCase() == 'cashier';

    if (isCashier) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                  onPressed: () => Navigator.pop(context),
                )
              : null,
          title: const Text(
            'غير مصرح بالدخول',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'عذراً، تقارير الأرباح والتكاليف مخصصة للإدارة فقط',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'لا يمتلك حساب الكاشير صلاحية الاطلاع على تكاليف البضاعة وصافي أرباح المحل.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              if (Navigator.canPop(context))
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  label: const Text('رجوع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),
        ),
      );
    }

    return BlocProvider(
      create: (context) =>
          getIt<ReportsCubit>()..loadReport(_dateRange!.start, _dateRange!.end),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تقارير المبيعات والأرباح',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.onSurface,
                ),
              ),
              Text(
                'تحليل الإيرادات والتكاليف وصافي الربح وطرق الدفع',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: PopupMenuButton<String>(
                tooltip: 'تصدير التقارير إلى ملف إكسيل',
                onSelected: (val) async {
                  final messenger = ScaffoldMessenger.of(context);
                  final excelService = ExcelService();
                  String? path;
                  try {
                    if (val == 'sales') {
                      path = await excelService.exportSales(
                        from: _dateRange?.start,
                        to: _dateRange?.end,
                      );
                    } else if (val == 'expenses') {
                      path = await excelService.exportExpenses(
                        from: _dateRange?.start,
                        to: _dateRange?.end,
                      );
                    } else if (val == 'all') {
                      path = await excelService.exportComprehensiveFinancialReport(
                        from: _dateRange?.start,
                        to: _dateRange?.end,
                      );
                    }
                    if (path != null) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('تم تصدير ملف الإكسيل بنجاح:\n$path'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('خطأ أثناء التصدير: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'sales',
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text('تصدير تقرير المبيعات (.xlsx)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'expenses',
                    child: Row(
                      children: [
                        Icon(Icons.outbox_rounded, color: AppColors.error, size: 20),
                        SizedBox(width: 8),
                        Text('تصدير تقرير المصروفات (.xlsx)'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'all',
                    child: Row(
                      children: [
                        Icon(Icons.auto_graph_rounded, color: Colors.teal, size: 20),
                        SizedBox(width: 8),
                        Text('تصدير تقرير مالي شامل (.xlsx)', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.table_view_rounded, color: Colors.green, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'تصدير إكسيل',
                        style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, color: Colors.green.shade800, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Builder(
          builder: (context) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.date_range_rounded,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _dateRange != null
                                ? 'الفترة: ${_dateRange!.start.toLocal().toString().split(' ')[0]} إلى ${_dateRange!.end.toLocal().toString().split(' ')[0]}'
                                : 'اختر الفترة الزمنية للتقرير',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                              initialDateRange: _dateRange,
                            );
                            if (picked != null) {
                              setState(() => _dateRange = picked);
                              if (context.mounted) {
                                context.read<ReportsCubit>().loadReport(
                                  picked.start,
                                  picked.end,
                                );
                              }
                            }
                          },
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          label: const Text(
                            'تغيير الفترة',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: BlocBuilder<ReportsCubit, ReportsState>(
                      builder: (context, state) {
                        if (state is ReportsLoading) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (state is ReportsError) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'خطأ: ${state.message}',
                                  style: const TextStyle(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                  ),
                                  onPressed: () =>
                                      context.read<ReportsCubit>().loadReport(
                                        _dateRange!.start,
                                        _dateRange!.end,
                                      ),
                                  child: const Text(
                                    'إعادة المحاولة',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        if (state is ReportsLoaded) {
                          final report = state.report;
                          return ListView(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _ReportCard(
                                      title: 'إجمالي المبيعات',
                                      value:
                                          '${Money(report.totalRevenue).toDisplay()} ج.م',
                                      icon: Icons.monetization_on_rounded,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ReportCard(
                                      title: 'تكلفة البضاعة',
                                      value:
                                          '${Money(report.totalCost).toDisplay()} ج.م',
                                      icon: Icons.shopping_bag_outlined,
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ReportCard(
                                      title: 'المصروفات',
                                      value:
                                          '${Money(report.totalExpenses).toDisplay()} ج.م',
                                      icon: Icons.outbox_rounded,
                                      color: AppColors.error,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ReportCard(
                                      title: 'صافي الربح الفعلي',
                                      value:
                                          '${Money(report.netProfit).toDisplay()} ج.م',
                                      icon: Icons.trending_up_rounded,
                                      color: report.netProfit >= 0
                                          ? AppColors.primary
                                          : AppColors.error,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ReportCard(
                                      title: 'عدد الفواتير',
                                      value: '${report.totalTransactions}',
                                      icon: Icons.receipt_long_rounded,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              FinancialComparisonBarChart(
                                totalRevenue: report.totalRevenue,
                                totalCost: report.totalCost,
                                totalExpenses: report.totalExpenses,
                                netProfit: report.netProfit,
                              ),
                              const SizedBox(height: 20),
                              PaymentMethodPieChart(
                                breakdown: report.paymentMethodBreakdown,
                              ),
                              const SizedBox(height: 20),
                              TopSellingProductsWidget(
                                products: report.topSellingProducts,
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'تفصيل المبيعات بحسب طريقة الدفع',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (report.paymentMethodBreakdown.isEmpty)
                                Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Padding(
                                    padding: EdgeInsets.all(20.0),
                                    child: Center(
                                      child: Text(
                                        'لا توجد عمليات بيع مسجلة خلال الفترة المحددة.',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                ...report.paymentMethodBreakdown.entries.map(
                                  (e) => Card(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Icon(
                                          e.key.toLowerCase().contains(
                                                    'cash',
                                                  ) ||
                                                  e.key.contains('كاش')
                                              ? Icons.money_rounded
                                              : Icons.credit_card_rounded,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      title: Text(
                                        _formatPaymentMethod(e.key),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      trailing: Text(
                                        '${Money(e.value).toDisplay()} ج.م',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ReportCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
