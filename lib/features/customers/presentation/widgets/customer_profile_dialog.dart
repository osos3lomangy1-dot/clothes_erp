import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../installments/presentation/screens/installment_detail_screen.dart';
import '../../data/datasources/customers_local_data_source.dart';
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
  bool _installmentsEnabled = false;
  bool _creditEnabled = true;
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
      bool instOn = false;
      bool creditOn = true;
      try {
        if (getIt.isRegistered<FeatureGate>()) {
          final gate = getIt<FeatureGate>();
          final featureOn = await gate.isEnabled(FeatureKeys.installments);
          final meta = await gate.getMeta('payment.installment');
          instOn = featureOn && (meta != '0');

          final creditMeta = await gate.getMeta('payment.credit');
          creditOn = creditMeta == null || creditMeta != '0';
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _statement = st;
        _installmentsEnabled = instOn;
        _creditEnabled = creditOn;
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
          Builder(
            builder: (context) {
              final hasActiveInstallment = _statement!.installments.any(
                (inst) => inst.status == 'active' || inst.remainingPiasters > 0,
              );
              final showInstallments = _installmentsEnabled || hasActiveInstallment;

              final hasActiveCreditDebt = _statement!.summary.creditDebtPiasters > 0;
              final hasCreditPayments = _statement!.payments.isNotEmpty;
              final showCredit = _creditEnabled || hasActiveCreditDebt || hasCreditPayments;

              final tabCount = 1 + (showInstallments ? 1 : 0) + (showCredit ? 1 : 0) + 1;

              return Expanded(
                child: DefaultTabController(
                  length: tabCount,
                  child: Column(
                    children: [
                      // KPI Summary Cards
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
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
                            if (showInstallments) ...[
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
                            ],
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
                      // Credit Account & Debt Banner
                      if (showCredit)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _statement!.summary.creditDebtPiasters > 0
                            ? Colors.red.shade50
                            : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _statement!.summary.creditDebtPiasters > 0
                              ? Colors.red.shade200
                              : Colors.blue.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_rounded,
                            color: _statement!.summary.creditDebtPiasters > 0
                                ? Colors.red.shade800
                                : AppColors.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    text: 'مديونية الحساب الآجل: ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '${Money(_statement!.summary.creditDebtPiasters).toDisplay()} ج.م',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: _statement!.summary.creditDebtPiasters > 0
                                              ? Colors.red.shade800
                                              : Colors.green.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  c.creditLimit > 0
                                      ? 'الحد الائتماني المسموح: ${Money(c.creditLimit).toDisplay()} ج.م'
                                      : 'الحد الائتماني: غير مقيد (مفتوح)',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _showRecordPaymentDialog(context),
                            icon: const Icon(Icons.price_check_rounded, size: 18),
                            label: const Text(
                              'تحصيل دفعة حساب',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
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
                        if (showInstallments)
                          Tab(
                            text: 'التقسيط (${_statement!.installments.length})',
                          ),
                        if (showCredit)
                          Tab(
                            text: 'سداد الآجل (${_statement!.payments.length})',
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
                        // Tab 2: Installments (only shown if feature enabled or customer has active installment)
                        if (showInstallments)
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
                        // Tab 3: Credit Payments (سداد الآجل)
                        if (showCredit)
                          _statement!.payments.isEmpty
                            ? _emptyTab('لا توجد دفعات مسجلة على الحساب الآجل لهذا العميل بعد')
                            : ListView.separated(
                                padding: const EdgeInsets.all(14),
                                itemCount: _statement!.payments.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (_, i) {
                                  final p = _statement!.payments[i];
                                  final isCash = p.paymentMethod == 'cash';
                                  return Card(
                                    margin: EdgeInsets.zero,
                                    child: ListTile(
                                      dense: true,
                                      leading: CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Colors.green.shade50,
                                        child: Icon(
                                          isCash ? Icons.payments_rounded : Icons.credit_card_rounded,
                                          size: 18,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                      title: Text(
                                        'سند قبض / تحصيل دفعة: +${Money(p.amount).toDisplay()} ج.م',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade900,
                                          fontSize: 14,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${dateFmt.format(p.paymentDate.toLocal())} • ${isCash ? 'نقدي (أودع بالدرج)' : 'بطاقة / فيزا'}'
                                        '${p.notes != null && p.notes!.isNotEmpty ? '\nملاحظات: ${p.notes}' : ''}',
                                      ),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.green.shade300),
                                        ),
                                        child: Text(
                                          'تم التحصيل',
                                          style: TextStyle(
                                            color: Colors.green.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                        // Tab 4: Loyalty Ledger
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
          );
        },
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

  Future<void> _showRecordPaymentDialog(BuildContext context) async {
    final debt = _statement?.summary.creditDebtPiasters ?? 0;
    final amountCtrl = TextEditingController(
      text: debt > 0
          ? (debt % 100 == 0 ? '${debt ~/ 100}' : (debt / 100.0).toStringAsFixed(2))
          : '',
    );
    final notesCtrl = TextEditingController();
    String method = 'cash';

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.price_check_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'تحصيل دفعة من حساب العميل',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('إجمالي المديونية الحالية:', style: TextStyle(fontSize: 13)),
                      Text(
                        '${Money(debt).toDisplay()} ج.م',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: debt > 0 ? Colors.red.shade800 : Colors.green.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'المبلغ المحصل *',
                    suffixText: 'ج.م',
                    prefixIcon: const Icon(Icons.attach_money_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: InputDecoration(
                    labelText: 'طريقة الدفع',
                    prefixIcon: const Icon(Icons.payment_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('كاش / نقدي (إيداع بالدرج)')),
                    DropdownMenuItem(value: 'card', child: Text('بطاقة / فيزا')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => method = val);
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    hintText: 'مثال: سداد دفعة نقدية بالفرع',
                    prefixIcon: const Icon(Icons.notes_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final amtDouble = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final amtPiasters = (amtDouble * 100).round();
                if (amtPiasters <= 0) {
                  AppFeedback.showError(dialogCtx, 'يرجى إدخال مبلغ صحيح أكبر من الصفر');
                  return;
                }

                String userId = 'admin';
                try {
                  final auth = context.read<AuthCubit>().state;
                  if (auth is AuthAuthenticated) userId = auth.user.id;
                } catch (_) {}

                final ds = getIt<CustomersLocalDataSource>();
                try {
                  await ds.recordCustomerPayment(
                    customerId: widget.customer.id,
                    amount: amtPiasters,
                    userId: userId,
                    paymentMethod: method,
                    notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  );
                  if (!dialogCtx.mounted) return;
                  Navigator.pop(dialogCtx);
                  if (mounted) {
                    AppFeedback.showSuccess(
                      context,
                      'تم تسجيل سند قبض بمبلغ ${Money(amtPiasters).toDisplay()} ج.م بنجاح',
                    );
                    _load();
                  }
                } catch (e) {
                  if (dialogCtx.mounted) {
                    AppFeedback.showError(dialogCtx, 'فشل تسجيل الدفعة: $e');
                  }
                }
              },
              child: const Text(
                'تأكيد واستلام الدفعة',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
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

