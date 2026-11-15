import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/payment_split.dart';

class SplitPaymentDialog extends StatefulWidget {
  final int totalPiasters;

  const SplitPaymentDialog({
    super.key,
    required this.totalPiasters,
  });

  @override
  State<SplitPaymentDialog> createState() => _SplitPaymentDialogState();
}

class _SplitPaymentDialogState extends State<SplitPaymentDialog> {
  late final TextEditingController _cashCtrl;
  late final TextEditingController _cardCtrl;
  bool _isUpdating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default split: half cash, half card
    final halfPiasters = widget.totalPiasters ~/ 2;
    final otherHalf = widget.totalPiasters - halfPiasters;

    _cashCtrl = TextEditingController(text: (halfPiasters / 100).toStringAsFixed(2));
    _cardCtrl = TextEditingController(text: (otherHalf / 100).toStringAsFixed(2));

    _cashCtrl.addListener(_onCashChanged);
    _cardCtrl.addListener(_onCardChanged);
  }

  void _onCashChanged() {
    if (_isUpdating) return;
    final cashEgp = double.tryParse(_cashCtrl.text.trim()) ?? 0;
    final cashPiasters = (cashEgp * 100).round();
    final remainingPiasters = widget.totalPiasters - cashPiasters;

    _isUpdating = true;
    _cardCtrl.text = (remainingPiasters / 100).toStringAsFixed(2);
    _isUpdating = false;

    _validate();
  }

  void _onCardChanged() {
    if (_isUpdating) return;
    final cardEgp = double.tryParse(_cardCtrl.text.trim()) ?? 0;
    final cardPiasters = (cardEgp * 100).round();
    final remainingPiasters = widget.totalPiasters - cardPiasters;

    _isUpdating = true;
    _cashCtrl.text = (remainingPiasters / 100).toStringAsFixed(2);
    _isUpdating = false;

    _validate();
  }

  void _validate() {
    final cashPiasters = ((double.tryParse(_cashCtrl.text.trim()) ?? 0) * 100).round();
    final cardPiasters = ((double.tryParse(_cardCtrl.text.trim()) ?? 0) * 100).round();

    setState(() {
      if (cashPiasters < 0 || cardPiasters < 0) {
        _error = 'المبالغ لا يمكن أن تكون سالبة';
      } else if (cashPiasters + cardPiasters != widget.totalPiasters) {
        _error = 'مجموع الدفع (${Money(cashPiasters + cardPiasters).toDisplay()} ج.م) يجب أن يساوي إجمالي الفاتورة (${Money(widget.totalPiasters).toDisplay()} ج.م)';
      } else if (cashPiasters == 0 || cardPiasters == 0) {
        _error = 'الدفع المجزأ يتطلب مبالغ أكبر من صفر لكل من الكاش والشبكة';
      } else {
        _error = null;
      }
    });
  }

  void _submit() {
    final cashPiasters = ((double.tryParse(_cashCtrl.text.trim()) ?? 0) * 100).round();
    final cardPiasters = ((double.tryParse(_cardCtrl.text.trim()) ?? 0) * 100).round();

    if (cashPiasters + cardPiasters != widget.totalPiasters || cashPiasters <= 0 || cardPiasters <= 0) {
      _validate();
      return;
    }

    Navigator.pop(context, [
      PaymentSplit(method: 'cash', amountPiasters: cashPiasters),
      PaymentSplit(method: 'card', amountPiasters: cardPiasters),
    ]);
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.call_split_rounded, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'دفع مجزأ (كاش + شبكة)',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('إجمالي الفاتورة المطلوب:', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
                    Text(
                      '${Money(widget.totalPiasters).toDisplay()} ج.م',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cashCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                decoration: InputDecoration(
                  labelText: 'المدفوع نقداً (كاش) ج.م',
                  prefixIcon: const Icon(Icons.money_rounded, color: Colors.green),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cardCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                decoration: InputDecoration(
                  labelText: 'المدفوع بالبطاقة (فيزا / شبكة) ج.م',
                  prefixIcon: const Icon(Icons.credit_card_rounded, color: Colors.blue),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(fontFamily: 'Cairo', color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _error == null ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('تأكيد الدفع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

