import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../installments/presentation/screens/installment_detail_screen.dart';
import '../../data/services/customer_ledger_service.dart';
import '../../domain/entities/customer_entity.dart';

/// Opens a rich CRM profile & financial statement dialog for [customer].
Future<void> showCustomerProfileDialog(
  BuildContext context, {
  required CustomerEntity customer,
  CustomerLedgerService? ledgerOverride,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: AppColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: _CustomerProfileBody(
          customer: customer,
          ledgerOverride: ledgerOverride,
        ),
      ),
    ),
  );
}

class _CustomerProfileBody extends StatefulWidget {
  final CustomerEntity customer;
  final CustomerLedgerService? ledgerOverride;

  const _CustomerProfileBody({
    required this.customer,
    this.ledgerOverride,
  });

  @override
  State<_CustomerProfileBody> createState() => _CustomerProfileBodyState();
}

class _CustomerProfileBodyState extends State<_CustomerProfileBody> {
  CustomerStatement? _statement;
  bool _loading = true;
  String? _error;

  CustomerLedgerService? get _service {
    if (widget.ledgerOverride != null) return widget.ledgerOverride;
    return getIt.isRegistered<CustomerLedgerService>()
        ? getIt<CustomerLedgerService>()
        : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = _service;
    if (svc == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر الوصول لخدمة كشف الحساب';
        });
      }
      return;
    }
    try {
      final st = await svc.getCustomerStatement(widget.customer.id);
      if (!mounted) return;
      setState(() {
        _statement = st;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل كشف الحساب: $e';
      });
    }
  }

  Future<void> _openWhatsApp() async {
    final uri = CustomerLedgerService.buildWhatsAppUri(widget.customer.phone);
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

  Future<void> _copyPhone() async {
    await Clipboard.setData(ClipboardData(text: widget.customer.phone));
    if (mounted) {
      AppFeedback.showSuccess(
        context,
        'تم نسخ الرقم: ${widget.customer.phone}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final dateFmt = DateFormat('yyyy/MM/dd HH:mm');
    final shortDateFmt = DateFormat('yyyy/MM/dd');

    return Column(
      children: [
        // Header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: c.isWholesale
                    ? Colors.purple.shade50
                    : c.isVip
                        ? Colors.amber.shade50
                        : AppColors.primary.withValues(alpha: 0.12),
                child: Icon(
                  c.isWholesale
                      ? Icons.storefront_rounded
                      : c.isVip
                          ? Icons.workspace_premium_rounded
                          : Icons.person_rounded,
                  color: c.isWholesale
                      ? Colors.purple.shade700
                      : c.isVip
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
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        _typeChip(c),
                        if (c.discountPercent > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Text(
                              'خصم ${c.discountPercent}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          c.phone,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: _copyPhone,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.copy_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'نسخ',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: _openWhatsApp,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chat_rounded,
                                  size: 13,
                                  color: Colors.green.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'واتساب',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'إغلاق',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(
            child: Center(
              child: Text(
                _error!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          )
        else
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  // 4 KPI Summary Cards
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: _kpiBox(
                            'إجمالي المشتريات',
                            '${Money(_statement!.summary.totalSpentPiasters).toDisplay()} ج.م',
                            Icons.shopping_bag_outlined,
                            AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _kpiBox(
                            'عدد الفواتير',
                            '${_statement!.summary.invoiceCount}',
                            Icons.receipt_long_rounded,
                            Colors.indigo,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _kpiBox(
                            'متبقي الأقساط',
                            '${Money(_statement!.summary.installmentsRemainingPiasters).toDisplay()} ج.م',
                            Icons.credit_score_rounded,
                            _statement!.summary.installmentsRemainingPiasters > 0
                                ? Colors.orange.shade800
                                : Colors.teal,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _kpiBox(
                            'نقاط الولاء',
                            '${c.loyaltyPoints} نقطة',
                            Icons.star_rounded,
                            Colors.amber.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.grey.shade600,
                      indicatorColor: AppColors.primary,
                      tabs: [
                        Tab(
                          text: 'الفواتير (${_statement!.sales.length})',
                        ),
                        Tab(
                          text: 'التقسيط (${_statement!.installments.length})',
                        ),
                        Tab(
                          text: 'نقاط الولاء (${_statement!.loyaltyLogs.length})',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Tab 1: Invoices
                        _statement!.sales.isEmpty
                            ? _emptyTab('لا توجد فواتير مسجلة لهذا العميل بعد')
                            : ListView.separated(
                                padding: const EdgeInsets.all(14),
                                itemCount: _statement!.sales.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final s = _statement!.sales[i];
                                  final isCancelled = s.status == 'cancelled';
                                  return Card(
                                    margin: EdgeInsets.zero,
                                    child: ListTile(
                                      dense: true,
                                      leading: Icon(
                                        Icons.receipt_outlined,
                                        color: isCancelled
                                            ? AppColors.error
                                            : AppColors.primary,
                                      ),
                                      title: Text(
                                        'فاتورة #${s.shortRef}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          decoration: isCancelled
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${dateFmt.format(s.date.toLocal())} • ${_paymentLabel(s.paymentMethod)}',
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${Money(s.total).toDisplay()} ج.م',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (isCancelled)
                                            const Text(
                                              'ملغاة',
                                              style: TextStyle(
                                                color: AppColors.error,
                                                fontSize: 11,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                        // Tab 2: Installments
                        _statement!.installments.isEmpty
                            ? _emptyTab('لا توجد عقود تقسيط مسجلة لهذا العميل')
                            : ListView.separated(
                                padding: const EdgeInsets.all(14),
                                itemCount: _statement!.installments.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final inst = _statement!.installments[i];
                                  return Card(
                                    margin: EdgeInsets.zero,
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.calendar_month_rounded,
                                        color: _instStatusColor(inst.status),
                                      ),
                                      title: Text(
                                        'عقد بقيمة ${Money(inst.totalPiasters).toDisplay()} ج.م (${inst.durationMonths} شهر)',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'البداية: ${shortDateFmt.format(inst.startDate.toLocal())} • المتبقي: ${Money(inst.remainingPiasters).toDisplay()} ج.م',
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _instStatusColor(
                                                inst.status,
                                              ).withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _instStatusLabel(inst.status),
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                                color: _instStatusColor(
                                                  inst.status,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          IconButton(
                                            tooltip: 'فتح تفاصيل العقد',
                                            icon: const Icon(
                                              Icons.open_in_new_rounded,
                                              size: 18,
                                            ),
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                              Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      InstallmentDetailScreen(
                                                    contractId: inst.id,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                        // Tab 3: Loyalty Ledger
                        _statement!.loyaltyLogs.isEmpty
                            ? _emptyTab('لا توجد حركات نقاط ولاء مسجلة بعد')
                            : ListView.separated(
                                padding: const EdgeInsets.all(14),
                                itemCount: _statement!.loyaltyLogs.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final log = _statement!.loyaltyLogs[i];
                                  final isGain = log.pointsDelta >= 0;
                                  return Card(
                                    margin: EdgeInsets.zero,
                                    child: ListTile(
                                      dense: true,
                                      leading: Icon(
                                        isGain
                                            ? Icons.add_circle_outline_rounded
                                            : Icons.remove_circle_outline_rounded,
                                        color: isGain
                                            ? Colors.green.shade700
                                            : Colors.orange.shade800,
                                      ),
                                      title: Text(
                                        log.reason,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        dateFmt.format(log.createdAt.toLocal()),
                                      ),
                                      trailing: Text(
                                        '${isGain ? '+' : ''}${log.pointsDelta} نقطة',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isGain
                                              ? Colors.green.shade800
                                              : Colors.orange.shade900,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _emptyTab(String msg) {
    return Center(
      child: Text(
        msg,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      ),
    );
  }

  Widget _kpiBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
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
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _typeChip(CustomerEntity c) {
    final (label, bg, fg) = c.isWholesale
        ? ('تاجر جملة', Colors.purple.shade50, Colors.purple.shade800)
        : c.isVip
            ? ('عميل مميز VIP', Colors.amber.shade50, Colors.amber.shade900)
            : ('عميل قطاعي', Colors.grey.shade100, Colors.grey.shade800);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  String _paymentLabel(String m) {
    switch (m) {
      case 'cash':
        return 'نقدي';
      case 'card':
      case 'visa':
        return 'بطاقة / فيزا';
      case 'installment':
        return 'تقسيط';
      case 'mixed':
        return 'دفع مختلط';
      default:
        return m;
    }
  }

  String _instStatusLabel(String s) {
    switch (s) {
      case 'active':
        return 'نشط';
      case 'overdue':
        return 'متأخر';
      case 'completed':
        return 'مكتمل';
      case 'cancelled':
        return 'ملغي';
      default:
        return s;
    }
  }

  Color _instStatusColor(String s) {
    switch (s) {
      case 'overdue':
        return AppColors.error;
      case 'completed':
        return Colors.teal.shade700;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.orange.shade800;
    }
  }
}

