import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/supplier_entity.dart';

class SupplierPaymentDialog extends StatefulWidget {
  final SupplierEntity supplier;
  final String? purchaseId;
  final String? purchaseInvoiceNumber;
  final Function({
    required int amount,
    required DateTime paymentDate,
    required String paymentMethod,
    String? referenceNumber,
    String? notes,
  }) onSave;

  const SupplierPaymentDialog({
    super.key,
    required this.supplier,
    this.purchaseId,
    this.purchaseInvoiceNumber,
    required this.onSave,
  });

  @override
  State<SupplierPaymentDialog> createState() => _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState extends State<SupplierPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _refController = TextEditingController();
  final _notesController = TextEditingController();
  String _paymentMethod = 'كاش';
  final DateTime _paymentDate = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final pounds = double.tryParse(_amountController.text.trim()) ?? 0;
      final piasters = (pounds * 100).round();

      widget.onSave(
        amount: piasters,
        paymentDate: _paymentDate,
        paymentMethod: _paymentMethod,
        referenceNumber: _refController.text.trim().isEmpty ? null : _refController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.payments_rounded, color: Colors.green),
          SizedBox(width: 8),
          Text(
            'تسجيل سداد دفعة لمورد',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.supplier.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          if (widget.supplier.companyName != null)
                            Text(
                              widget.supplier.companyName!,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('إجمالي المديونية المستحقة:', style: TextStyle(fontSize: 11)),
                          Text(
                            widget.supplier.formattedBalance,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: widget.supplier.balance > 0 ? Colors.red.shade700 : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.purchaseInvoiceNumber != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'مرتبطة بفاتورة شراء: #${widget.purchaseInvoiceNumber}',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'مبلغ الدفعة المسدد (ج.م) *',
                    prefixIcon: const Icon(Icons.attach_money_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'يرجى إدخال المبلغ';
                    final val = double.tryParse(v.trim());
                    if (val == null || val <= 0) return 'المبلغ يجب أن يكون أكبر من صفر';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  decoration: InputDecoration(
                    labelText: 'طريقة الدفع',
                    prefixIcon: const Icon(Icons.account_balance_wallet_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'كاش', child: Text('كاش (نقدي)')),
                    DropdownMenuItem(value: 'تحويل بنكي', child: Text('تحويل بنكي')),
                    DropdownMenuItem(value: 'انستاباي', child: Text('انستاباي (InstaPay)')),
                    DropdownMenuItem(value: 'فودافون كاش', child: Text('محفظة إلكترونية')),
                    DropdownMenuItem(value: 'شيك', child: Text('شيك بنكي')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _paymentMethod = val);
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _refController,
                  decoration: InputDecoration(
                    labelText: 'رقم الإيصال / الحوالة (اختياري)',
                    prefixIcon: const Icon(Icons.receipt_long_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات إضافية',
                    prefixIcon: const Icon(Icons.note_alt_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _submit,
          child: const Text(
            'تأكيد وسداد الدفعة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

