import 'package:flutter/material.dart';

import '../../../../core/utils/money.dart';
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
  InstallmentInterestModel _selectedModel = InstallmentInterestModel.fixed;
  final _downPaymentCtrl = TextEditingController(text: '0');
  final _pinCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedPlan = widget.plans.first;
  }

  @override
  void dispose() {
    _downPaymentCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  String _modelLabel(InstallmentInterestModel m) {
    switch (m) {
      case InstallmentInterestModel.fixed:
        return 'فائدة ثابتة';
      case InstallmentInterestModel.percentTotal:
        return 'نسبة من أصل المبلغ';
      case InstallmentInterestModel.percentMonthly:
        return 'نسبة شهرية';
    }
  }

  void _submit() {
    final downDouble = double.tryParse(_downPaymentCtrl.text.trim()) ?? 0;
    final downPaymentPiasters = (downDouble * 100).round();

    if (downPaymentPiasters < 0 || downPaymentPiasters > widget.totalPiasters) {
      setState(() => _error =
          'الدفعة المقدمة يجب أن تكون بين 0 و ${Money(widget.totalPiasters).toDisplay()}');
      return;
    }
    if (widget.pinRequired && _pinCtrl.text.trim().isEmpty) {
      setState(() => _error = 'أدخل رقم PIN للمدير');
      return;
    }

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
    return AlertDialog(
      title: const Text('تفاصيل التقسيط'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<InstallmentPlanEntity>(
              initialValue: _selectedPlan,
              decoration: const InputDecoration(
                labelText: 'الخطة',
                border: OutlineInputBorder(),
              ),
              items: widget.plans
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedPlan = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<InstallmentInterestModel>(
              initialValue: _selectedModel,
              decoration: const InputDecoration(
                labelText: 'نموذج الفائدة',
                border: OutlineInputBorder(),
              ),
              items: InstallmentInterestModel.values
                  .map((m) =>
                      DropdownMenuItem(value: m, child: Text(_modelLabel(m))))
                  .toList(),
              onChanged: (v) => setState(() => _selectedModel = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _downPaymentCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'الدفعة المقدمة (بالجنيه)',
                helperText:
                    'الحد الأقصى: ${Money(widget.totalPiasters).toDisplay()}',
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.pinRequired) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'PIN المدير',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('تأكيد'),
        ),
      ],
    );
  }
}
