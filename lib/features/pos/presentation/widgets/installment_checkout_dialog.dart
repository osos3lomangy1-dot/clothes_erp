import 'package:dartz/dartz.dart' hide State;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/money.dart';
import '../../../customers/domain/entities/customer_entity.dart';
import '../../../installments/data/services/manager_pin_service.dart';
import '../../../installments/domain/entities/customer_installments_summary.dart';
import '../../../installments/domain/entities/installment_plan_entity.dart';
import '../../../installments/domain/facades/installments_facade.dart';
import '../../../installments/domain/services/installment_calculator.dart';

class InstallmentCheckoutConfig {
  final String? planId;
  final int downPaymentPiasters;
  final int interestBp;
  final InstallmentInterestModel interestModel;
  final int durationMonths;
  final String pin;
  final bool isCustom;

  const InstallmentCheckoutConfig({
    this.planId,
    required this.downPaymentPiasters,
    required this.interestBp,
    required this.interestModel,
    required this.durationMonths,
    required this.pin,
    this.isCustom = false,
  });
}

class InstallmentCheckoutDialog extends StatefulWidget {
  final List<InstallmentPlanEntity> plans;
  final int totalPiasters;
  final bool pinRequired;
  final CustomerEntity? customer;

  const InstallmentCheckoutDialog({
    super.key,
    required this.plans,
    required this.totalPiasters,
    required this.pinRequired,
    this.customer,
  });

  @override
  State<InstallmentCheckoutDialog> createState() =>
      _InstallmentCheckoutDialogState();
}

class _InstallmentCheckoutDialogState extends State<InstallmentCheckoutDialog> {
  bool _isCustomMode = false;
  InstallmentPlanEntity? _selectedPlan;
  InstallmentInterestModel _selectedModel =
      InstallmentInterestModel.percentTotal;
  late final TextEditingController _downPaymentCtrl;
  late final TextEditingController _customMonthsCtrl;
  late final TextEditingController _customInterestPctCtrl;
  final _pinCtrl = TextEditingController();
  String? _error;
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    if (widget.plans.isEmpty) {
      _isCustomMode = true;
      _selectedPlan = null;
    } else {
      _isCustomMode = false;
      _selectedPlan = widget.plans.first;
    }

    final initialDown = (_selectedPlan != null && _selectedPlan!.downPaymentPiasters > 0)
        ? (_selectedPlan!.downPaymentPiasters / 100).toStringAsFixed(0)
        : '0';

    _downPaymentCtrl = TextEditingController(text: initialDown);
    _customMonthsCtrl = TextEditingController(text: '6');
    _customInterestPctCtrl = TextEditingController(text: '10');

    _downPaymentCtrl.addListener(() => setState(() {}));
    _customMonthsCtrl.addListener(() => setState(() {}));
    _customInterestPctCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _downPaymentCtrl.dispose();
    _customMonthsCtrl.dispose();
    _customInterestPctCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  String _modelLabel(InstallmentInterestModel m, double interestPct) {
    switch (m) {
      case InstallmentInterestModel.percentTotal:
        return 'نسبة إجمالية من أصل الدين ($interestPct%)';
      case InstallmentInterestModel.percentMonthly:
        return 'نسبة شهرية ($interestPct% شهرياً)';
      case InstallmentInterestModel.fixed:
        return 'مبلغ فائدة ثابت ($interestPct ج.م)';
    }
  }

  void _onPlanChanged(InstallmentPlanEntity newPlan) {
    setState(() {
      _selectedPlan = newPlan;
      if (newPlan.downPaymentPiasters > 0) {
        _downPaymentCtrl.text =
            (newPlan.downPaymentPiasters / 100).toStringAsFixed(0);
      }
    });
  }

  Future<void> _submit() async {
    final downDouble = double.tryParse(_downPaymentCtrl.text.trim()) ?? 0;
    final downPaymentPiasters = (downDouble * 100).round();

    if (downPaymentPiasters < 0) {
      setState(() => _error = 'الدفعة المقدمة لا يمكن أن تكون سالبة');
      return;
    }
    if (downPaymentPiasters >= widget.totalPiasters) {
      setState(() => _error =
          'الدفعة المقدمة يجب أن تكون أقل من إجمالي الفاتورة (${Money(widget.totalPiasters).toDisplay()} ج.م)');
      return;
    }

    int durationMonths = 6;
    int interestBp = 0;

    if (_isCustomMode) {
      final months = int.tryParse(_customMonthsCtrl.text.trim());
      if (months == null || months < 1 || months > 60) {
        setState(() => _error = 'مدة التقسيط يجب أن تكون بين شهر و 60 شهراً');
        return;
      }
      final interest = double.tryParse(_customInterestPctCtrl.text.trim());
      if (interest == null || interest < 0 || interest > 200) {
        setState(() => _error = 'نسبة الفائدة يجب أن تكون بين 0% و 200%');
        return;
      }
      durationMonths = months;
      interestBp = (interest * 100).round();
    } else {
      if (_selectedPlan == null) {
        setState(() => _error = 'يرجى اختيار خطة تقسيط معتمدة أو التبديل لخطة مخصصة');
        return;
      }
      durationMonths = _selectedPlan!.durationMonths;
      interestBp = _selectedPlan!.interestBp;
    }

    if (widget.pinRequired && _pinCtrl.text.trim().isEmpty) {
      setState(() => _error = 'الرجاء إدخال الرقم السري (PIN) للمدير');
      return;
    }

    // Pre-verify PIN right here so if wrong, the dialog stays open and doesn't trigger checkout!
    if (widget.pinRequired || _pinCtrl.text.trim().isNotEmpty) {
      setState(() {
        _isValidating = true;
        _error = null;
      });

      if (getIt.isRegistered<ManagerPinService>()) {
        final pinResult = await getIt<ManagerPinService>().verifyPin(
          pin: _pinCtrl.text.trim(),
          operation: 'create_contract',
        );
        if (!mounted) return;
        if (!pinResult.ok) {
          setState(() {
            _isValidating = false;
            _error = pinResult.error ?? 'الرقم السري للمدير غير صحيح';
          });
          return;
        }
      }
      setState(() => _isValidating = false);
    }

    if (!mounted) return;
    Navigator.pop(
      context,
      InstallmentCheckoutConfig(
        planId: _isCustomMode ? null : _selectedPlan?.id,
        downPaymentPiasters: downPaymentPiasters,
        interestBp: interestBp,
        interestModel: _selectedModel,
        durationMonths: durationMonths,
        pin: _pinCtrl.text.trim(),
        isCustom: _isCustomMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Live calculation for preview
    final downDouble = double.tryParse(_downPaymentCtrl.text.trim()) ?? 0;
    final downPiasters = (downDouble * 100).round().clamp(0, widget.totalPiasters);
    final financedPiasters = (widget.totalPiasters - downPiasters).clamp(0, widget.totalPiasters);

    final int effectiveDuration = _isCustomMode
        ? (int.tryParse(_customMonthsCtrl.text.trim()) ?? 6).clamp(1, 120)
        : (_selectedPlan?.durationMonths ?? 6);

    final double effectiveInterestPct = _isCustomMode
        ? (double.tryParse(_customInterestPctCtrl.text.trim()) ?? 0.0).clamp(0.0, 200.0)
        : ((_selectedPlan?.interestBp ?? 0) / 100.0);

    final int effectiveInterestBp = (effectiveInterestPct * 100).round().clamp(0, 20000);

    final scheduleResult = InstallmentCalculator.calculateSchedule(
      principalPiasters: widget.totalPiasters,
      durationMonths: effectiveDuration,
      interestModel: _selectedModel,
      interestValue: effectiveInterestBp,
      downPaymentPiasters: downPiasters,
      startDate: DateTime.now(),
    );

    int totalInterestPiasters = 0;
    int monthlyAmountPiasters = 0;
    DateTime firstDueDate = InstallmentCalculator.addMonths(DateTime.now(), 1);
    scheduleResult.fold((_) {}, (entries) {
      if (entries.isNotEmpty) {
        totalInterestPiasters = entries.fold<int>(0, (s, e) => s + e.interestComponentPiasters);
        monthlyAmountPiasters = entries.first.amountPiasters;
        firstDueDate = entries.first.dueDate;
      }
    });

    final totalObligationPiasters = downPiasters + financedPiasters + totalInterestPiasters;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.payments_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 10),
          const Text(
            'تفاصيل البيع بالتقسيط',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Customer Existing Obligations Alert
              if (widget.customer != null) ...[
                FutureBuilder<Either<Failure, List<CustomerInstallmentsSummary>>>(
                  future: getIt<InstallmentsFacade>().getGroupedByCustomer(now: DateTime.now()),
                  builder: (context, snapshot) {
                    final summaries = snapshot.data?.getOrElse(() => []) ?? [];
                    final customerSummary = summaries
                        .where((s) => s.customerId == widget.customer!.id)
                        .firstOrNull;
                    if (customerSummary == null) return const SizedBox.shrink();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.amber.shade800, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'العميل لديه ${customerSummary.contractsCount} عقد/عقود نشطة\n'
                              'متبقي: ${Money(customerSummary.totalRemainingPiasters).toDisplay()} ج.م | '
                              'قسط شهري: ${Money(customerSummary.totalMonthlyAmountPiasters).toDisplay()} ج.م',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade900,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],

              // Mode Switcher (Approved Plans vs Custom Plan)
              if (widget.plans.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _isCustomMode = false;
                              if (_selectedPlan == null && widget.plans.isNotEmpty) {
                                _selectedPlan = widget.plans.first;
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: !_isCustomMode ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: !_isCustomMode
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.view_timeline_outlined,
                                  size: 16,
                                  color: !_isCustomMode ? AppColors.primary : AppColors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'خطط معتمدة',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: !_isCustomMode ? FontWeight.bold : FontWeight.normal,
                                    color: !_isCustomMode ? AppColors.primary : AppColors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _isCustomMode = true),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _isCustomMode ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _isCustomMode
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 16,
                                  color: _isCustomMode ? AppColors.primary : AppColors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'تقسيط مخصص فوري',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: _isCustomMode ? FontWeight.bold : FontWeight.normal,
                                    color: _isCustomMode ? AppColors.primary : AppColors.onSurfaceVariant,
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
              ] else ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'لا توجد خطط تقسيط مسبقة. يمكنك إدخال تفاصيل التقسيط المخصص مباشرة:',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: AppColors.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Approved Plan Selector
              if (!_isCustomMode && widget.plans.isNotEmpty) ...[
                DropdownButtonFormField<InstallmentPlanEntity>(
                  isExpanded: true,
                  initialValue: _selectedPlan ?? widget.plans.first,
                  decoration: InputDecoration(
                    labelText: 'خطة التقسيط',
                    labelStyle: const TextStyle(fontFamily: 'Cairo'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.view_timeline_outlined),
                  ),
                  items: widget.plans
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(
                              '${p.name} (${p.durationMonths} شهور - فائدة ${p.interestBp / 100}%)',
                              style: const TextStyle(fontFamily: 'Cairo'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _onPlanChanged(v);
                  },
                ),
                const SizedBox(height: 12),
              ],

              // Custom Plan Inputs (Months & Interest Rate)
              if (_isCustomMode) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customMonthsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'مدة التقسيط (شهور) *',
                          labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                          helperText: 'من 1 إلى 60 شهراً',
                          helperStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10),
                          prefixIcon: const Icon(Icons.calendar_month_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _customInterestPctCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'نسبة الفائدة (%)',
                          labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                          helperText: '0% بدون فوائد',
                          helperStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10),
                          prefixIcon: const Icon(Icons.percent_rounded, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Interest model selector
              DropdownButtonFormField<InstallmentInterestModel>(
                isExpanded: true,
                initialValue: _selectedModel,
                decoration: InputDecoration(
                  labelText: 'نموذج الفائدة',
                  labelStyle: const TextStyle(fontFamily: 'Cairo'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.percent_rounded),
                ),
                items: InstallmentInterestModel.values
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                            _modelLabel(m, effectiveInterestPct),
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedModel = v);
                },
              ),
              const SizedBox(height: 12),

              // Down payment
              TextField(
                controller: _downPaymentCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'الدفعة المقدمة (بالجنيه)',
                  labelStyle: const TextStyle(fontFamily: 'Cairo'),
                  helperText: 'الحد الأقصى: ${Money(widget.totalPiasters).toDisplay()} ج.م (تُقيد بالخزينة فوراً)',
                  helperStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),

              // Live Financial Simulation Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'معاينة حساب التقسيط:',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          '$effectiveDuration شهور',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('أصل الفاتورة:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600)),
                        ),
                        Text('${Money(widget.totalPiasters).toDisplay()} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('المقدم المدفوع:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600)),
                        ),
                        Text('${Money(downPiasters).toDisplay()} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('المتبقي للتقسيط (أصل الدين):', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600)),
                        ),
                        Text('${Money(financedPiasters).toDisplay()} ج.م', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('الفائدة المحسوبة:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600)),
                        ),
                        Text(
                          totalInterestPiasters > 0
                              ? '${Money(totalInterestPiasters).toDisplay()} ج.م ($effectiveInterestPct%)'
                              : '0.00 ج.م (بدون فوائد)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: totalInterestPiasters > 0 ? AppColors.warning : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('القسط الشهري التقديري:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600)),
                        ),
                        Text(
                          '${Money(monthlyAmountPiasters).toDisplay()} ج.م / شهر',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('تاريخ أول قسط:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey.shade600)),
                        ),
                        Text(
                          DateFormat('yyyy/MM/dd').format(firstDueDate),
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade700),
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text('إجمالي التزام العميل:', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        Text(
                          '${Money(totalObligationPiasters).toDisplay()} ج.م',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (widget.pinRequired) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'الرقم السري للمدير (PIN)',
                    labelStyle: const TextStyle(fontFamily: 'Cairo'),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(fontFamily: 'Cairo', color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isValidating ? null : () => Navigator.pop(context),
          child: Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey.shade700)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          onPressed: _isValidating ? null : _submit,
          child: _isValidating
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('تأكيد التقسيط', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
