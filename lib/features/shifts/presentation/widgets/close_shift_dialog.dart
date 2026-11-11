import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/shift_summary_entity.dart';

class CloseShiftDialog extends StatefulWidget {
  final ShiftSummaryEntity summary;
  final Future<dynamic> Function(int countedBalancePiasters) onClose;

  const CloseShiftDialog({
    super.key,
    required this.summary,
    required this.onClose,
  });

  @override
  State<CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<CloseShiftDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _countedController;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final expectedPounds = (widget.summary.expectedCashInDrawer / 100.0).toStringAsFixed(2);
    _countedController = TextEditingController(text: expectedPounds);
  }

  @override
  void dispose() {
    _countedController.dispose();
    super.dispose();
  }

  String _normalizeNumbers(String input) {
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    var res = input;
    for (int i = 0; i < 10; i++) {
      res = res.replaceAll(arabic[i], english[i]);
    }
    return res;
  }

  double get _countedPounds {
    final norm = _normalizeNumbers(_countedController.text.trim());
    return double.tryParse(norm) ?? 0.0;
  }

  double get _expectedPounds {
    return widget.summary.expectedCashInDrawer / 100.0;
  }

  double get _diffPounds => _countedPounds - _expectedPounds;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final piasters = (_countedPounds * 100).round();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.onClose(piasters);
      if (!mounted) return;

      if (res is String && res.isNotEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = res;
        });
      } else if (res == false) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'تعذر إغلاق الوردية. يرجى إعادة المحاولة.';
        });
      } else {
        setState(() => _isLoading = false);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Color diffColor;
    String diffLabel;
    if (_diffPounds.abs() < 0.01) {
      diffColor = Colors.green.shade700;
      diffLabel = 'الدرج مطابق تماماً (0.00 ج.م)';
    } else if (_diffPounds > 0) {
      diffColor = Colors.blue.shade700;
      diffLabel = 'زيادة في الدرج: +${_diffPounds.toStringAsFixed(2)} ج.م';
    } else {
      diffColor = AppColors.error;
      diffLabel = 'عجز في الدرج: ${_diffPounds.toStringAsFixed(2)} ج.م';
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.lock_clock_rounded, color: Colors.red.shade700, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إغلاق وتصفية الوردية',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'مطابقة النقدية الفعلية مع حركة مبيعات ومصروفات الوردية',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade900, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      _rowDetail('الرصيد الافتتاحي (الفكة):', '${Money(widget.summary.shift.openingBalance).toDisplay()} ج.م'),
                      const Divider(height: 14),
                      _rowDetail('مبيعات نقدية (كاش):', '+${Money(widget.summary.cashSales).toDisplay()} ج.م', color: Colors.green.shade700),
                      if (widget.summary.cashReturns > 0) ...[
                        const Divider(height: 14),
                        _rowDetail('مرتجعات نقدية:', '-${Money(widget.summary.cashReturns).toDisplay()} ج.م', color: Colors.orange.shade800),
                      ],
                      if (widget.summary.cashExpenses > 0) ...[
                        const Divider(height: 14),
                        _rowDetail('مصروفات من الدرج:', '-${Money(widget.summary.cashExpenses).toDisplay()} ج.م', color: AppColors.error),
                      ],
                      const Divider(height: 14, thickness: 1.5),
                      _rowDetail(
                        'المبلغ المتوقع في الدرج:',
                        '${Money(widget.summary.expectedCashInDrawer).toDisplay()} ج.م',
                        isBold: true,
                        color: AppColors.primary,
                      ),
                      if (widget.summary.cardSales > 0) ...[
                        const SizedBox(height: 8),
                        _rowDetail('مبيعات الفيزا / الإلكترونية (غير كاش):', '${Money(widget.summary.cardSales).toDisplay()} ج.م', color: Colors.grey.shade600),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _countedController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'المبلغ الفعلي الموجود في الدرج الآن (ج.م) *',
                    prefixIcon: const Icon(Icons.point_of_sale_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'يرجى إدخال المبلغ المحسوب في الدرج';
                    final norm = _normalizeNumbers(v.trim());
                    final val = double.tryParse(norm);
                    if (val == null || val < 0) return 'المبلغ لا يمكن أن يكون سالباً';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: diffColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: diffColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    diffLabel,
                    style: TextStyle(color: diffColor, fontWeight: FontWeight.bold, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: _isLoading ? null : _submit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                      label: const Text(
                        'إغلاق الوردية نهائياً',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rowDetail(String label, String value, {Color? color, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}
