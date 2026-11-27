import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/standard_date_filter_chips.dart';
import '../cubits/delivery_cubit.dart';
import '../cubits/delivery_state.dart';
import '../../domain/entities/delivery_courier_entity.dart';
import '../../domain/entities/delivery_order_entity.dart';
import '../../domain/entities/shipping_company_statement.dart';
import '../widgets/delivery_checkout_dialog.dart';
import '../../../../core/widgets/app_floating_toast.dart';

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
  final accountCtrl = TextEditingController();
  final defaultRateCtrl = TextEditingController();
  final trackingCtrl = TextEditingController();
  String providerType = 'in_house';
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
            Icon(
              providerType == 'in_house'
                  ? Icons.person_add_alt_1_rounded
                  : Icons.local_shipping_outlined,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              providerType == 'in_house'
                  ? 'إضافة مندوب توصيل (طيار)'
                  : 'إضافة شركة / مكتب شحن خارجي',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Provider Type Selector
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.outlineVariant),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setDialogState(() => providerType = 'in_house'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: providerType == 'in_house'
                                    ? AppColors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.moped_rounded,
                                    size: 16,
                                    color: providerType == 'in_house'
                                        ? Colors.white
                                        : AppColors.onSurface,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'طيار المحل (داخلي)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: providerType == 'in_house'
                                          ? Colors.white
                                          : AppColors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: InkWell(
                            onTap: () => setDialogState(() => providerType = 'shipping_company'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: providerType == 'shipping_company'
                                    ? AppColors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.business_rounded,
                                    size: 16,
                                    color: providerType == 'shipping_company'
                                        ? Colors.white
                                        : AppColors.onSurface,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'شركة شحن خارجي',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: providerType == 'shipping_company'
                                          ? Colors.white
                                          : AppColors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Name field
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: providerType == 'in_house'
                          ? 'اسم الطيار *'
                          : 'اسم شركة / مكتب الشحن *',
                      prefixIcon: Icon(
                        providerType == 'in_house'
                            ? Icons.person_outline_rounded
                            : Icons.business_outlined,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                  ),
                  const SizedBox(height: 12),

                  // Phone field
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: providerType == 'in_house'
                          ? 'رقم الهاتف *'
                          : 'رقم خدمة العملاء / المندوب *',
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

                  if (providerType == 'in_house') ...[
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
                  ] else ...[
                    // Shipping Company specific fields
                    TextFormField(
                      controller: accountCtrl,
                      decoration: InputDecoration(
                        labelText: 'رقم حساب المتجر لدى الشركة (اختياري)',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        hintText: 'مثال: ACC-99482',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: defaultRateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'التكلفة القياسية للشحنة (ج.م) - اختياري',
                        prefixIcon: const Icon(Icons.attach_money_rounded),
                        hintText: 'مثال: 45.00',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: trackingCtrl,
                      decoration: InputDecoration(
                        labelText: 'قالب رابط التتبع (اختياري)',
                        prefixIcon: const Icon(Icons.link_rounded),
                        hintText: 'https://track.example.com?no={TRACKING}',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
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
              final isShipping = providerType == 'shipping_company';
              final ratePiasters = defaultRateCtrl.text.trim().isNotEmpty
                  ? Money.fromString(defaultRateCtrl.text.trim()).piasters
                  : null;

              final success = await cubit.addCourier(
                name: nameCtrl.text,
                phone: phoneCtrl.text,
                vehicleType: isShipping ? null : vehicle,
                providerType: providerType,
                accountNumber: isShipping && accountCtrl.text.trim().isNotEmpty
                    ? accountCtrl.text.trim()
                    : null,
                defaultRatePiasters: isShipping ? ratePiasters : null,
                trackingUrlTemplate: isShipping && trackingCtrl.text.trim().isNotEmpty
                    ? trackingCtrl.text.trim()
                    : null,
              );
              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (success) {
                  AppFloatingToast.show(
                    context,
                    message: isShipping
                        ? 'تمت إضافة شركة الشحن بنجاح'
                        : 'تمت إضافة مندوب التوصيل بنجاح',
                    type: ToastType.success,
                  );
                }
              }
            },
            child: Text(providerType == 'in_house' ? 'حفظ الطيار' : 'حفظ شركة الشحن'),
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
    _tabController = TabController(length: 3, vsync: this);
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
        orderTotalPiasters: 15000,
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
              'إدارة وتتبع الدليفري وشركات الشحن',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'توزيع الطلبات الخارجية، طياري المحل، بوالص الشحن، وكشوف الحسابات',
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
            label: const Text('جهة توصيل جديدة'),
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
            Tab(
              icon: Icon(Icons.business_rounded, size: 20),
              text: 'كشف حساب شركات الشحن',
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
          const _ShippingCompaniesTab(),
        ],
      ),
    );
  }
}

// =============================================================================
// TAB 1: DELIVERY ORDERS LIST & STATUS TRACKING
// =============================================================================

class _DeliveryOrdersListTab extends StatefulWidget {
  final TextEditingController searchCtrl;

  const _DeliveryOrdersListTab({required this.searchCtrl});

  @override
  State<_DeliveryOrdersListTab> createState() => _DeliveryOrdersListTabState();
}

class _DeliveryOrdersListTabState extends State<_DeliveryOrdersListTab> {
  String _activeDateFilter = 'all';
  DateTimeRange? _customRange;

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
                  'إسناد الطلب ${order.orderRef} إلى جهة توصيل:',
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
                    'لا يوجد طيارين أو شركات شحن مسجلة حالياً.',
                  ),
                ),
              )
            else
              ...couriers.map(
                (c) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: c.isShippingCompany
                        ? const Color(0xFFF1F5F9)
                        : const Color(0xFFEAF1F7),
                    child: Icon(
                      c.isShippingCompany
                          ? Icons.business_rounded
                          : Icons.two_wheeler_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  title: Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    c.isShippingCompany
                        ? 'شركة شحن | هاتف: ${c.phone}${c.accountNumber != null ? " | حساب: ${c.accountNumber}" : ""}'
                        : 'طيار داخلي | هاتف: ${c.phone} | ${c.vehicleType ?? "موتوسيكل"}',
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                  ),
                  onTap: () {
                    cubit.assignCourier(
                      order.id,
                      c.id,
                      c.name,
                    );
                    Navigator.pop(ctx);
                    AppFloatingToast.show(
                      context,
                      message: c.isShippingCompany
                          ? 'تم إسناد الطلب إلى ${c.name} (شركة شحن)'
                          : 'تم إسناد الطلب إلى ${c.name} وتغيير حالته إلى (خرج للتوصيل)',
                      type: ToastType.success,
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
          if (!StandardDateFilterChips.matchesDate(
            o.createdAt,
            _activeDateFilter,
            _customRange,
          )) {
            return false;
          }
          if (state.providerTypeFilter != 'all' &&
              o.providerType != state.providerTypeFilter) {
            return false;
          }
          final q = state.searchQuery.trim().toLowerCase();
          if (q.isEmpty) return true;
          return o.customerName.toLowerCase().contains(q) ||
              o.customerPhone.contains(q) ||
              o.orderRef.toLowerCase().contains(q) ||
              o.deliveryAddress.toLowerCase().contains(q) ||
              (o.courierName?.toLowerCase().contains(q) ?? false) ||
              (o.waybillNumber?.toLowerCase().contains(q) ?? false);
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            StandardDateFilterChips(
              activeFilter: _activeDateFilter,
              customRange: _customRange,
              onFilterChanged: (v) => setState(() => _activeDateFilter = v),
              onCustomRangePicked: (picked) => setState(() {
                _customRange = picked;
                _activeDateFilter = 'custom';
              }),
            ),
            const SizedBox(height: 12),
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
                    title: 'مع الطيارين/الشحن',
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
                    controller: widget.searchCtrl,
                    onChanged: cubit.setSearchQuery,
                    decoration: InputDecoration(
                      hintText:
                          'ابحث باسم العميل، الهاتف، العنوان، رقم الطلب، البوليصة، أو الطيار...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: widget.searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                widget.searchCtrl.clear();
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
                  // Filter Chips (Provider Type + Status)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Provider Filter
                        _filterChip(
                          label: 'الكل',
                          selected: state.providerTypeFilter == 'all',
                          onTap: () => cubit.setProviderTypeFilter('all'),
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          label: 'طيار داخلي',
                          selected: state.providerTypeFilter == 'in_house',
                          onTap: () => cubit.setProviderTypeFilter('in_house'),
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          label: 'شركات الشحن',
                          selected: state.providerTypeFilter == 'shipping_company',
                          onTap: () => cubit.setProviderTypeFilter('shipping_company'),
                        ),
                        const SizedBox(width: 12),
                        Container(height: 20, width: 1, color: Colors.grey.shade300),
                        const SizedBox(width: 12),
                        // Status Filter
                        _filterChip(
                          label: 'كافة الحالات',
                          selected: state.statusFilter == 'all',
                          onTap: () => cubit.setStatusFilter('all'),
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          label: 'قيد التجهيز',
                          selected: state.statusFilter == 'preparing',
                          onTap: () => cubit.setStatusFilter('preparing'),
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          label: 'خرج للتوصيل',
                          selected: state.statusFilter == 'out_for_delivery',
                          onTap: () => cubit.setStatusFilter('out_for_delivery'),
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          label: 'تم التسليم',
                          selected: state.statusFilter == 'delivered',
                          onTap: () => cubit.setStatusFilter('delivered'),
                        ),
                        const SizedBox(width: 6),
                        _filterChip(
                          label: 'مرتجع / ملغي',
                          selected: state.statusFilter == 'returned',
                          onTap: () => cubit.setStatusFilter('returned'),
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
                      Icon(Icons.two_wheeler_rounded, size: 54, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'لا توجد طلبات دليفري جارية حالياً.. جميع الطلبات تم تسليمها وتصفيتها بنجاح',
                        key: Key('delivery_empty_state_text'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 14.5,
                          color: AppColors.onSurfaceVariant,
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

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
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
        return 'خرج مع الطيار / الشحن';
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
            // Top Row: Ref, Provider & Waybill, Status Badge, and Time
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

                // Provider Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: order.isShippingCompany
                        ? Colors.blue.shade50
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: order.isShippingCompany
                          ? Colors.blue.shade300
                          : AppColors.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        order.isShippingCompany
                            ? Icons.business_rounded
                            : Icons.two_wheeler_rounded,
                        size: 13,
                        color: order.isShippingCompany
                            ? Colors.blue.shade800
                            : AppColors.onSurface,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        order.isShippingCompany
                            ? 'شركة شحن: ${order.courierName ?? "غير محدد"}'
                            : 'طيار: ${order.courierName ?? "غير محدد"}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: order.isShippingCompany
                              ? Colors.blue.shade900
                              : AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),

                if (order.waybillNumber != null && order.waybillNumber!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Text(
                      'بوليصة: ${order.waybillNumber}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade800,
                      ),
                    ),
                  ),
                ],

                const SizedBox(width: 6),
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

                if (order.shippingBatchId != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.teal.shade300),
                    ),
                    child: Text(
                      'تسوية مجمعة',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade800,
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
                              AppFloatingToast.show(
                                context,
                                message: 'تم نسخ رقم الهاتف',
                                type: ToastType.info,
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
                        'المطلوب تحصيله (COD): ${Money(order.grandTotalPiasters).toDisplay()} ج.م',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        order.isCustomerDirectShipping
                            ? '(قيمة البضاعة: ${Money(order.orderTotalPiasters).toDisplay()} + الشحن يدفع للشركة: ${Money(order.deliveryFeePiasters).toDisplay()})'
                            : '(منتجات: ${Money(order.orderTotalPiasters).toDisplay()} + توصيل: ${Money(order.deliveryFeePiasters).toDisplay()})',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.end,
                      ),
                      if (order.isShippingCompany) ...[
                        const SizedBox(height: 4),
                        Text(
                          'صافي استحقاق المحل: ${Money(order.netStoreDuePiasters).toDisplay()} ج.م',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        order.courierName != null
                            ? 'الجهة: ${order.courierName}'
                            : 'لم تُحدد جهة توصيل بعد',
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
                    icon: Icon(
                      order.isShippingCompany
                          ? Icons.business_rounded
                          : Icons.moped_rounded,
                      size: 16,
                    ),
                    label: Text(
                      order.isShippingCompany ? 'إرسال لشركة الشحن' : 'إرسال مع طيار',
                    ),
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

                // WhatsApp Dispatch Button
                OutlinedButton.icon(
                  key: Key('delivery_whatsapp_btn_${order.id}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF075E54),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  onPressed: () {
                    final String msg;
                    if (order.isShippingCompany) {
                      final waybillText = (order.waybillNumber != null && order.waybillNumber!.isNotEmpty)
                          ? ' برقم بوليصة ${order.waybillNumber}'
                          : '';
                      msg = 'تم تسليم شحنتك لشركة ${order.courierName ?? "الشحن"}$waybillText للتتبع - المبلغ المطلوب تحصيله (COD): ${Money(order.grandTotalPiasters).toDisplay()} ج.م';
                    } else {
                      msg = 'طلبك في الطريق مع الكابتن ${order.courierName ?? "المندوب"} - المبلغ المطلوب: ${Money(order.grandTotalPiasters).toDisplay()} ج.م';
                    }
                    Clipboard.setData(ClipboardData(text: msg));
                    AppFloatingToast.show(
                      context,
                      message: 'تم نسخ رسالة الواتساب للعميل بنجاح',
                      type: ToastType.success,
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                  label: const Text('واتساب للعميل'),
                ),

                // Copy Details for Courier
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
                    final text = 'طلب #${order.orderRef}\n'
                        'العميل: ${order.customerName}\n'
                        'الهاتف: ${order.customerPhone}\n'
                        'العنوان: ${order.deliveryAddress}\n'
                        'المطلوب: ${Money(order.grandTotalPiasters).toDisplay()} ج.م';
                    Clipboard.setData(ClipboardData(text: text));
                    AppFloatingToast.show(
                      context,
                      message: 'تم نسخ بيانات الطلب كاملة',
                      type: ToastType.info,
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('نسخ البيانات'),
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
        // Only show in-house couriers in this settlement tab
        final inHouseCouriers = state.inHouseCouriers;

        if (inHouseCouriers.isEmpty) {
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
                  'لا يوجد طيارين داخليين مسجلين في النظام حتى الآن',
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

        if (_selectedCourierId == null ||
            !inHouseCouriers.any((c) => c.id == _selectedCourierId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedCourierId = inHouseCouriers.first.id);
              cubit.loadCourierSettlement(inHouseCouriers.first.id);
            }
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
                  itemCount: inHouseCouriers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final c = inHouseCouriers[index];
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
                                              Text('تأكيد توريد النقدية للدرج'),
                                            ],
                                          ),
                                          content: Text(
                                            'هل استلمت بالفعل مبلغ ${Money(summary.totalCashToCollectPiasters).toDisplay()} ج.م نقداً من الطيار "${summary.courierName}" لإيداعها في درج الوردية النشطة؟',
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
                                                'تأكيد الإيداع في الدرج',
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
                                          AppFloatingToast.show(
                                            context,
                                            message:
                                                'تمت تصفية وتوريد عهدة الطيار وإيداعها في درج الوردية بنجاح!',
                                            type: ToastType.success,
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.check_circle_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'تصفية وتوريد النقدية للدرج (Cash-In)',
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
// TAB 3: SHIPPING COMPANIES STATEMENTS & PAYOUTS
// =============================================================================

class _ShippingCompaniesTab extends StatefulWidget {
  const _ShippingCompaniesTab();

  @override
  State<_ShippingCompaniesTab> createState() => _ShippingCompaniesTabState();
}

class _ShippingCompaniesTabState extends State<_ShippingCompaniesTab> {
  String? _selectedCompanyId;

  void _showRecordPayoutDialog(
    BuildContext context,
    DeliveryCourierEntity company,
  ) {
    final cubit = context.read<DeliveryCubit>();
    final amountCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String method = 'bank_transfer';
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
              Icon(Icons.add_card_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'تسجيل دفعة من: ${company.name}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المستلم (ج.م) *',
                      prefixIcon: const Icon(Icons.attach_money_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'المبلغ مطلوب';
                      final val = double.tryParse(v.trim());
                      if (val == null || val <= 0) return 'أدخل مبلغاً صحيحاً';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'طريقة / وجهة الاستلام',
                      prefixIcon: const Icon(Icons.account_balance_wallet_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'bank_transfer',
                        child: Text('تحويل بنكي / حساب الشركة'),
                      ),
                      DropdownMenuItem(
                        value: 'safe',
                        child: Text('الخزينة الرئيسية للمحل'),
                      ),
                      DropdownMenuItem(
                        value: 'wallet',
                        child: Text('محفظة إلكترونية (فودافون كاش / إنستاباي)'),
                      ),
                      DropdownMenuItem(
                        value: 'drawer',
                        child: Text('درج الوردية النشطة'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => method = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: refCtrl,
                    decoration: InputDecoration(
                      labelText: 'رقم الإيصال / الحوالة / العملية (اختياري)',
                      prefixIcon: const Icon(Icons.receipt_long_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      prefixIcon: const Icon(Icons.notes_rounded),
                      hintText: 'مثال: دفعة تحت حساب شحنات الأسبوع',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
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
                final piasters = Money.fromString(amountCtrl.text.trim()).piasters;
                final success = await cubit.recordShippingCompanyPayout(
                  courierId: company.id,
                  amountPiasters: piasters,
                  paymentMethod: method,
                  referenceNumber: refCtrl.text.trim().isNotEmpty
                      ? refCtrl.text.trim()
                      : null,
                  notes: notesCtrl.text.trim().isNotEmpty
                      ? notesCtrl.text.trim()
                      : null,
                );

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (success) {
                    AppFloatingToast.show(
                      context,
                      message: 'تم تسجيل الدفعة وتحديث رصيد شركة الشحن بنجاح',
                      type: ToastType.success,
                    );
                  }
                }
              },
              child: const Text('تسجيل الدفعة'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReconcileBatchDialog(
    BuildContext context,
    DeliveryCourierEntity company,
    ShippingCompanyStatement statement,
  ) {
    final cubit = context.read<DeliveryCubit>();
    final unreconciled = statement.orders
        .where((o) => o.status == 'delivered' && o.shippingBatchId == null)
        .toList();

    if (unreconciled.isEmpty) {
      AppFloatingToast.show(
        context,
        message: 'لا توجد شحنات مسلمة معلقة بانتظار التسوية المجمعة',
        type: ToastType.warning,
      );
      return;
    }

    final batchId = 'BATCH-${DateFormat('yyMMdd').format(DateTime.now())}-${DateTime.now().millisecondsSinceEpoch % 1000}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.fact_check_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Text('إجراء تسوية مجمعة للشحنات'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل تريد إغلاق وتسوية ${unreconciled.length} شحنة مسلمة مع شركة "${company.name}" برقم دفعة مجمعة ($batchId)؟',
            ),
            const SizedBox(height: 10),
            Text(
              'سيتم تثبيت كود الدفعة على هذه البوالص لاعتبارها مسواة في كشوف الحساب.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final orderIds = unreconciled.map((o) => o.id).toList();
              final success = await cubit.reconcileShippingBatch(
                courierId: company.id,
                orderIds: orderIds,
                batchId: batchId,
              );
              if (context.mounted && success) {
                AppFloatingToast.show(
                  context,
                  message: 'تمت التسوية المجمعة بنجاح برقم: $batchId',
                  type: ToastType.success,
                );
              }
            },
            child: const Text('تأكيد التسوية المجمعة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DeliveryCubit>();

    return BlocBuilder<DeliveryCubit, DeliveryState>(
      builder: (context, state) {
        final companies = state.shippingCompanies;

        if (companies.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.business_rounded,
                  size: 56,
                  color: Colors.grey,
                ),
                const SizedBox(height: 12),
                const Text(
                  'لا توجد شركات أو مكاتب شحن مسجلة حتى الآن',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'يمكنك إضافة شركات الشحن المتعاقد معها لتتبع بوالص الشحن وكشوف الحسابات',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () => showAddCourierDialog(context),
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'إضافة شركة شحن جديدة',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }

        if (_selectedCompanyId == null ||
            !companies.any((c) => c.id == _selectedCompanyId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedCompanyId = companies.first.id);
              cubit.loadShippingCompanyStatement(companies.first.id);
            }
          });
        }

        final selectedCompany = companies.firstWhere(
          (c) => c.id == _selectedCompanyId,
          orElse: () => companies.first,
        );

        final statement = state.shippingStatement;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Top Selection & Action Bar
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
                      radius: 22,
                      backgroundColor: Colors.blue.shade50,
                      child: Icon(
                        Icons.business_rounded,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('shipping_company_dropdown'),
                        initialValue: _selectedCompanyId ?? companies.first.id,
                        decoration: InputDecoration(
                          labelText: 'اختر شركة الشحن',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: companies.map((c) {
                          final acc = c.accountNumber != null ? ' (حساب: ${c.accountNumber})' : '';
                          return DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              '${c.name}$acc',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedCompanyId = val);
                            cubit.loadShippingCompanyStatement(val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Record Payout Button
                    FilledButton.icon(
                      key: const Key('record_shipping_payout_btn'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _showRecordPayoutDialog(context, selectedCompany),
                      icon: const Icon(Icons.add_card_rounded, size: 18),
                      label: const Text('تسجيل دفعة مستلمة'),
                    ),
                    const SizedBox(width: 8),

                    // Reconcile Batch Button
                    if (statement != null)
                      OutlinedButton.icon(
                        key: const Key('reconcile_shipping_batch_btn'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.teal.shade800,
                          side: BorderSide(color: Colors.teal.shade400),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _showReconcileBatchDialog(
                          context,
                          selectedCompany,
                          statement,
                        ),
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('إجراء تسوية مجمعة'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Financial Summary Metrics
            if (statement == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      title: 'تحصيل الشحنات المسلمة (COD)',
                      value:
                          '${Money(statement.totalCodDeliveredPiasters).toDisplay()} ج.م',
                      icon: Icons.payments_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricCard(
                      title: 'تكلفة الشحن للشركة',
                      value:
                          '${Money(statement.totalShippingFeesPiasters).toDisplay()} ج.م',
                      icon: Icons.local_shipping_outlined,
                      color: Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricCard(
                      title: 'صافي مستحق للمحل',
                      value:
                          '${Money(statement.totalNetDueToStorePiasters).toDisplay()} ج.م',
                      icon: Icons.account_balance_wallet_rounded,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricCard(
                      title: 'الدفعات المستلمة',
                      value:
                          '${Money(statement.totalPayoutsReceivedPiasters).toDisplay()} ج.م',
                      icon: Icons.check_circle_outline_rounded,
                      color: Colors.teal.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricCard(
                      title: 'الرصيد المعلق المتبقي',
                      value:
                          '${Money(statement.remainingBalancePiasters).toDisplay()} ج.م',
                      icon: Icons.pending_actions_rounded,
                      color: statement.remainingBalancePiasters > 0
                          ? Colors.purple.shade700
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Two Column Layout: Shipments List & Payouts History
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Shipments List
                  Expanded(
                    flex: 3,
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.black12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'سجل بوالص وشحنات الشركة:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${statement.orders.length} شحنة',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            if (statement.orders.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24.0),
                                child: Center(
                                  child: Text('لا توجد شحنات مسندة لهذه الشركة حتى الآن'),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: statement.orders.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final o = statement.orders[index];
                                  final isReconciled = o.shippingBatchId != null;

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    title: Row(
                                      children: [
                                        Text(
                                          '#${o.orderRef}',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        if (o.waybillNumber != null && o.waybillNumber!.isNotEmpty) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'بوليصة: ${o.waybillNumber}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.purple.shade800,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const Spacer(),
                                        Text(
                                          'COD: ${Money(o.grandTotalPiasters).toDisplay()} ج.م',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('العميل: ${o.customerName} | العنوان: ${o.deliveryAddress}'),
                                        Row(
                                          children: [
                                            Text(
                                              'صافي المحل: ${Money(o.netStoreDuePiasters).toDisplay()} ج.م',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade800,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'تكلفة الشحن: ${Money(o.shippingCostPiasters ?? 0).toDisplay()} ج.م',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.orange.shade800,
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isReconciled
                                                    ? Colors.teal.shade50
                                                    : Colors.amber.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isReconciled
                                                      ? Colors.teal.shade200
                                                      : Colors.amber.shade300,
                                                ),
                                              ),
                                              child: Text(
                                                isReconciled
                                                    ? 'مسواة (${o.shippingBatchId})'
                                                    : 'معلق قيد التسوية',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isReconciled
                                                      ? Colors.teal.shade800
                                                      : Colors.amber.shade900,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Right: Payouts History
                  Expanded(
                    flex: 2,
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.black12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.history_rounded, color: Colors.green.shade700, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'سجل الدفعات المستلمة:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${statement.payouts.length} دفعة',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            if (statement.payouts.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24.0),
                                child: Center(
                                  child: Text('لم يتم تسجيل أي دفعات مستلمة بعد'),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: statement.payouts.length,
                                separatorBuilder: (_, _) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final p = statement.payouts[index];
                                  final ref = p.referenceNumber != null ? ' | إيصال: ${p.referenceNumber}' : '';
                                  final notes = p.notes != null ? ' (${p.notes})' : '';
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.green.shade50,
                                      child: Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                    title: Text(
                                      '${Money(p.amountPiasters).toDisplay()} ج.م',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${DateFormat('yyyy/MM/dd').format(p.payoutDate)} | ${p.paymentMethod}$ref$notes',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
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
