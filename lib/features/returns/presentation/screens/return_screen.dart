import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../domain/entities/return_entity.dart';
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
  final _dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

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
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: Navigator.canPop(context)
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
                    tooltip: 'رجوع',
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : null,
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إدارة مرتجعات المبيعات',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
                ),
                Text(
                  'إرجاع الأصناف، استرداد المبالغ للدرج، ومتابعة سجل الفواتير المرتجعة',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            bottom: const TabBar(
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              tabs: [
                Tab(
                  icon: Icon(Icons.assignment_return_rounded),
                  text: 'إجراء مرتجع جديد',
                ),
                Tab(
                  icon: Icon(Icons.receipt_long_rounded),
                  text: 'سجل فواتير المرتجعات',
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
                _searchCtrl.clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.green,
                    content: Text(state.successMessage!),
                  ),
                );
              }
            },
            builder: (context, state) {
              return TabBarView(
                children: [
                  _buildNewReturnTab(context, state),
                  _buildReturnsHistoryTab(context, state),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: NEW RETURN
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNewReturnTab(BuildContext context, ReturnsState state) {
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
                    labelText: 'ابحث برقم الفاتورة (مثال: #S101 أو المعرف)...',
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
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => context.read<ReturnsCubit>().searchSale(_searchCtrl.text),
                icon: const Icon(Icons.search_rounded, color: Colors.white, size: 18),
                label: const Text('بحث', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              if (state.selectedSale != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    _searchCtrl.clear();
                    context.read<ReturnsCubit>().clearSelection();
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('الرجوع للقائمة'),
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
              'لا توجد فواتير بيع قابلة للإرجاع حالياً',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'الفواتير المرتجعة بالكامل لا تظهر هنا منعاً للتكرار، ويمكنك مراجعتها في تاب "سجل فواتير المرتجعات"',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اختر فاتورة بيع لإرجاع أصناف منها:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.onSurface),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: state.recentSales.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final sale = state.recentSales[index];
              final dateStr = _dateFormat.format(sale.date);

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
                    'فاتورة #${sale.id.length > 8 ? sale.id.substring(0, 8) : sale.id} • الإجمالي: ${Money(sale.total.toInt()).toDisplay()} ج.م',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'التاريخ: $dateStr • طريقة الدفع: ${sale.paymentMethod}',
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
    final dateStr = _dateFormat.format(sale.date);

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
                      'الفاتورة المحددة: #${sale.id.length > 8 ? sale.id.substring(0, 8) : sale.id}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'التاريخ: $dateStr • طريقة الدفع: ${sale.paymentMethod}',
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
            'حدد كميات الأصناف المراد إرجاعها (الأصناف المرتجعة سابقاً محددة تلقائياً):',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.onSurface),
          ),
          const SizedBox(height: 8),
          ...state.returnItems.map((item) {
            final isFullyReturned = item.maxQty == 0;

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: isFullyReturned ? Colors.grey.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isFullyReturned ? Colors.red.shade200 : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName.isNotEmpty ? item.productName : item.variantId,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isFullyReturned ? Colors.grey.shade600 : Colors.black87,
                          ),
                        ),
                        Text(
                          '${item.color} - مقاس ${item.size} • سعر القطعة: ${Money(item.refundUnitPrice).toDisplay()} ج.م',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        if (isFullyReturned)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'تم إرجاع هذا الصنف بالكامل سابقاً',
                                style: TextStyle(fontSize: 11, color: Colors.red.shade800, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                        else
                          Text(
                            'الكمية المتبقية القابلة للإرجاع: ${item.maxQty} قطعة',
                            style: TextStyle(fontSize: 11, color: Colors.blue.shade800, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                  if (!isFullyReturned) ...[
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
                      const Text('إجمالي المبلغ المسترد (يخصم من الدرج):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        '${Money(state.totalRefund).toDisplay()} ج.م',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary),
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
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.assignment_return_rounded, color: Colors.white),
                      label: state.isProcessing
                          ? const Text(
                              'جارِ معالجة المرتجع...',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            )
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

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: RETURNS HISTORY
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildReturnsHistoryTab(BuildContext context, ReturnsState state) {
    if (state.returnsHistory.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => context.read<ReturnsCubit>().loadReturnsHistory(),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.assignment_return_outlined, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text(
                      'لا توجد فواتير مرتجعات مسجلة حتى الآن',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'عند تنفيذ أي عملية إرجاع ستظهر تفاصيلها وسجلها هنا تلقائياً',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<ReturnsCubit>().loadReturnsHistory(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: state.returnsHistory.length,
        separatorBuilder: (_, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final ret = state.returnsHistory[index];
          return _buildReturnHistoryCard(ret);
        },
      ),
    );
  }

  Widget _buildReturnHistoryCard(ReturnEntity ret) {
    final dateStr = _dateFormat.format(ret.date);
    final isCash = ret.paymentMethod.toLowerCase().contains('cash') || ret.paymentMethod.contains('كاش');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ExpansionTile(
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.assignment_return_rounded, color: Colors.red.shade700),
        ),
        title: Row(
          children: [
            Text(
              'مرتجع #${ret.id.length > 8 ? ret.id.substring(0, 8) : ret.id}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(width: 8),
            if (ret.saleShortRef != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'فاتورة الأصل: #${ret.saleShortRef}',
                  style: TextStyle(color: Colors.blue.shade900, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            const Spacer(),
            Text(
              '-${Money(ret.refundAmount).toDisplay()} ج.م',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red.shade700),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Row(
            children: [
              Text(
                dateStr,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
              const SizedBox(width: 12),
              Text(
                'بواسطة: ${ret.cashierName ?? ret.cashierId}',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isCash ? Colors.green.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isCash ? 'مسترد نقداً (خصم من الدرج)' : 'مسترد إلكتروني',
                  style: TextStyle(
                    color: isCash ? Colors.green.shade800 : Colors.blue.shade800,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'سبب المرتجع: ${ret.reason}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'الأصناف المرتجعة للمخزن:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                ...ret.items.map((it) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '• ${it.productName} (${it.color} - مقاس ${it.size}) × ${it.qty} قطعة',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '${Money(it.refundUnitPrice * it.qty).toDisplay()} ج.م',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
