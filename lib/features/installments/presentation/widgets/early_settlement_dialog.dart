import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/customer_installment_entity.dart';
import '../../domain/entities/installment_plan_entity.dart';
import '../../domain/services/installment_calculator.dart';

class EarlySettlementSubmission {
  final int waivedInterestPiasters;
  final int settlementAmountPiasters;
  final String paymentMethod;
  final String pin;
  final String? notes;
  final DateTime settledAt;

  const EarlySettlementSubmission({
    required this.waivedInterestPiasters,
    required this.settlementAmountPiasters,
    required this.paymentMethod,
    required this.pin,
    this.notes,
    required this.settledAt,
  });
}

class EarlySettlementDialog extends StatefulWidget {
  final CustomerInstallmentEntity contract;
  final int totalContractInterestPiasters;
  final int paidTowardsScheduleCashPiasters;
  final List<InstallmentPlanEntity> activePlans;
  final bool isPinRequired;

  const EarlySettlementDialog({
    super.key,
    required this.contract,
    required this.totalContractInterestPiasters,
    required this.paidTowardsScheduleCashPiasters,
    required this.activePlans,
    required this.isPinRequired,
  });

  @override
  State<EarlySettlementDialog> createState() => _EarlySettlementDialogState();
}

class _EarlySettlementDialogState extends State<EarlySettlementDialog> {
  late EarlySettlementMode _mode;
  late int _usedMonths;
  InstallmentPlanEntity? _selectedAlternatePlan;
  DateTime _settlementDate = DateTime.now();
  String _paymentMethod = 'cash';

  final _customWaiverCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final initialCalc = InstallmentCalculator.calculateEarlySettlement(
      financedPrincipalPiasters: widget.contract.principalPiasters,
      totalContractInterestPiasters: widget.totalContractInterestPiasters,
      paidTowardsSchedulePiasters: widget.paidTowardsScheduleCashPiasters,
      currentRemainingPiasters: widget.contract.remainingPiasters,
      durationMonths: widget.contract.durationMonths,
      startDate: widget.contract.startDate,
      settlementDate: _settlementDate,
      mode: EarlySettlementMode.fullWaiver,
    );

    // Auto-select full waiver if within 14-day grace period; otherwise proportional months
    _mode = initialCalc.isWithinGracePeriod
        ? EarlySettlementMode.fullWaiver
        : EarlySettlementMode.proportionalMonths;
    _usedMonths = initialCalc.suggestedUsedMonths > 0
        ? initialCalc.suggestedUsedMonths
        : 1;
    if (widget.activePlans.isNotEmpty) {
      _selectedAlternatePlan = widget.activePlans.first;
    }

    _customWaiverCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _customWaiverCtrl.dispose();
    _notesCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  EarlySettlementCalculation _compute() {
    final customDouble = double.tryParse(_customWaiverCtrl.text.trim()) ?? 0;
    final customPiasters = (customDouble * 100).round();

    return InstallmentCalculator.calculateEarlySettlement(
      financedPrincipalPiasters: widget.contract.principalPiasters,
      totalContractInterestPiasters: widget.totalContractInterestPiasters,
      paidTowardsSchedulePiasters: widget.paidTowardsScheduleCashPiasters,
      currentRemainingPiasters: widget.contract.remainingPiasters,
      durationMonths: widget.contract.durationMonths,
      startDate: widget.contract.startDate,
      settlementDate: _settlementDate,
      mode: _mode,
      usedMonthsOverride: _usedMonths,
      alternatePlanInterestBp: _selectedAlternatePlan?.interestBp ?? 0,
      customWaiverPiasters: customPiasters,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _settlementDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      setState(() {
        _settlementDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          now.hour,
          now.minute,
          now.second,
        );
      });
    }
  }

  String _autoReasonNote(EarlySettlementCalculation calc) {
    final custom = _notesCtrl.text.trim();
    if (custom.isNotEmpty) return custom;
    switch (_mode) {
      case EarlySettlementMode.fullWaiver:
        return 'إعفاء كامل من الفائدة (سداد كاش خلال ${calc.elapsedDays} يوم)';
      case EarlySettlementMode.proportionalMonths:
        return 'احتساب فائدة $_usedMonths شهر من أصل ${widget.contract.durationMonths} شهور';
      case EarlySettlementMode.alternatePlan:
        return 'تطبيق نسبة خطة "${_selectedAlternatePlan?.name ?? ''}"';
      case EarlySettlementMode.customWaiver:
        return 'تسوية بإعفاء مخصص بقرار المدير';
    }
  }

  void _submit(EarlySettlementCalculation calc) {
    if (widget.isPinRequired && _pinCtrl.text.trim().isEmpty) {
      setState(() => _error = 'الرجاء إدخال الرقم السري للمدير (PIN) لإتمام التسوية');
      return;
    }

    if (_mode == EarlySettlementMode.customWaiver) {
      final raw = double.tryParse(_customWaiverCtrl.text.trim());
      if (raw == null || raw < 0) {
        setState(() => _error = 'الرجاء إدخال مبلغ إعفاء صحيح');
        return;
      }
      final piasters = (raw * 100).round();
      if (piasters > calc.maxWaivableInterestPiasters) {
        setState(() => _error =
            'الحد الأقصى للإعفاء هو ${Money(calc.maxWaivableInterestPiasters).toDisplay()} ج.م (لا يمكن النزول عن أصل الفاتورة)');
        return;
      }
    }

    Navigator.of(context).pop(
      EarlySettlementSubmission(
        waivedInterestPiasters: calc.waivedInterestPiasters,
        settlementAmountPiasters: calc.settlementAmountPiasters,
        paymentMethod: _paymentMethod,
        pin: _pinCtrl.text.trim(),
        notes: _autoReasonNote(calc),
        settledAt: _settlementDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final calc = _compute();
    final hasPlans = widget.activePlans.isNotEmpty;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bolt_rounded, color: Colors.teal.shade700, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'السداد المبكر / تسوية العقد',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 17),
                ),
                Text(
                  'إغلاق العقد بالكامل مع إعادة حساب أو إعفاء الفائدة',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grace period hint
              if (calc.isWithinGracePeriod)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_rounded, color: Colors.green.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'مضى ${calc.elapsedDays} يوم فقط منذ الشراء (ضمن فترة السماح 14 يوماً) — تم اختيار الإعفاء الكامل من الفائدة تلقائياً.',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Settlement Mode Selection
              const Text(
                'طريقة تسوية الفائدة:',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _modeChip(
                    mode: EarlySettlementMode.fullWaiver,
                    label: 'إعفاء كامل (بدون فائدة)',
                    icon: Icons.money_off_csred_rounded,
                  ),
                  _modeChip(
                    mode: EarlySettlementMode.proportionalMonths,
                    label: 'حسب الشهور الفعلية',
                    icon: Icons.calendar_month_rounded,
                  ),
                  if (hasPlans)
                    _modeChip(
                      mode: EarlySettlementMode.alternatePlan,
                      label: 'نسبة خطة أخرى',
                      icon: Icons.swap_horiz_rounded,
                    ),
                  _modeChip(
                    mode: EarlySettlementMode.customWaiver,
                    label: 'إعفاء مخصص',
                    icon: Icons.tune_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Mode-specific controls
              if (_mode == EarlySettlementMode.proportionalMonths) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'عدد الشهور الفعلية المحتسبة:',
                            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          Text(
                            'من أصل ${widget.contract.durationMonths} شهور (المدة الأصلية)',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _usedMonths > 0
                                ? () => setState(() => _usedMonths--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                            color: AppColors.primary,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              '$_usedMonths شهر',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _usedMonths < widget.contract.durationMonths
                                ? () => setState(() => _usedMonths++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              if (_mode == EarlySettlementMode.alternatePlan && hasPlans) ...[
                DropdownButtonFormField<InstallmentPlanEntity>(
                  initialValue: _selectedAlternatePlan,
                  decoration: InputDecoration(
                    labelText: 'اختر الخطة البديلة لحساب الفائدة',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.view_timeline_outlined),
                  ),
                  items: widget.activePlans
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(
                              '${p.name} (${p.durationMonths} شهور - فائدة ${p.interestBp / 100}%)',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedAlternatePlan = v),
                ),
                const SizedBox(height: 14),
              ],

              if (_mode == EarlySettlementMode.customWaiver) ...[
                TextField(
                  controller: _customWaiverCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'مبلغ الفائدة المُعفى (بالجنيه)',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                    helperText:
                        'الحد الأقصى للإعفاء: ${Money(calc.maxWaivableInterestPiasters).toDisplay()} ج.م (لحماية أصل المبلغ)',
                    helperStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                    suffixText: 'ج.م',
                    prefixIcon: const Icon(Icons.local_offer_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Financial Breakdown Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  children: [
                    _summaryRow(
                      'الرصيد المتبقي قبل التسوية:',
                      '${Money(calc.currentRemainingPiasters).toDisplay()} ج.م',
                    ),
                    const SizedBox(height: 5),
                    _summaryRow(
                      'أصل المبلغ المموَّل (بدون فوائد):',
                      '${Money(calc.financedPrincipalPiasters).toDisplay()} ج.م',
                    ),
                    const SizedBox(height: 5),
                    _summaryRow(
                      'الفائدة الأصلية للعقد:',
                      '${Money(calc.totalContractInterestPiasters).toDisplay()} ج.م',
                    ),
                    const SizedBox(height: 5),
                    _summaryRow(
                      'الفائدة المستحقة بعد التسوية:',
                      '${Money(calc.applicableInterestPiasters).toDisplay()} ج.م',
                    ),
                    const SizedBox(height: 6),
                    _summaryRow(
                      'إعفاء الفائدة (الخصم للعميل):',
                      '- ${Money(calc.waivedInterestPiasters).toDisplay()} ج.م',
                      valueColor: Colors.purple.shade700,
                      bold: true,
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'المطلوب سداده الآن لإغلاق العقد:',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${Money(calc.settlementAmountPiasters).toDisplay()} ج.م',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Date & Payment Method Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_rounded, size: 16),
                      label: Text(
                        'التاريخ: ${DateFormat('yyyy/MM/dd').format(_settlementDate)}',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('نقدي', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    selected: _paymentMethod == 'cash',
                    onSelected: (v) {
                      if (v) setState(() => _paymentMethod = 'cash');
                    },
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('بطاقة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    selected: _paymentMethod == 'card',
                    onSelected: (v) {
                      if (v) setState(() => _paymentMethod = 'card');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Optional notes
              TextField(
                controller: _notesCtrl,
                decoration: InputDecoration(
                  labelText: 'ملاحظات التسوية (اختياري)',
                  labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
              // Manager PIN (hidden completely when disabled in settings)
              if (widget.isPinRequired) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'الرقم السري للمدير (PIN) *',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey.shade700)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.check_circle_rounded, size: 18),
          label: Text(
            'تأكيد التسوية (${Money(calc.settlementAmountPiasters).toDisplay()} ج.م)',
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          onPressed: () => _submit(calc),
        ),
      ],
    );
  }

  Widget _modeChip({
    required EarlySettlementMode mode,
    required String label,
    required IconData icon,
  }) {
    final selected = _mode == mode;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? AppColors.primary : Colors.grey.shade600,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? AppColors.primary : AppColors.onSurface,
        ),
      ),
      selected: selected,
      selectedColor: AppColors.primary.withValues(alpha: 0.14),
      onSelected: (_) => setState(() {
        _mode = mode;
        _error = null;
      }),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: Colors.grey.shade700,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}

