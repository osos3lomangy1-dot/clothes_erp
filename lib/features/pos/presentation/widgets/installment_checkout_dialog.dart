import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../installments/data/services/manager_pin_service.dart';
import '../../../installments/domain/entities/installment_plan_entity.dart';
import '../../../installments/domain/services/installment_calculator.dart';

class InstallmentCheckoutConfig {
  final String planId;
  final int downPaymentPiasters;
  final int interestBp;
  final InstallmentInterestModel interestModel;
  final int durationMonths;
  final String pin;

  const InstallmentCheckoutConfig({
    required this.planId,
    required this.downPaymentPiasters,
    required this.interestBp,
    required this.interestModel,
    required this.durationMonths,
    required this.pin,
  });
}

class InstallmentCheckoutDialog extends StatefulWidget {
  final List<InstallmentPlanEntity> plans;
  final int totalPiasters;
  final bool pinRequired;

  const InstallmentCheckoutDialog({
    super.key,
    required this.plans,
    required this.totalPiasters,
    required this.pinRequired,
  });

  @override
  State<InstallmentCheckoutDialog> createState() =>
      _InstallmentCheckoutDialogState();
}

class _InstallmentCheckoutDialogState extends State<InstallmentCheckoutDialog> {
  late InstallmentPlanEntity _selectedPlan;
  InstallmentInterestModel _selectedModel = InstallmentInterestModel.percentTotal;
  late final TextEditingController _downPaymentCtrl;
  final _pinCtrl = TextEditingController();
  String? _error;
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.plans.first;
    final initialDown = _selectedPlan.downPaymentPiasters > 0
        ? (_selectedPlan.downPaymentPiasters / 100).toStringAsFixed(0)
        : '0';
    _downPaymentCtrl = TextEditingController(text: initialDown);
    _downPaymentCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _downPaymentCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  String _modelLabel(InstallmentInterestModel m) {
    final interestPct = _selectedPlan.interestBp / 100.0;
    switch (m) {
      case InstallmentInterestModel.percentTotal:
        return 'نسبة إجمالية من أصل المبلغ ($interestPct%)';
      case InstallmentInterestModel.percentMonthly:
        return 'نسبة شهرية ($interestPct% شهرياً)';
      case InstallmentInterestModel.fixed:
        return 'مبلغ فائدة ثابت (${_selectedPlan.interestBp / 100} ج.م)';
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
        planId: _selectedPlan.id,
        downPaymentPiasters: downPaymentPiasters,
        interestBp: _selectedPlan.interestBp,
        interestModel: _selectedModel,
        durationMonths: _selectedPlan.durationMonths,
        pin: _pinCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Live calculation for preview
    final downDouble = double.tryParse(_downPaymentCtrl.text.trim()) ?? 0;
    final downPiasters = (downDouble * 100).round().clamp(0, widget.totalPiasters);
    final financedPiasters = (widget.totalPiasters - downPiasters).clamp(0, widget.totalPiasters);

    final scheduleResult = InstallmentCalculator.calculateSchedule(
      principalPiasters: widget.totalPiasters,
      durationMonths: _selectedPlan.durationMonths,
      interestModel: _selectedModel,
      interestValue: _selectedPlan.interestBp,
      downPaymentPiasters: downPiasters,
      startDate: DateTime.now(),
    );

    int totalInterestPiasters = 0;
    int monthlyAmountPiasters = 0;
    scheduleResult.fold((_) {}, (entries) {
      if (entries.isNotEmpty) {
        totalInterestPiasters = entries.fold<int>(0, (s, e) => s + e.interestComponentPiasters);
        monthlyAmountPiasters = entries.first.amountPiasters;
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
            child: const Icon(Icons.payments_rounded, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 10),
          Text(
            'تفاصيل التقسيط',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Plan selector
              DropdownButtonFormField<InstallmentPlanEntity>(
                initialValue: _selectedPlan,
                decoration: InputDecoration(
                  labelText: 'خطة التقسيط',
                  labelStyle: GoogleFonts.cairo(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.view_timeline_outlined),
                ),
                items: widget.plans
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.name} (${p.durationMonths} شهور - فائدة ${p.interestBp / 100}%)',
                            style: GoogleFonts.cairo(),
                          ),
                        ))
                    .toList(),
                onChanged: (v) => _onPlanChanged(v!),
              ),
              const SizedBox(height: 12),

              // Interest model
              DropdownButtonFormField<InstallmentInterestModel>(
                initialValue: _selectedModel,
                decoration: InputDecoration(
                  labelText: 'نموذج الفائدة',
                  labelStyle: GoogleFonts.cairo(),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.percent_rounded),
                ),
                items: InstallmentInterestModel.values
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(_modelLabel(m), style: GoogleFonts.cairo(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedModel = v!),
              ),
              const SizedBox(height: 12),

              // Down payment
              TextField(
                controller: _downPaymentCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'الدفعة المقدمة (بالجنيه)',
                  labelStyle: GoogleFonts.cairo(),
                  helperText: 'الحد الأقصى: ${Money(widget.totalPiasters).toDisplay()} ج.م',
                  helperStyle: GoogleFonts.cairo(fontSize: 11),
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),

              // Live Financial Simulation Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'معاينة حساب التقسيط:',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                        ),
                        Text(
                          '${_selectedPlan.durationMonths} شهور',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('أصل الفاتورة:', style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600)),
                        Text('${Money(widget.totalPiasters).toDisplay()} ج.م', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المقدم المدفوع:', style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600)),
                        Text('${Money(downPiasters).toDisplay()} ج.م', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF0284C7))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('الفائدة المحسوبة:', style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600)),
                        Text(
                          totalInterestPiasters > 0
                              ? '${Money(totalInterestPiasters).toDisplay()} ج.م (${_selectedPlan.interestBp / 100}%)'
                              : '0.00 ج.م (بدون فوائد)',
                          style: GoogleFonts.cairo(
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
                        Text('القسط الشهري التقديري:', style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600)),
                        Text(
                          '${Money(monthlyAmountPiasters).toDisplay()} ج.م / شهر',
                          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('إجمالي التزام العميل:', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text(
                          '${Money(totalObligationPiasters).toDisplay()} ج.م',
                          style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.onSurface),
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
                    labelStyle: GoogleFonts.cairo(),
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
                          style: GoogleFonts.cairo(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold),
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
          child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700)),
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
              : Text('تأكيد التقسيط', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
