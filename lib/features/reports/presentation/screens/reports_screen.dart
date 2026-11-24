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
import '../../../dashboard/presentation/widgets/hourly_sales_chart.dart';
import '../../domain/services/date_range_presets.dart';
import '../widgets/category_breakdown_donut_chart.dart';
import '../widgets/daily_trend_line_chart.dart';
import '../widgets/financial_comparison_bar_chart.dart';
import '../widgets/most_profitable_products_widget.dart';
import '../widgets/payment_method_pie_chart.dart';
import '../widgets/quick_date_range_bar.dart';
import '../widgets/top_selling_products_widget.dart';
import '../widgets/installments_report_section.dart';
import '../widgets/promotions_report_section.dart';
import 'smart_inventory_reports_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTimeRange? _dateRange;
  QuickDatePreset _selectedPreset = QuickDatePreset.thisMonth;

  @override
  void initState() {
    super.initState();
    _dateRange = DateRangeEngine.resolveRange(QuickDatePreset.thisMonth);
  }

  String _formatPaymentMethod(String method) {
    final lower = method.toLowerCase();
    if (lower == 'cash' || lower == 'نقدي') return 'نقدي (كاش)';
    if (lower == 'card' || lower == 'visa' || lower == 'فيزا') {
      return 'بطاقة / فيزا';
    }
    if (lower == 'credit' || lower == 'آجل' || lower == 'اجل') {
      return 'دفع آجل (حساب عملاء)';
    }
    if (lower == 'installment' || lower == 'تقسيط') {
      return 'أقساط';
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
                          backgroundColor: AppColors.success,
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
                  PopupMenuItem(
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
                  PopupMenuItem(
                    value: 'all',
                    child: Row(
                      children: [
                        Icon(Icons.auto_graph_rounded, color: AppColors.secondary, size: 20),
                        const SizedBox(width: 8),
                        const Text('تصدير تقرير مالي شامل (.xlsx)', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.successContainer,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.table_view_rounded, color: AppColors.success, size: 18),
                      const SizedBox(width: 6),
                      const Text(
                        'تصدير إكسيل',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, color: AppColors.success, size: 18),
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
                  QuickDateRangeBar(
                    selectedPreset: _selectedPreset,
                    onPresetSelected: (preset) async {
                      if (preset == QuickDatePreset.custom) {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: _dateRange,
                        );
                        if (picked != null && context.mounted) {
                          setState(() {
                            _selectedPreset = QuickDatePreset.custom;
                            _dateRange = picked;
                          });
                          context.read<ReportsCubit>().loadReport(
                                picked.start,
                                picked.end,
                              );
                        }
                        return;
                      }
                      final resolved = DateRangeEngine.resolveRange(preset);
                      setState(() {
                        _selectedPreset = preset;
                        _dateRange = resolved;
                      });
                      context.read<ReportsCubit>().loadReport(
                            resolved.start,
                            resolved.end,
                          );
                    },
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
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
                  const SizedBox(height: 12),
                  // Smart Inventory Reports Banner
                  Material(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: AppColors.outlineVariant.withValues(alpha: 0.8),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.inventory_2_rounded, color: AppColors.primary, size: 22),
                      ),
                      title: const Text(
                        'تقارير المخزون الذكية',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: const Text(
                        'اقتراح طلب الشراء (النواقص) • المنتجات الراكدة • كارت حركة كل صنف',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      trailing: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('فتح التقارير'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SmartInventoryReportsScreen(),
                            ),
                          );
                        },
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SmartInventoryReportsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
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
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.analytics_rounded, color: AppColors.primary, size: 24),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'القسم الأول: تقرير الأرباح والخسائر (P&L)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: AppColors.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final cards = [
                                    _ReportCard(
                                      title: 'إجمالي المبيعات',
                                      value:
                                          '${Money(report.totalRevenue).toDisplay()} ج.م',
                                      icon: Icons.monetization_on_rounded,
                                      color: AppColors.primary,
                                      growthPercent: report.revenueGrowthPercent,
                                      subtitle: '${report.totalTransactions} فاتورة',
                                    ),
                                    _ReportCard(
                                      title: 'صافي الربح الحقيقي',
                                      value:
                                          '${Money(report.netProfit).toDisplay()} ج.م',
                                      icon: Icons.trending_up_rounded,
                                      color: report.netProfit >= 0
                                          ? AppColors.secondary
                                          : AppColors.error,
                                      growthPercent: report.netProfitGrowthPercent,
                                      subtitle:
                                          'تكلفة: ${Money(report.totalCost).toDisplay()} | مصروف: ${Money(report.totalExpenses).toDisplay()}',
                                    ),
                                    _ReportCard(
                                      title: 'هامش الربح الصافي %',
                                      value:
                                          '${report.profitMarginPercent.toStringAsFixed(1)}%',
                                      icon: Icons.percent_rounded,
                                      color: AppColors.primary,
                                      subtitle: 'من صافي الإيرادات',
                                    ),
                                    _ReportCard(
                                      title: 'متوسط قيمة الفاتورة (AOV)',
                                      value:
                                          '${Money(report.averageOrderValuePiasters).toDisplay()} ج.م',
                                      icon: Icons.receipt_long_rounded,
                                      color: AppColors.secondary,
                                      subtitle: 'متوسط سلة العميل',
                                    ),
                                    _ReportCard(
                                      title: 'قيمة المخزون بالتكلفة',
                                      value:
                                          '${Money(report.inventoryCostCapitalPiasters).toDisplay()} ج.م',
                                      icon: Icons.inventory_2_outlined,
                                      color: AppColors.primary,
                                      subtitle: 'رأس المال بالمخزن',
                                    ),
                                  ];
                                  if (constraints.maxWidth < 700) {
                                    return Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: cards
                                          .map(
                                            (c) => SizedBox(
                                              width: (constraints.maxWidth - 10) / 2,
                                              child: c,
                                            ),
                                          )
                                          .toList(),
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: cards[0]),
                                      const SizedBox(width: 10),
                                      Expanded(child: cards[1]),
                                      const SizedBox(width: 10),
                                      Expanded(child: cards[2]),
                                      const SizedBox(width: 10),
                                      Expanded(child: cards[3]),
                                      const SizedBox(width: 10),
                                      Expanded(child: cards[4]),
                                    ],
                                  );
                                },
                              ),
                              if (report.totalReturns > 0) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.outlineVariant),
                                  ),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 6,
                                    alignment: WrapAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'إجمالي المرتجعات: ${Money(report.totalReturns).toDisplay()} ج.م',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.error,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        'صافي المبيعات بعد المرتجعات: ${Money(report.netRevenue).toDisplay()} ج.م',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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
                              const SizedBox(height: 20),
                              DailyTrendLineChart(
                                points: report.dailySalesTrend,
                              ),
                              const SizedBox(height: 20),
                              HourlySalesChart(
                                hourlyPoints: report.hourlySalesDistribution,
                              ),
                              const SizedBox(height: 20),
                              CategoryBreakdownDonutChart(
                                categoryBreakdown: report.categoryRevenueBreakdown,
                              ),
                              const SizedBox(height: 20),
                              MostProfitableProductsWidget(
                                products: report.mostProfitableProducts,
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
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                               const SizedBox(height: 24),
                               // Section 2: Cash Flow (التدفقات النقدية والخزينة)
                               Row(
                                 children: [
                                   Container(
                                     padding: const EdgeInsets.all(8),
                                     decoration: BoxDecoration(
                                       color: AppColors.secondary.withValues(alpha: 0.12),
                                       borderRadius: BorderRadius.circular(10),
                                     ),
                                     child: Icon(Icons.account_balance_wallet_rounded, color: AppColors.secondary, size: 24),
                                   ),
                                   const SizedBox(width: 10),
                                   const Expanded(
                                     child: Text(
                                       'القسم الثاني: التدفقات النقدية والخزينة (Cash Flow)',
                                       style: TextStyle(
                                         fontWeight: FontWeight.bold,
                                         fontSize: 18,
                                         color: AppColors.onSurface,
                                       ),
                                     ),
                                   ),
                                 ],
                               ),
                               const SizedBox(height: 12),
                               LayoutBuilder(
                                 builder: (context, constraints) {
                                   final cashCards = [
                                     _ReportCard(
                                       title: 'إجمالي المقبوضات (داخل الخزينة)',
                                       value: '${Money(report.cashFlowIn).toDisplay()} ج.م',
                                       icon: Icons.arrow_downward_rounded,
                                       color: AppColors.success,
                                     ),
                                     _ReportCard(
                                       title: 'إجمالي المدفوعات (خارج الخزينة)',
                                       value: '${Money(report.cashFlowOut).toDisplay()} ج.م',
                                       icon: Icons.arrow_upward_rounded,
                                       color: AppColors.error,
                                     ),
                                     _ReportCard(
                                       title: 'صافي السيولة النقدية (Net Cash)',
                                       value: '${Money(report.netCashFlow).toDisplay()} ج.م',
                                       icon: Icons.account_balance_rounded,
                                       color: report.netCashFlow >= 0 ? AppColors.primary : AppColors.error,
                                     ),
                                   ];
                                   if (constraints.maxWidth < 500) {
                                     return Column(
                                       children: [
                                         cashCards[0],
                                         const SizedBox(height: 10),
                                         cashCards[1],
                                         const SizedBox(height: 10),
                                         cashCards[2],
                                       ],
                                     );
                                   }
                                   return Row(
                                     children: [
                                       Expanded(child: cashCards[0]),
                                       const SizedBox(width: 10),
                                       Expanded(child: cashCards[1]),
                                       const SizedBox(width: 10),
                                       Expanded(child: cashCards[2]),
                                     ],
                                   );
                                 },
                               ),
                               const SizedBox(height: 12),
                               Card(
                                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                 child: Padding(
                                   padding: const EdgeInsets.all(16),
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       const Text(
                                         'تفصيل المقبوضات والمدفوعات بحسب الوسيلة (من حركات النقدية)',
                                         style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                       ),
                                       const Divider(height: 20),
                                       ...['cash', 'card', 'transfer'].map((m) {
                                         final mIn = report.cashFlowInByMethod[m] ?? 0;
                                         final mOut = report.cashFlowOutByMethod[m] ?? 0;
                                         if (mIn == 0 && mOut == 0) return const SizedBox.shrink();
                                         final label = m == 'cash' ? 'نقدي (كاش)' : (m == 'card' ? 'بطاقة / فيزا' : 'تحويل بنكي');
                                         return Padding(
                                           padding: const EdgeInsets.symmetric(vertical: 6),
                                           child: Row(
                                             children: [
                                               Expanded(
                                                 flex: 2,
                                                 child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                                               ),
                                               Expanded(
                                                 flex: 3,
                                                 child: Text('داخل: +${Money(mIn).toDisplay()} ج.م', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                                               ),
                                               Expanded(
                                                 flex: 3,
                                                 child: Text('خارج: -${Money(mOut).toDisplay()} ج.م', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                                               ),
                                               Expanded(
                                                 flex: 2,
                                                 child: Text('الصافي: ${Money(mIn - mOut).toDisplay()} ج.م', style: const TextStyle(fontWeight: FontWeight.bold)),
                                               ),
                                             ],
                                           ),
                                         );
                                       }),
                                     ],
                                   ),
                                 ),
                               ),
                               const SizedBox(height: 20),
                               const InstallmentsReportSection(),
                               const SizedBox(height: 20),
                               PromotionsReportSection(
                                 startDate: _dateRange?.start,
                                 endDate: _dateRange?.end,
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
  final double? growthPercent;
  final String? subtitle;

  const _ReportCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.growthPercent,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final g = growthPercent;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            if (g != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: g >= 0
                      ? AppColors.successContainer
                      : AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      g >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      size: 13,
                      color: g >= 0 ? AppColors.success : AppColors.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${g >= 0 ? '+' : ''}${g.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: g >= 0 ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
