import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../cubits/delivery_cubit.dart';
import '../cubits/delivery_state.dart';
import '../../domain/entities/delivery_courier_entity.dart';
import '../../domain/entities/delivery_order_entity.dart';
import '../widgets/delivery_checkout_dialog.dart';

class DeliveryOrdersScreen extends StatelessWidget {
  const DeliveryOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<DeliveryCubit>(),
      child: const _DeliveryOrdersView(),
    );
  }
}

class _DeliveryOrdersView extends StatefulWidget {
  const _DeliveryOrdersView();

  @override
  State<_DeliveryOrdersView> createState() => _DeliveryOrdersViewState();
}

void showAddCourierDialog(BuildContext context) {
  final cubit = context.read<DeliveryCubit>();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  String vehicle = 'موتوسيكل';
  final formKey = GlobalKey<FormState>();

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text(
              'إضافة مندوب توصيل (طيار)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم الطيار *',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'رقم الهاتف *',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'رقم الهاتف مطلوب'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: vehicle,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'وسيلة التوصيل',
                      prefixIcon: const Icon(Icons.two_wheeler_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'موتوسيكل',
                        child: Text('موتوسيكل / فيسبا'),
                      ),
                      DropdownMenuItem(
                        value: 'عجلة',
                        child: Text('دراجة / عجلة'),
                      ),
                      DropdownMenuItem(value: 'سيارة', child: Text('سيارة')),
                      DropdownMenuItem(
                        value: 'تروسيكل',
                        child: Text('تروسيكل'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => vehicle = val);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final success = await cubit.addCourier(
                name: nameCtrl.text,
                phone: phoneCtrl.text,
                vehicleType: vehicle,
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تمت إضافة مندوب التوصيل بنجاح'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text('حفظ الطيار'),
          ),
        ],
      ),
    ),
  );
}

class _DeliveryOrdersViewState extends State<_DeliveryOrdersView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openAddCourierDialog(BuildContext context) {
    showAddCourierDialog(context);
  }

  void _openManualOrderDialog(
    BuildContext context,
    List<DeliveryCourierEntity> couriers,
  ) {
    final cubit = context.read<DeliveryCubit>();
    showDialog<DeliveryOrderEntity>(
      context: context,
      builder: (_) => DeliveryCheckoutDialog(
        branchId: 'default',
        orderRef: 'ORD-${DateTime.now().millisecondsSinceEpoch % 10000}',
        orderTotalPiasters: 15000, // sample 150 EGP
        couriers: couriers,
      ),
    ).then((order) {
      if (order != null && context.mounted) {
        cubit.createDeliveryOrder(order);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DeliveryCubit>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.onSurface,
                ),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إدارة وتتبع الدليفري والطيارين',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'توزيع الطلبات الخارجية، متابعة الحالات، وتصفية عهدة الطيارين',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _openAddCourierDialog(context),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('طيار جديد'),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            tooltip: 'تحديث',
            onPressed: () => cubit.init(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.normal,
            fontSize: 13,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.moped_rounded, size: 20),
              text: 'طلبات التوصيل',
            ),
            Tab(
              icon: Icon(Icons.account_balance_wallet_rounded, size: 20),
              text: 'تصفية عهدة الطيارين',
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'طلب توصيل جديد',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          final state = cubit.state;
          _openManualOrderDialog(context, state.couriers);
        },
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DeliveryOrdersListTab(searchCtrl: _searchCtrl),
          const _CourierSettlementTab(),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 1: DELIVERY ORDERS LIST & STATUS TRACKING
// =============================================================================

class _DeliveryOrdersListTab extends StatelessWidget {
  final TextEditingController searchCtrl;

  const _DeliveryOrdersListTab({required this.searchCtrl});

  void _assignCourierModal(
    BuildContext context,
    DeliveryOrderEntity order,
    List<DeliveryCourierEntity> couriers,
  ) {
    final cubit = context.read<DeliveryCubit>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.delivery_dining_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'إسناد الطلب ${order.orderRef} إلى طيار:',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (couriers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    'لا يوجد طيارين مسجلين حالياً. يرجى إضافة طيار أولاً.',
                  ),
                ),
              )
            else
              ...couriers.map(
                (c) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFEAF1F7),
                    child: Icon(
                      Icons.two_wheeler_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'هاتف: ${c.phone} | ${c.vehicleType ?? "موتوسيكل"}',
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                  ),
                  onTap: () {
                    cubit.assignCourier(order.id, c.id, c.name);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تم إسناد الطلب إلى ${c.name} وتغيير حالته إلى (خرج للتوصيل)',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DeliveryCubit>();

    return BlocBuilder<DeliveryCubit, DeliveryState>(
      builder: (context, state) {
        if (state.status == DeliveryStatus.loading && state.orders.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final filteredOrders = state.orders.where((o) {
          final q = state.searchQuery.trim().toLowerCase();
          if (q.isEmpty) return true;
          return o.customerName.toLowerCase().contains(q) ||
              o.customerPhone.contains(q) ||
              o.orderRef.toLowerCase().contains(q) ||
              o.deliveryAddress.toLowerCase().contains(q) ||
              (o.courierName?.toLowerCase().contains(q) ?? false);
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Top Summary Cards
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: 'قيد التجهيز',
                    value: '${state.preparingCount}',
                    icon: Icons.hourglass_top_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: 'مع الطيارين',
                    value: '${state.outForDeliveryCount}',
                    icon: Icons.moped_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: 'تم التسليم',
                    value: '${state.deliveredCount}',
                    icon: Icons.check_circle_outline_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricCard(
                    title: 'كاش في الطريق',
                    value:
                        '${Money(state.activeCashInTransitPiasters).toDisplay()} ج.م',
                    icon: Icons.payments_outlined,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Search Bar & Filter Chips
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    onChanged: cubit.setSearchQuery,
                    decoration: InputDecoration(
                      hintText:
                          'ابحث باسم العميل، الهاتف، العنوان، رقم الطلب، أو الطيار...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                searchCtrl.clear();
                                cubit.setSearchQuery('');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _statusFilterChip(
                          context,
                          label: 'الكل',
                          value: 'all',
                          selected: state.statusFilter == 'all',
                        ),
                        const SizedBox(width: 6),
                        _statusFilterChip(
                          context,
                          label: 'قيد التجهيز بالمحل',
                          value: 'preparing',
                          selected: state.statusFilter == 'preparing',
                        ),
                        const SizedBox(width: 6),
                        _statusFilterChip(
                          context,
                          label: 'خرج مع الطيار',
                          value: 'out_for_delivery',
                          selected: state.statusFilter == 'out_for_delivery',
                        ),
                        const SizedBox(width: 6),
                        _statusFilterChip(
                          context,
                          label: 'تم التسليم',
                          value: 'delivered',
                          selected: state.statusFilter == 'delivered',
                        ),
                        const SizedBox(width: 6),
                        _statusFilterChip(
                          context,
                          label: 'مرتجع / ملغي',
                          value: 'returned',
                          selected: state.statusFilter == 'returned',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Orders list
            if (filteredOrders.isEmpty)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      Icon(Icons.moped_rounded, size: 54, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'لا توجد طلبات توصيل مطابقة للبحث أو الفلتر',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...filteredOrders.map(
                (order) => _DeliveryOrderCard(
                  order: order,
                  onAssignCourier: () =>
                      _assignCourierModal(context, order, state.couriers),
                  onStatusUpdate: (newStatus) =>
                      cubit.updateDeliveryStatus(order.id, newStatus),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _statusFilterChip(
    BuildContext context, {
    required String label,
    required String value,
    required bool selected,
  }) {
    return InkWell(
      onTap: () => context.read<DeliveryCubit>().setStatusFilter(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'Cairo',
            color: selected ? Colors.white : AppColors.onSurface,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _DeliveryOrderCard extends StatelessWidget {
  final DeliveryOrderEntity order;
  final VoidCallback onAssignCourier;
  final void Function(String status) onStatusUpdate;

  const _DeliveryOrderCard({
    required this.order,
    required this.onAssignCourier,
    required this.onStatusUpdate,
  });

  String _statusLabel(String status) {
    switch (status) {
      case 'preparing':
        return 'قيد التجهيز بالمحل';
      case 'out_for_delivery':
        return 'خرج مع الطيار';
      case 'delivered':
        return 'تم التسليم';
      case 'returned':
        return 'مرتجع';
      case 'cancelled':
        return 'ملغي';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _statusLabel(order.status);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Ref, Status Badge, and Time
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Text(
                    order.orderRef,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (order.courierSettled) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Text(
                      'تم توريد الكاش',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  DateFormat('HH:mm - yyyy/MM/dd').format(order.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const Divider(height: 18),

            // Customer & Address Info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            order.customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: order.customerPhone),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم نسخ رقم الهاتف'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.phone_rounded,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  order.customerPhone,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.deliveryAddress,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      if (order.notes != null && order.notes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'ملاحظات: ${order.notes}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Financials & Courier
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'المطلوب: ${Money(order.grandTotalPiasters).toDisplay()} ج.م',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        '(منتجات: ${Money(order.orderTotalPiasters).toDisplay()} + توصيل: ${Money(order.deliveryFeePiasters).toDisplay()})',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        order.courierName != null
                            ? 'الطيار: ${order.courierName}'
                            : 'لم يُعين طيار بعد',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: order.courierName != null
                              ? AppColors.onSurface
                              : Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (order.isPreparing)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    onPressed: onAssignCourier,
                    icon: const Icon(Icons.moped_rounded, size: 16),
                    label: const Text('إرسال مع طيار'),
                  ),
                if (order.isOutForDelivery) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    onPressed: () => onStatusUpdate('delivered'),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('تأكيد التسليم والتحصيل'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                    onPressed: () => onStatusUpdate('returned'),
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: const Text('مرتجع'),
                  ),
                ],
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.outlineVariant),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            'طلب #${order.orderRef}\nالعميل: ${order.customerName}\nالهاتف: ${order.customerPhone}\nالعنوان: ${order.deliveryAddress}\nالمطلوب: ${Money(order.grandTotalPiasters).toDisplay()} ج.م',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'تم نسخ بيانات الطلب كاملة جاهزة للواتساب',
                        ),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('نسخ للطيار'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TAB 2: COURIER SETTLEMENT & CASH HANDOVER
// =============================================================================

class _CourierSettlementTab extends StatefulWidget {
  const _CourierSettlementTab();

  @override
  State<_CourierSettlementTab> createState() => _CourierSettlementTabState();
}

class _CourierSettlementTabState extends State<_CourierSettlementTab> {
  String? _selectedCourierId;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DeliveryCubit>();

    return BlocBuilder<DeliveryCubit, DeliveryState>(
      builder: (context, state) {
        final couriers = state.couriers;

        if (couriers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.two_wheeler_rounded,
                  size: 56,
                  color: Colors.grey,
                ),
                const SizedBox(height: 12),
                const Text(
                  'لا يوجد طيارين مسجلين في النظام حتى الآن',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () => showAddCourierDialog(context),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'إضافة طيار جديد',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }

        if (_selectedCourierId == null && couriers.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() => _selectedCourierId = couriers.first.id);
            cubit.loadCourierSettlement(couriers.first.id);
          });
        }

        final summary = state.settlementSummary;

        return Row(
          children: [
            // Couriers List (Left Column)
            SizedBox(
              width: 260,
              child: Card(
                elevation: 0,
                margin: const EdgeInsets.all(12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Colors.black12),
                ),
                child: ListView.separated(
                  itemCount: couriers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final c = couriers[index];
                    final isSelected = c.id == _selectedCourierId;

                    return ListTile(
                      selected: isSelected,
                      selectedTileColor: AppColors.primary.withValues(
                        alpha: 0.08,
                      ),
                      leading: Icon(
                        Icons.two_wheeler_rounded,
                        color: isSelected ? AppColors.primary : Colors.grey,
                      ),
                      title: Text(
                        c.name,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        c.phone,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () {
                        setState(() => _selectedCourierId = c.id);
                        cubit.loadCourierSettlement(c.id);
                      },
                    );
                  },
                ),
              ),
            ),

            // Settlement Details (Right Pane)
            Expanded(
              child: summary == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Courier Header Card
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Colors.black12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AppColors.primary.withValues(
                                    alpha: 0.1,
                                  ),
                                  child: Icon(
                                    Icons.two_wheeler_rounded,
                                    color: AppColors.primary,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'كشف حساب وعهدة: ${summary.courierName}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17,
                                      ),
                                    ),
                                    Text(
                                      'هاتف: ${summary.courierPhone}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                if (summary.unsettledOrders.isNotEmpty)
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Row(
                                            children: [
                                              Icon(
                                                Icons.check_circle_outline,
                                                color: Colors.green,
                                              ),
                                              SizedBox(width: 8),
                                              Text('تأكيد توريد النقدية'),
                                            ],
                                          ),
                                          content: Text(
                                            'هل استلمت بالفعل مبلغ ${Money(summary.totalCashToCollectPiasters).toDisplay()} ج.م نقداً من الطيار "${summary.courierName}" لتوريدها للخزينة؟',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('إلغاء'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.green.shade700,
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text(
                                                'تأكيد التوريد',
                                              ),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirmed == true &&
                                          context.mounted) {
                                        final orderIds = summary.unsettledOrders
                                            .map((o) => o.id)
                                            .toList();
                                        await cubit.settleCourierOrders(
                                          summary.courierId,
                                          orderIds,
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'تمت تصفية وتوريد عهدة الطيار بنجاح!',
                                              ),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.check_circle_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'تصفية وتوريد النقدية للخزينة',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Metric Cards
                        Row(
                          children: [
                            Expanded(
                              child: _MetricCard(
                                title: 'نقدية محصلة مع الطيار',
                                value:
                                    '${Money(summary.totalCashToCollectPiasters).toDisplay()} ج.م',
                                icon: Icons.payments_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MetricCard(
                                title: 'طلبات مسلمة غير مصفاة',
                                value: '${summary.unsettledOrders.length} طلب',
                                icon: Icons.receipt_long_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MetricCard(
                                title: 'إجمالي أجور التوصيل',
                                value:
                                    '${Money(summary.totalDeliveryFeesPiasters).toDisplay()} ج.م',
                                icon: Icons.moped_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Unsettled orders table
                        const Text(
                          'تفاصيل الطلبات المسلمة بانتظار توريد النقدية من الطيار:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),

                        if (summary.unsettledOrders.isEmpty)
                          Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Center(
                                child: Text(
                                  'جميع طلبات هذا الطيار مصفاة وموردة بالكامل لا توجد عهدة معلقة.',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          ...summary.unsettledOrders.map(
                            (o) => Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(color: Colors.black12),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  Icons.receipt_rounded,
                                  color: AppColors.primary,
                                ),
                                title: Text(
                                  'طلب #${o.orderRef} - العميل: ${o.customerName}',
                                ),
                                subtitle: Text('العنوان: ${o.deliveryAddress}'),
                                trailing: Text(
                                  '${Money(o.grandTotalPiasters).toDisplay()} ج.م',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================================
// REUSABLE METRIC CARD
// =============================================================================

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
