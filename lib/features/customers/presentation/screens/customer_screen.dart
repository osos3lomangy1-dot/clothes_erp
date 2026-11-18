import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/show_customer_dialog.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
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
  _CustomerFilter _filter = _CustomerFilter.all;
  _CustomerSort _sort = _CustomerSort.newest;
  Map<String, CustomerFinancialSummary> _summaries = const {};
  bool _exporting = false;

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
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    final isAdmin = _isAdmin(context);

    return Scaffold(
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
                      onPressed: () {
                        showCustomerDialog(context);
                      },
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

          return Column(
            children: [
              // KPI Strip + Search + Filter Chips + Sort
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // KPI Summary Strip
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _kpiPill(
                            'إجمالي العملاء',
                            '${allCustomers.length}',
                            Icons.people_alt_rounded,
                            AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          _kpiPill(
                            'تجار جملة',
                            '$wholesaleCount',
                            Icons.storefront_rounded,
                            Colors.purple.shade700,
                          ),
                          const SizedBox(width: 10),
                          _kpiPill(
                            'عملاء VIP',
                            '$vipCount',
                            Icons.workspace_premium_rounded,
                            Colors.amber.shade800,
                          ),
                          const SizedBox(width: 10),
                          _kpiPill(
                            'عليهم أقساط نشطة',
                            '$withInstCount عميل (${Money(totalInstRemaining).toDisplay()} ج.م)',
                            Icons.credit_score_rounded,
                            withInstCount > 0
                                ? Colors.orange.shade800
                                : Colors.teal,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Search + Sort Row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'البحث عن عميل بالاسم أو رقم الهاتف...',
                              prefixIcon: Icon(
                                Icons.search,
                                color: AppColors.primary,
                              ),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        context
                                            .read<CustomerCubit>()
                                            .searchCustomers('');
                                        setState(() {});
                                      },
                                    )
                                  : null,
                              isDense: true,
                            ),
                            onChanged: (query) {
                              context
                                  .read<CustomerCubit>()
                                  .searchCustomers(query);
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 210,
                          child: DropdownButtonFormField<_CustomerSort>(
                            initialValue: _sort,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'ترتيب حسب',
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
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Filter Chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _filterChip(_CustomerFilter.all, 'الكل'),
                        _filterChip(_CustomerFilter.retail, 'قطاعي'),
                        _filterChip(_CustomerFilter.wholesale, 'جملة'),
                        _filterChip(_CustomerFilter.vip, 'VIP'),
                        _filterChip(_CustomerFilter.discounted, 'لديهم خصم'),
                        _filterChip(
                          _CustomerFilter.withInstallments,
                          'لديهم أقساط ($withInstCount)',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
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
            border: Border.all(
              color: sum.activeInstallmentsCount > 0
                  ? Colors.orange.shade200
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: isWholesale
                    ? Colors.purple.shade50
                    : isVip
                        ? Colors.amber.shade50
                        : AppColors.primary.withValues(alpha: 0.12),
                child: Icon(
                  isWholesale
                      ? Icons.storefront_rounded
                      : isVip
                          ? Icons.workspace_premium_rounded
                          : Icons.person_rounded,
                  color: isWholesale
                      ? Colors.purple.shade700
                      : isVip
                          ? Colors.amber.shade800
                          : AppColors.primary,
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
                          ),
                        ),
                        if (isWholesale)
                          _tag(
                            'تاجر جملة',
                            Colors.purple.shade50,
                            Colors.purple.shade800,
                          )
                        else if (isVip)
                          _tag(
                            'عميل مميز',
                            Colors.amber.shade50,
                            Colors.amber.shade900,
                          ),
                        if (customer.discountPercent > 0)
                          _tag(
                            'خصم ${customer.discountPercent}%',
                            Colors.green.shade50,
                            Colors.green.shade800,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.phone_outlined,
                              size: 13.5,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              customer.phone,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        _tag(
                          '★ ${customer.loyaltyPoints} نقطة',
                          Colors.amber.shade50,
                          Colors.amber.shade900,
                        ),
                        if (sum.invoiceCount > 0)
                          _tag(
                            '${sum.invoiceCount} فاتورة • ${Money(sum.totalSpentPiasters).toDisplay()} ج.م',
                            Colors.blue.shade50,
                            Colors.blue.shade900,
                          ),
                        if (sum.activeInstallmentsCount > 0)
                          _tag(
                            'أقساط متبقية: ${Money(sum.installmentsRemainingPiasters).toDisplay()} ج.م',
                            Colors.orange.shade50,
                            Colors.orange.shade900,
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
                    icon: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: Colors.teal,
                    ),
                    tooltip: 'كشف حساب وفواتير العميل',
                    onPressed: () => showCustomerProfileDialog(
                      context,
                      customer: customer,
                      ledgerOverride: widget.ledgerOverride,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.chat_rounded,
                      color: Colors.green.shade700,
                      size: 20,
                    ),
                    tooltip: 'محادثة واتساب',
                    onPressed: () => _openWhatsApp(customer),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.copy_rounded,
                      color: Colors.grey.shade700,
                      size: 18,
                    ),
                    tooltip: 'نسخ رقم الهاتف',
                    onPressed: () => _copyPhone(customer),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.edit_outlined,
                      color: AppColors.primary,
                    ),
                    tooltip: 'تعديل بيانات العميل ومزاياه',
                    onPressed: () => showCustomerDialog(
                      context,
                      customer: customer,
                    ),
                  ),
                  if (isAdmin)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.error,
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

  Widget _kpiPill(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(_CustomerFilter value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.primary.withValues(alpha: 0.14),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? AppColors.primary : Colors.grey.shade800,
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
