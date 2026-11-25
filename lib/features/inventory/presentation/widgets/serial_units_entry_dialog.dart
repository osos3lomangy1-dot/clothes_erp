import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';

class SerialUnitsEntryDialog extends StatefulWidget {
  final String productName;
  final int targetQty;
  final List<String> initialImeis;

  const SerialUnitsEntryDialog({
    super.key,
    required this.productName,
    required this.targetQty,
    this.initialImeis = const [],
  });

  static Future<List<String>?> show(
    BuildContext context, {
    required String productName,
    required int targetQty,
    List<String> initialImeis = const [],
  }) {
    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SerialUnitsEntryDialog(
        productName: productName,
        targetQty: targetQty,
        initialImeis: initialImeis,
      ),
    );
  }

  @override
  State<SerialUnitsEntryDialog> createState() => _SerialUnitsEntryDialogState();
}

class _SerialUnitsEntryDialogState extends State<SerialUnitsEntryDialog> {
  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  late List<String> _imeis;

  @override
  void initState() {
    super.initState();
    _imeis = List<String>.from(widget.initialImeis);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _addCurrent() {
    final code = _inputCtrl.text.trim();
    if (code.isEmpty) return;
    if (_imeis.any((e) => e.toLowerCase() == code.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم الـ IMEI مكرر بالفعل في القائمة'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() {
      _imeis.add(code);
      _inputCtrl.clear();
    });
    _inputFocus.requestFocus();
  }

  void _save() {
    Navigator.of(context).pop(_imeis);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.f12): _save,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AlertDialog(
        key: const Key('serial_units_entry_dialog'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'إدخال أرقام السيريال / IMEI (${_imeis.length}/${widget.targetQty})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الصنف: ${widget.productName}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('serial_imei_input_field'),
                      controller: _inputCtrl,
                      focusNode: _inputFocus,
                      autofocus: true,
                      onSubmitted: (_) => _addCurrent(),
                      decoration: InputDecoration(
                        labelText: 'امسح أو اكتب رقم IMEI واضغط Enter',
                        prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const Key('serial_imei_add_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _addCurrent,
                    child: const Text(
                      'إضافة',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_imeis.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'لا توجد أرقام مسجلة لهذا السطر (اختياري للإكسسوارات)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _imeis.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, idx) {
                      final code = _imeis[idx];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${idx + 1}. ',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Expanded(
                              child: Text(
                                code,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.error,
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _imeis.removeAt(idx)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            key: const Key('serial_imei_save_btn'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: _save,
            child: const Text(
              'حفظ الأرقام (F12)',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

