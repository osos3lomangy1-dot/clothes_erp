import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_feedback.dart';

import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../inventory/domain/entities/goods_receipt_entity.dart';
import '../../../inventory/presentation/cubits/goods_receipt_cubit.dart';
import '../../../inventory/presentation/cubits/goods_receipt_state.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/entities/supplier_entity.dart';
import '../cubits/purchases_cubit.dart';
import '../cubits/purchases_state.dart';
import '../cubits/suppliers_cubit.dart';
import '../cubits/suppliers_state.dart';
import '../widgets/supplier_form_dialog.dart';
import '../widgets/supplier_payment_dialog.dart';
import 'create_purchase_screen.dart';

class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<PurchasesCubit>()..loadPurchases()),
        BlocProvider(create: (_) => getIt<SuppliersCubit>()..loadSuppliers()),
        BlocProvider(create: (_) => getIt<GoodsReceiptCubit>()..loadGoodsReceipts(status: 'pending')),
      ],
      child: const _PurchasesView(),
    );
  }
}

class _PurchasesView extends StatefulWidget {
  const _PurchasesView();

  @override
  State<_PurchasesView> createState() => _PurchasesViewState();
}

class _PurchasesViewState extends State<_PurchasesView> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isCreatingInvoice = false;
  GoodsReceiptEntity? _selectedReceiptForInvoice;

  void _openCreatePurchase({GoodsReceiptEntity? fromReceipt}) {
    setState(() {
      _selectedReceiptForInvoice = fromReceipt;
      _isCreatingInvoice = true;
    });
  }

  void _openAddSupplierDialog() {
    showDialog(
      context: context,
      builder: (_) => SupplierFormDialog(
        onSave: ({
          required String name,
          String? phone,
          String? companyName,
          String? address,
        }) async {
          final cubit = context.read<SuppliersCubit>();
          final created = await cubit.addSupplier(
            name: name,
            phone: phone,
            companyName: companyName,
            address: address,
          );
          if (created == null) {
            return cubit.state.errorMessage ?? 'تعذر إضافة المورد. يرجى إعادة المحاولة.';
          }
          if (mounted) {
            _showToast('تمت إضافة المورد بنجاح');
          }
          return null;
        },
      ),
    );
  }

  void _openEditSupplierDialog(SupplierEntity s) {
    showDialog(
      context: context,
      builder: (_) => SupplierFormDialog(
        supplier: s,
        onSave: ({
          required String name,
          String? phone,
          String? companyName,
          String? address,
        }) async {
          final cubit = context.read<SuppliersCubit>();
          final success = await cubit.updateSupplier(
            id: s.id,
            name: name,
            phone: phone,
            companyName: companyName,
            address: address,
          );
          if (!success) {
            return cubit.state.errorMessage ?? 'تعذر تعديل بيانات المورد.';
          }
          if (mounted) {
            _showToast('تم تعديل بيانات المورد بنجاح');
          }
          return null;
        },
      ),
    );
  }

  void _openPaymentDialog(SupplierEntity supplier, {PurchaseEntity? purchase}) {
    final authState = context.read<AuthCubit>().state;
    String currentUserId = 'system';
    if (authState is AuthAuthenticated) {
      currentUserId = authState.user.name;
    }

    showDialog(
      context: context,
      builder: (_) => SupplierPaymentDialog(
        supplier: supplier,
        purchaseId: purchase?.id,
        purchaseInvoiceNumber: purchase?.invoiceNumber,
        onSave: ({
          required int amount,
          required DateTime paymentDate,
          required String paymentMethod,
          String? referenceNumber,
          String? notes,
        }) async {
          final cubit = context.read<SuppliersCubit>();
          final payment = await cubit.addSupplierPayment(
            supplierId: supplier.id,
            purchaseId: purchase?.id,
            amount: amount,
            paymentDate: paymentDate,
            paymentMethod: paymentMethod,
            referenceNumber: referenceNumber,
            notes: notes,
            userId: currentUserId,
          );

          if (payment != null && mounted) {
            context.read<PurchasesCubit>().loadPurchases();
            _showToast('تم تسجيل سداد الدفعة وخصمها من الرصيد بنجاح');
          }
        },
      ),
    );
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
                'عذراً، هذه الشاشة مخصصة للإدارة فقط',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'لا يمتلك حساب الكاشير صلاحية الوصول إلى بيانات الموردين والمشتريات والمديونيات.',
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

    if (_isCreatingInvoice) {
      return CreatePurchaseScreen(
        initialGoodsReceipt: _selectedReceiptForInvoice,
        onBack: () => setState(() {
          _isCreatingInvoice = false;
          _selectedReceiptForInvoice = null;
        }),
        onSaved: () {
          setState(() {
            _isCreatingInvoice = false;
            _selectedReceiptForInvoice = null;
          });
          context.read<PurchasesCubit>().loadPurchases();
          context.read<SuppliersCubit>().loadSuppliers();
          context.read<GoodsReceiptCubit>().loadGoodsReceipts(status: 'pending');
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'إدارة المشتريات والموردين',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
          ),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 18),
              label: const Text('فاتورة شراء جديدة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: _openCreatePurchase,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.person_add_rounded, color: AppColors.primary, size: 18),
              label: const Text('إضافة مورد', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _openAddSupplierDialog,
            ),
            const SizedBox(width: 16),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(
                icon: Icon(Icons.receipt_long_rounded),
                text: 'فواتير المشتريات',
              ),
              Tab(
                icon: Icon(Icons.pending_actions_rounded),
                text: 'استلامات معلقة (Pending Receipts)',
              ),
              Tab(
                icon: Icon(Icons.business_rounded),
                text: 'سجل الموردين والمديونيات',
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            // Top Summary Cards Banner
            _buildTopSummaryBanner(),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPurchasesTab(),
                  _buildPendingReceiptsTab(),
                  _buildSuppliersTab(),
                ],
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildTopSummaryBanner() {
    return BlocBuilder<PurchasesCubit, PurchasesState>(
      builder: (context, pState) {
        return BlocBuilder<SuppliersCubit, SuppliersState>(
          builder: (context, sState) {
            final totalPurchases = pState.totalPurchasesAmount / 100.0;
            final totalPaid = pState.totalPaidAmount / 100.0;
            final totalDebt = sState.totalSuppliersDebt / 100.0;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: _summaryCard(
                      title: 'إجمالي المشتريات',
                      value: '${totalPurchases.toStringAsFixed(2)} ج.م',
                      icon: Icons.shopping_bag_outlined,
                      color: Colors.blue.shade700,
                      bgColor: Colors.blue.shade50,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryCard(
                      title: 'المبالغ المسددة',
                      value: '${totalPaid.toStringAsFixed(2)} ج.م',
                      icon: Icons.check_circle_outline_rounded,
                      color: Colors.green.shade700,
                      bgColor: Colors.green.shade50,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _summaryCard(
                      title: 'إجمالي ديون الموردين',
                      value: '${totalDebt.toStringAsFixed(2)} ج.م',
                      icon: Icons.warning_amber_rounded,
                      color: totalDebt > 0 ? Colors.red.shade700 : Colors.grey.shade700,
                      bgColor: totalDebt > 0 ? Colors.red.shade50 : Colors.grey.shade100,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: PURCHASES LIST
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPendingReceiptsTab() {
    return BlocBuilder<GoodsReceiptCubit, GoodsReceiptState>(
      builder: (context, state) {
        if (state.status == GoodsReceiptStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final receipts = state.receipts.where((r) => r.isPending).toList();

        if (receipts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                const Text(
                  'لا توجد استلامات مخزنية معلقة بانتظار الفوترة',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  'كل الشحنات المستلمة من الكاشير تمت مراجعتها وفوترتها للموردين بنجاح.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: receipts.length,
          separatorBuilder: (c, i) => const SizedBox(height: 12),
          itemBuilder: (ctx, idx) {
            final r = receipts[idx];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.pending_actions_rounded, size: 16, color: Colors.orange.shade800),
                            const SizedBox(width: 4),
                            Text(
                              'بانتظار الفوترة (Pending Audit)',
                              style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'شحنة رقم: #${r.id.substring(0, 8)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const Spacer(),
                      Text(
                        'المستلم: ${r.cashierId}',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'تاريخ الاستلام: ${r.receivedAt.year}/${r.receivedAt.month}/${r.receivedAt.day}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                  if (r.notes != null && r.notes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'ملاحظات: ${r.notes}',
                      style: TextStyle(color: Colors.grey.shade800, fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Items summary
                  Text(
                    'الأصناف المستلمة (إجمالي ${r.totalItems} قطعة):',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: r.items.map((it) {
                      return Chip(
                        backgroundColor: Colors.grey.shade100,
                        avatar: const Icon(Icons.checkroom_rounded, size: 16, color: AppColors.primary),
                        label: Text(
                          '${it.productName ?? 'منتج'} (${it.size} - ${it.color}): ${it.quantity} قطع',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 16),
                        label: const Text(
                          'تحويل إلى فاتورة مشتريات (تسجيل التكلفة والمديونية)',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () => _openCreatePurchase(fromReceipt: r),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPurchasesTab() {
    return BlocBuilder<PurchasesCubit, PurchasesState>(
      builder: (context, state) {
        if (state.status == PurchasesStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.status == PurchasesStatus.error) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text(state.errorMessage ?? 'حدث خطأ أثناء تحميل الفواتير'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => context.read<PurchasesCubit>().loadPurchases(),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }

        if (state.purchases.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text('لا توجد فواتير مشتريات مسجلة حتى الآن', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('اضغط على "فاتورة شراء جديدة" لتسجيل بضاعة جديدة وتحديث المخزن', style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white),
                  label: const Text('إنشاء أول فاتورة شراء', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: _openCreatePurchase,
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => context.read<PurchasesCubit>().loadPurchases(),
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: state.purchases.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, idx) {
              final p = state.purchases[idx];
              return _buildPurchaseCard(p);
            },
          ),
        );
      },
    );
  }

  Widget _buildPurchaseCard(PurchaseEntity p) {
    Color statusColor;
    String statusText;
    if (p.paymentStatus == 'paid') {
      statusColor = Colors.green;
      statusText = 'مدفوعة بالكامل';
    } else if (p.paymentStatus == 'partial') {
      statusColor = Colors.amber.shade800;
      statusText = 'سداد جزئي';
    } else {
      statusColor = Colors.red;
      statusText = 'آجل (غير مدفوعة)';
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ExpansionTile(
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.inventory_rounded, color: statusColor),
        ),
        title: Row(
          children: [
            Text(
              p.invoiceNumber != null && p.invoiceNumber!.isNotEmpty
                  ? 'فاتورة #${p.invoiceNumber}'
                  : 'فاتورة شراء #${p.id.substring(0, 8)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusText,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            const Spacer(),
            Text(
              p.formattedTotalAmount,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.onSurface),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(p.supplierName ?? 'مورد غير محدد', style: TextStyle(color: Colors.grey.shade800)),
              const SizedBox(width: 16),
              Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '${p.purchaseDate.year}/${p.purchaseDate.month.toString().padLeft(2, '0')}/${p.purchaseDate.day.toString().padLeft(2, '0')}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const Spacer(),
              Text(
                'المدفوع: ${p.formattedPaidAmount} | المتبقي: ${p.formattedRemainingAmount}',
                style: TextStyle(fontSize: 12, color: p.remainingAmount > 0 ? Colors.red.shade700 : Colors.green),
              ),
            ],
          ),
        ),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.grey.shade50),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الأصناف المشمولة في الفاتورة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                ...p.items.map((it) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.circle, size: 6, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${it.productName ?? 'صنف'} (${it.color ?? ''} - ${it.size ?? ''}) - كود: ${it.sku ?? ''}'),
                          ),
                          Text('${it.qty} قطعة × ${it.formattedCostPrice} = ${it.formattedTotalCost}'),
                        ],
                      ),
                    )),
                if (p.notes != null && p.notes!.isNotEmpty) ...[
                  const Divider(height: 16),
                  Text('ملاحظات: ${p.notes}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                ],
                if (p.remainingAmount > 0) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.payment_rounded, size: 16, color: Colors.white),
                      label: const Text('سداد دفعة من هذه الفاتورة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        final suppliers = context.read<SuppliersCubit>().state.suppliers;
                        final sup = suppliers.firstWhere(
                          (s) => s.id == p.supplierId,
                          orElse: () => SupplierEntity(
                            id: p.supplierId,
                            branchId: p.branchId,
                            name: p.supplierName ?? 'مورد',
                            balance: p.remainingAmount,
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          ),
                        );
                        _openPaymentDialog(sup, purchase: p);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: SUPPLIERS LIST
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSuppliersTab() {
    return BlocBuilder<SuppliersCubit, SuppliersState>(
      builder: (context, state) {
        if (state.status == SuppliersStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final suppliers = state.filteredSuppliers;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'ابحث باسم المورد، اسم المصنع، أو رقم الهاتف...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (v) => context.read<SuppliersCubit>().onSearchChanged(v),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: suppliers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.business_outlined, size: 54, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text('لا يوجد موردون مسجلون', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 6),
                          Text('اضغط على "إضافة مورد" بالأعلى لتسجيل بيانات أول مورد', style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async => context.read<SuppliersCubit>().loadSuppliers(),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        itemCount: suppliers.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, idx) {
                          final s = suppliers[idx];
                          return _buildSupplierCard(s);
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSupplierCard(SupplierEntity s) {
    final hasDebt = s.balance > 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasDebt ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.business_rounded,
                color: hasDebt ? Colors.red.shade700 : Colors.green.shade700,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (s.companyName != null && s.companyName!.isNotEmpty)
                    Text(
                      s.companyName!,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (s.phone != null) ...[
                        Icon(Icons.phone_rounded, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(s.phone!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                        const SizedBox(width: 14),
                      ],
                      if (s.address != null) ...[
                        Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(s.address!, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('المديونية المستحقة:', style: TextStyle(fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  s.formattedBalance,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: hasDebt ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Row(
              children: [
                if (hasDebt)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.payments_outlined, size: 16, color: Colors.white),
                    label: const Text('سداد دفعة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: () => _openPaymentDialog(s),
                  ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'تعديل',
                  icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
                  onPressed: () => _openEditSupplierDialog(s),
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                  onPressed: () async {
                    final confirm = await AppFeedback.confirmDelete(
                      context: context,
                      title: 'تأكيد حذف المورد',
                      content: 'هل تريد حذف المورد "${s.name}"؟ سيتم الاحتفاظ بسجل فواتيره السابقة لأغراض الأرشفة.',
                    );
                    if (confirm && mounted) {
                      final success = await context.read<SuppliersCubit>().deleteSupplier(s.id);
                      if (mounted) {
                        if (success) {
                          AppFeedback.showSuccess(context, 'تم حذف المورد "${s.name}" بنجاح');
                        } else {
                          AppFeedback.showError(context, 'تعذر حذف المورد');
                        }
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

