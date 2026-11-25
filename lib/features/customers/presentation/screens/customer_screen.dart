import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/keyboard_focus_helper.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/show_customer_dialog.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../auth/services/cashier_permissions_service.dart';
import '../../data/services/customer_ledger_service.dart';
import '../../domain/entities/customer_entity.dart';
import '../cubits/customer_cubit.dart';
import '../widgets/customer_profile_dialog.dart';

enum _CustomerFilter { all, retail, wholesale, vip, discounted, withInstallments }

enum _CustomerSort { newest, highestSpend, highestPoints, nameAsc }

class CustomerScreen extends StatelessWidget {
  final CustomerLedgerService? ledgerOverride;

  const CustomerScreen({super.key, this.ledgerOverride});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<CustomerCubit>(),
      child: _CustomerView(ledgerOverride: ledgerOverride),
    );
  }
}

class _CustomerView extends StatefulWidget {
  final CustomerLedgerService? ledgerOverride;

  const _CustomerView({this.ledgerOverride});

  @override
  State<_CustomerView> createState() => _CustomerViewState();
}

class _CustomerViewState extends State<_CustomerView> {
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  _CustomerFilter _filter = _CustomerFilter.all;
  _CustomerSort _sort = _CustomerSort.newest;
  Map<String, CustomerFinancialSummary> _summaries = const {};
  bool _exporting = false;
  bool _installmentsEnabled = false;
  bool _creditEnabled = true;

  CustomerLedgerService? get _ledgerService {
    if (widget.ledgerOverride != null) return widget.ledgerOverride;
    return getIt.isRegistered<CustomerLedgerService>()
        ? getIt<CustomerLedgerService>()
        : null;
  }

  @override
  void initState() {
    super.initState();
    _loadSummaries();
    _checkFeatures();
  }

  Future<void> _checkFeatures() async {
    try {
      if (getIt.isRegistered<FeatureGate>()) {
        final gate = getIt<FeatureGate>();
        final featureOn = await gate.isEnabled(FeatureKeys.installments);
        final meta = await gate.getMeta('payment.installment');
        final instOn = featureOn && (meta != '0');

        final creditMeta = await gate.getMeta('payment.credit');
        final creditOn = creditMeta == null || creditMeta != '0';

        if (mounted) {
          setState(() {
            _installmentsEnabled = instOn;
            _creditEnabled = creditOn;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSummaries() async {
    final svc = _ledgerService;
    if (svc == null) return;
    try {
      final map = await svc.getAllCustomerSummaries();
      if (mounted) {
        setState(() => _summaries = map);
      }
    } catch (_) {}
  }

  bool _isAdmin(BuildContext context) {
    try {
      final auth = context.watch<AuthCubit>().state;
      if (auth is AuthAuthenticated) {
        return auth.user.role.toLowerCase() != 'cashier';
      }
    } catch (_) {}
    return true;
  }

  List<CustomerEntity> _applyFilterAndSort(List<CustomerEntity> raw) {
    var list = raw.where((c) {
      final sum = _summaries[c.id] ?? CustomerFinancialSummary.empty;
      switch (_filter) {
        case _CustomerFilter.all:
          return true;
        case _CustomerFilter.retail:
          return !c.isWholesale && !c.isVip;
        case _CustomerFilter.wholesale:
          return c.isWholesale;
        case _CustomerFilter.vip:
          return c.isVip;
        case _CustomerFilter.discounted:
          return c.discountPercent > 0;
        case _CustomerFilter.withInstallments:
          return sum.activeInstallmentsCount > 0;
      }
    }).toList();

    list.sort((a, b) {
      final sa = _summaries[a.id] ?? CustomerFinancialSummary.empty;
      final sb = _summaries[b.id] ?? CustomerFinancialSummary.empty;
      switch (_sort) {
        case _CustomerSort.newest:
          return b.createdAt.compareTo(a.createdAt);
        case _CustomerSort.highestSpend:
          return sb.totalSpentPiasters.compareTo(sa.totalSpentPiasters);
        case _CustomerSort.highestPoints:
          return b.loyaltyPoints.compareTo(a.loyaltyPoints);
        case _CustomerSort.nameAsc:
          return a.name.compareTo(b.name);
      }
    });
    return list;
  }

  Future<void> _openWhatsApp(CustomerEntity customer) async {
    final uri = CustomerLedgerService.buildWhatsAppUri(customer.phone);
    if (uri == null) {
      AppFeedback.showError(context, 'رقم الهاتف غير صالح لفتح واتساب');
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        AppFeedback.showError(context, 'تعذر فتح واتساب على هذا الجهاز');
      }
    }
  }

  Future<void> _copyPhone(CustomerEntity customer) async {
    await Clipboard.setData(ClipboardData(text: customer.phone));
    if (mounted) {
      AppFeedback.showSuccess(context, 'تم نسخ الرقم: ${customer.phone}');
    }
  }

  Future<void> _exportExcel(List<CustomerEntity> customers) async {
    final svc = _ledgerService;
    if (svc == null || customers.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final path = await svc.exportCustomersExcel(customers, _summaries);
      if (mounted && path != null) {
        AppFeedback.showSuccess(context, 'تم تصدير سجل العملاء بنجاح:\n$path');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'تعذر تصدير العملاء: $e');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  bool _canManageCustomers(BuildContext context) {
    bool admin = true;
    try {
      final auth = context.read<AuthCubit>().state;
      if (auth is AuthAuthenticated) {
        admin = auth.user.role.toLowerCase() != 'cashier';
      }
    } catch (_) {}
    if (admin) return true;
    return CashierPermissionsService.current.allowManageCustomers;
  }

  void _handleEsc(BuildContext context) {
    if (_searchCtrl.text.isNotEmpty) {
      _searchCtrl.clear();
      context.read<CustomerCubit>().searchCustomers('');
      setState(() {});
      return;
    }
    if (Navigator.canPop(context)) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _isAdmin(context);
    final canManage = isAdmin || CashierPermissionsService.current.allowManageCustomers;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () =>
            _searchFocusNode.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f3): () {
          if (_canManageCustomers(context)) {
            showCustomerDialog(context);
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _handleEsc(context),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => handleNumpadAddShortcut(event, () {
          if (_canManageCustomers(context)) {
            showCustomerDialog(context);
          }
        }),
        child: Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سجل العملاء وكشف الحساب',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'إدارة العملاء، المشتريات، الأقساط النشطة، نقاط الولاء والتواصل المباشر',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          BlocBuilder<CustomerCubit, CustomerState>(
            builder: (context, state) {
              final visible = _applyFilterAndSort(state.customers);
              return Row(
                children: [
                  if (visible.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      child: OutlinedButton.icon(
                        key: const Key('export_customers_excel_btn'),
                        onPressed:
                            _exporting ? null : () => _exportExcel(visible),
                        icon: _exporting
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.table_view_rounded, size: 18),
                        label: const Text('تصدير إكسيل'),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 12,
                    ),
                    child: ElevatedButton.icon(
                      key: const Key('add_customer_btn'),
                      icon: const Icon(
                        Icons.person_add_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: const Text(
                        'إضافة عميل جديد',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: canManage ? () => showCustomerDialog(context) : null,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<CustomerCubit, CustomerState>(
        listener: (context, state) {
          if (state.status == CustomerStatus.success) {
            _loadSummaries();
          } else if (state.status == CustomerStatus.error &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.errorMessage!.replaceFirst('Exception: ', ''),
                ),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        builder: (context, state) {
          final allCustomers = state.customers;
          final filteredCustomers = _applyFilterAndSort(allCustomers);

          final wholesaleCount = allCustomers.where((c) => c.isWholesale).length;
          final vipCount = allCustomers.where((c) => c.isVip).length;
          int withInstCount = 0;
          int totalInstRemaining = 0;
          for (final c in allCustomers) {
            final sum = _summaries[c.id];
            if (sum != null && sum.activeInstallmentsCount > 0) {
              withInstCount++;
              totalInstRemaining += sum.installmentsRemainingPiasters;
            }
          }

          final retailCount =
              allCustomers.where((c) => !c.isWholesale && !c.isVip).length;
          final discountedCount =
              allCustomers.where((c) => c.discountPercent > 0).length;
          final hasActiveFilters =
              _searchCtrl.text.isNotEmpty || _filter != _CustomerFilter.all;

          return Column(
            children: [
              const Divider(height: 1),
              // Zone 1: Clean Equal-Width Executive KPI Cards
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = <Widget>[
                      _executiveKpiCard(
                        title: 'إجمالي العملاء',
                        value: '${allCustomers.length} عميل',
                        subtitle: '$retailCount قطاعي • $discountedCount لديهم خصم',
                        icon: Icons.people_alt_outlined,
                        accent: AppColors.primary,
                      ),
                      _executiveKpiCard(
                        title: 'تجار الجملة',
                        value: '$wholesaleCount',
                        subtitle: 'حسابات أسعار الجملة',
                        icon: Icons.storefront_outlined,
                        accent: Colors.purple.shade700,
                      ),
                      _executiveKpiCard(
                        title: 'عملاء VIP',
                        value: '$vipCount',
                        subtitle: 'العملاء المميزون',
                        icon: Icons.workspace_premium_outlined,
                        accent: Colors.amber.shade800,
                      ),
                      _executiveKpiCard(
                        title: 'أقساط نشطة',
                        value: withInstCount == 0
                            ? 'لا توجد أقساط'
                            : '${Money(totalInstRemaining).toDisplay()} ج.م',
                        subtitle: '$withInstCount عميل عليه أقساط',
                        icon: Icons.credit_score_rounded,
                        accent: withInstCount > 0
                            ? Colors.orange.shade800
                            : Colors.teal.shade700,
                      ),
                    ];

                    if (constraints.maxWidth >= 880) {
                      return Row(
                        children: [
                          for (var i = 0; i < cards.length; i++) ...[
                            Expanded(child: cards[i]),
                            if (i < cards.length - 1) const SizedBox(width: 12),
                          ],
                        ],
                      );
                    }

                    final cardWidth = (constraints.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: cards
                          .map(
                            (c) => SizedBox(
                              width: cardWidth > 220
                                  ? cardWidth
                                  : constraints.maxWidth,
                              child: c,
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ),
              // Zone 2: Unified Search, Sort & Segmented Filter Bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, c) {
                          final searchField = TextField(
                            key: const Key('customer_search_field'),
                            controller: _searchCtrl,
                            focusNode: _searchFocusNode,
                            decoration: InputDecoration(
                              hintText: 'البحث عن عميل بالاسم أو رقم الهاتف...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade500,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                size: 20,
                                color: Colors.grey.shade600,
                              ),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        context
                                            .read<CustomerCubit>()
                                            .searchCustomers('');
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                            ),
                            onChanged: (query) {
                              context
                                  .read<CustomerCubit>()
                                  .searchCustomers(query);
                              setState(() {});
                            },
                          );

                          final sortDropdown =
                              DropdownButtonFormField<_CustomerSort>(
                            initialValue: _sort,
                            isDense: true,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'الترتيب',
                              filled: true,
                              fillColor: Color(0xFFF8FAFC),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: _CustomerSort.newest,
                                child: Text('الأحدث تسجيلاً'),
                              ),
                              DropdownMenuItem(
                                value: _CustomerSort.highestSpend,
                                child: Text('الأعلى مشتريات'),
                              ),
                              DropdownMenuItem(
                                value: _CustomerSort.highestPoints,
                                child: Text('الأعلى نقاط ولاء'),
                              ),
                              DropdownMenuItem(
                                value: _CustomerSort.nameAsc,
                                child: Text('الاسم (أ - ي)'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _sort = v);
                            },
                          );

                          if (c.maxWidth >= 600) {
                            return Row(
                              children: [
                                Expanded(child: searchField),
                                const SizedBox(width: 10),
                                SizedBox(width: 205, child: sortDropdown),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              searchField,
                              const SizedBox(height: 10),
                              sortDropdown,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _segmentTab(
                                      _CustomerFilter.all,
                                      'الكل',
                                      allCustomers.length,
                                      AppColors.primary,
                                    ),
                                    _segmentTab(
                                      _CustomerFilter.retail,
                                      'قطاعي',
                                      retailCount,
                                      Colors.blueGrey.shade700,
                                    ),
                                    _segmentTab(
                                      _CustomerFilter.wholesale,
                                      'جملة',
                                      wholesaleCount,
                                      Colors.purple.shade700,
                                    ),
                                    _segmentTab(
                                      _CustomerFilter.vip,
                                      'VIP',
                                      vipCount,
                                      Colors.amber.shade800,
                                    ),
                                    _segmentTab(
                                      _CustomerFilter.discounted,
                                      'لديهم خصم',
                                      discountedCount,
                                      Colors.green.shade700,
                                    ),
                                    if (_installmentsEnabled || withInstCount > 0)
                                      _segmentTab(
                                        _CustomerFilter.withInstallments,
                                        _installmentsEnabled ? 'لديهم أقساط' : 'أقساط نشطة',
                                        withInstCount,
                                        Colors.orange.shade800,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (hasActiveFilters) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () {
                                _searchCtrl.clear();
                                context.read<CustomerCubit>().searchCustomers(
                                  '',
                                );
                                setState(() => _filter = _CustomerFilter.all);
                              },
                              icon: const Icon(
                                Icons.filter_alt_off_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'مسح الفلاتر',
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (state.status == CustomerStatus.loading) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (state.status == CustomerStatus.error &&
                        allCustomers.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 64,
                              color: AppColors.error,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              state.errorMessage ??
                                  'حدث خطأ أثناء تحميل بيانات العملاء',
                              style: const TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  context.read<CustomerCubit>().loadCustomers(),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text(
                                'إعادة المحاولة',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    if (filteredCustomers.isEmpty) {
                      final hasSearchOrFilter =
                          _searchCtrl.text.isNotEmpty ||
                          _filter != _CustomerFilter.all;
                      return AppEmptyState(
                        icon: Icons.people_outline_rounded,
                        title: hasSearchOrFilter
                            ? 'لا يوجد عملاء مطابقون للبحث أو التصفية'
                            : 'لا يوجد عملاء مسجلون حتى الآن',
                        subtitle: hasSearchOrFilter
                            ? 'جرّب تغيير الفلتر أو مسح نص البحث.'
                            : 'قم بإضافة عملاء جدد لحفظ فواتيرهم ونقاط الولاء والخصومات الخاصة بهم.',
                        actionLabel:
                            hasSearchOrFilter ? null : 'إضافة عميل جديد',
                        onAction: hasSearchOrFilter
                            ? null
                            : () => showCustomerDialog(context),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredCustomers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final customer = filteredCustomers[index];
                        final sum =
                            _summaries[customer.id] ??
                            CustomerFinancialSummary.empty;
                        return _buildCustomerCard(
                          context,
                          customer,
                          sum,
                          isAdmin: isAdmin,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
    ),
    );
  }

  Widget _buildCustomerCard(
    BuildContext context,
    CustomerEntity customer,
    CustomerFinancialSummary sum, {
    required bool isAdmin,
  }) {
    final isWholesale = customer.isWholesale;
    final isVip = customer.isVip;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showCustomerProfileDialog(
          context,
          customer: customer,
          ledgerOverride: widget.ledgerOverride,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFF1F5F9),
                child: Icon(
                  isWholesale
                      ? Icons.storefront_rounded
                      : isVip
                          ? Icons.workspace_premium_rounded
                          : Icons.person_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          customer.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15.5,
                            color: AppColors.onSurface,
                          ),
                        ),
                        if (customer.isBlacklisted)
                          _tag(
                            'محظور (تهرب تقسيط)',
                            const Color(0xFFFEF2F2),
                            AppColors.error,
                          )
                        else if (isWholesale)
                          _tag(
                            'تاجر جملة',
                            const Color(0xFFF1F5F9),
                            const Color(0xFF334155),
                          )
                        else if (isVip)
                          _tag(
                            'عميل مميز',
                            const Color(0xFFF1F5F9),
                            const Color(0xFF334155),
                          ),
                        if (customer.discountPercent > 0)
                          _tag(
                            'خصم ${customer.discountPercent}%',
                            const Color(0xFFF1F5F9),
                            const Color(0xFF334155),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.phone_outlined,
                              size: 13.5,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              customer.phone,
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${customer.loyaltyPoints} نقطة ولاء',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        if (sum.invoiceCount > 0)
                          Text(
                            '${sum.invoiceCount} فاتورة • ${Money(sum.totalSpentPiasters).toDisplay()} ج.م',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        if (sum.activeInstallmentsCount > 0)
                          Text(
                            'أقساط: ${Money(sum.installmentsRemainingPiasters).toDisplay()} ج.م',
                            style: TextStyle(
                              fontSize: 12,
                              color: sum.installmentsRemainingPiasters > 0
                                  ? AppColors.warning
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        if (sum.creditDebtPiasters > 0)
                          Text(
                            'مديونية: ${Money(sum.creditDebtPiasters).toDisplay()} ج.م',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                            ),
                          ),
                        if ((_creditEnabled || sum.creditDebtPiasters > 0) && customer.creditLimit > 0)
                          Text(
                            'حد آجل: ${Money(customer.creditLimit).toDisplay()} ج.م',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    tooltip: 'كشف حساب وفواتير العميل',
                    onPressed: () => showCustomerProfileDialog(
                      context,
                      customer: customer,
                      ledgerOverride: widget.ledgerOverride,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.chat_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    tooltip: 'محادثة واتساب',
                    onPressed: () => _openWhatsApp(customer),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.copy_rounded,
                      color: Color(0xFF64748B),
                      size: 18,
                    ),
                    tooltip: 'نسخ رقم الهاتف',
                    onPressed: () => _copyPhone(customer),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    tooltip: 'تعديل بيانات العميل ومزاياه',
                    onPressed: () => showCustomerDialog(
                      context,
                      customer: customer,
                    ),
                  ),
                  if (isAdmin)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.error,
                        size: 20,
                      ),
                      tooltip: 'حذف العميل (للمدير فقط)',
                      onPressed: () => _confirmDelete(context, customer),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _executiveKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentTab(
    _CustomerFilter value,
    String label,
    int count,
    Color activeColor,
  ) {
    final selected = _filter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? activeColor : Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? activeColor.withValues(alpha: 0.12)
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: selected ? activeColor : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CustomerEntity customer,
  ) async {
    final confirmed = await AppFeedback.confirmDelete(
      context: context,
      title: 'تأكيد حذف العميل',
      content:
          'هل أنت متأكد من حذف العميل "${customer.name}"؟ لن يُسمح بالحذف إذا كان لديه عقود تقسيط نشطة.',
    );

    if (confirmed && context.mounted) {
      final cubit = context.read<CustomerCubit>();
      final ok = await cubit.deleteCustomer(customer.id);
      if (!context.mounted) return;
      if (ok) {
        AppFeedback.showSuccess(
          context,
          'تم حذف العميل "${customer.name}" بنجاح',
        );
      }
    }
  }
}
