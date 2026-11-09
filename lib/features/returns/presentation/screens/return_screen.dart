import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../cubits/returns_cubit.dart';
import '../cubits/returns_state.dart';

class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key});

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final _searchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<ReturnsCubit>()..init(),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'إدارة مرتجعات المبيعات',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
              ),
              Text(
                'البحث عن الفاتورة وإرجاع الأصناف وإعادة الرصيد للمخزن',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        body: BlocConsumer<ReturnsCubit, ReturnsState>(
          listener: (context, state) {
            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.errorMessage!), backgroundColor: AppColors.error),
              );
            }
            if (state.successMessage != null) {
              _reasonCtrl.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: Colors.green,
                  content: Text(state.successMessage!),
                ),
              );
            }
          },
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search bar
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            labelText: 'ابحث برقم الفاتورة أو المعرف...',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                            suffixIcon: _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      context.read<ReturnsCubit>().loadRecentSales();
                                    },
                                  )
                                : null,
                          ),
                          onSubmitted: (val) => context.read<ReturnsCubit>().searchSale(val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => context.read<ReturnsCubit>().searchSale(_searchCtrl.text),
                        child: const Text('بحث', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      if (state.selectedSale != null) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            context.read<ReturnsCubit>().clearSelection();
                          },
                          child: const Text('الرجوع للقائمة'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.isLoading)
                    const Expanded(child: Center(child: CircularProgressIndicator()))
                  else if (state.selectedSale != null)
                    Expanded(child: _buildSaleReturnDetails(context, state))
                  else
                    Expanded(child: _buildRecentSalesList(context, state)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecentSalesList(BuildContext context, ReturnsState state) {
    if (state.errorMessage != null && state.recentSales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              state.errorMessage!,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => context.read<ReturnsCubit>().loadRecentSales(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    if (state.recentSales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'لا توجد فواتير بيع سابقة لإجراء مرتجع عليها',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اختر فاتورة بيع حديثة لإرجاع أصناف منها:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.onSurface),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: state.recentSales.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final sale = state.recentSales[index];
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt_rounded, color: AppColors.primary),
                  ),
                  title: Text(
                    'فاتورة: ${sale.id.length > 8 ? sale.id.substring(0, 8) : sale.id} • الإجمالي: ${Money(sale.total.toInt()).toDisplay()} ج.م',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'التاريخ: ${sale.date.toLocal().toString().split('.')[0]} • الكاشير: ${sale.cashierId}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_left_rounded, color: AppColors.primary),
                  onTap: () => context.read<ReturnsCubit>().selectSale(sale),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSaleReturnDetails(BuildContext context, ReturnsState state) {
    final sale = state.selectedSale!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الفاتورة المحددة: ${sale.id.length > 8 ? sale.id.substring(0, 8) : sale.id}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'التاريخ: ${sale.date.toLocal().toString().split('.')[0]} • طريقة الدفع: ${sale.paymentMethod}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
                Text(
                  'الإجمالي الأصلي: ${Money(sale.total.toInt()).toDisplay()} ج.م',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'حدد كميات الأصناف المراد إرجاعها:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.onSurface),
          ),
          const SizedBox(height: 8),
          ...state.returnItems.map((item) {
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName.isNotEmpty ? item.productName : item.variantId,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${item.color} - مقاس ${item.size} • سعر القطعة: ${Money(item.refundUnitPrice).toDisplay()} ج.م (الحد الأقصى: ${item.maxQty})',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: AppColors.primary),
                        onPressed: item.qty > 0 ? () => context.read<ReturnsCubit>().updateItemQty(item.variantId, item.qty - 1) : null,
                      ),
                      Text('${item.qty}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                        onPressed: item.qty < item.maxQty ? () => context.read<ReturnsCubit>().updateItemQty(item.variantId, item.qty + 1) : null,
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 100,
                    child: Text(
                      '${Money(item.lineTotal).toDisplay()} ج.م',
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          // Refund Summary & Reason
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('إجمالي المبلغ المسترد للعميل:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        '${Money(state.totalRefund).toDisplay()} ج.م',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'سبب الإرجاع (مطلوب) *',
                      border: OutlineInputBorder(),
                      hintText: 'مثال: عيب صناعة، مقاس غير مناسب، رغبة العميل',
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: state.isProcessing || state.totalRefund == 0
                          ? null
                          : () {
                              String cashierId = 'cashier';
                              try {
                                final authState = context.read<AuthCubit>().state;
                                if (authState is AuthAuthenticated) {
                                  cashierId = authState.user.id;
                                }
                              } catch (_) {}

                              context.read<ReturnsCubit>().processReturn(
                                    reason: _reasonCtrl.text,
                                    userId: cashierId,
                                    paymentMethod: sale.paymentMethod,
                                  );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: state.isProcessing
                          ? const SizedBox.shrink()
                          : const Icon(Icons.assignment_return_rounded, color: Colors.white),
                      label: state.isProcessing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'تأكيد وإتمام المرتجع وإعادة البضاعة للمخزن',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
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
