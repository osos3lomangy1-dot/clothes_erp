import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../../core/utils/phone_validator.dart';
import '../../data/services/device_serial_service.dart';

class _VariantPickerOption {
  final String variantId;
  final String productName;
  final String sku;

  const _VariantPickerOption({
    required this.variantId,
    required this.productName,
    required this.sku,
  });
}

class UsedDeviceIntakeDialog extends StatefulWidget {
  final bool isTradeInMode;
  final String userId;

  const UsedDeviceIntakeDialog({
    super.key,
    this.isTradeInMode = false,
    this.userId = 'admin',
  });

  static Future<UsedDeviceIntakeResult?> show(
    BuildContext context, {
    bool isTradeInMode = false,
    String userId = 'admin',
  }) {
    return showDialog<UsedDeviceIntakeResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          UsedDeviceIntakeDialog(isTradeInMode: isTradeInMode, userId: userId),
    );
  }

  @override
  State<UsedDeviceIntakeDialog> createState() => _UsedDeviceIntakeDialogState();
}

class _UsedDeviceIntakeDialogState extends State<UsedDeviceIntakeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _imeiCtrl = TextEditingController();
  final _batteryCtrl = TextEditingController();
  final _buyPriceCtrl = TextEditingController();
  final _sellerNameCtrl = TextEditingController();
  final _sellerNationalIdCtrl = TextEditingController();
  final _sellerPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<_VariantPickerOption> _variants = [];
  String? _selectedVariantId;
  String _condition = 'used';
  late bool _deductFromDrawer;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _deductFromDrawer = !widget.isTradeInMode;
    _loadVariants();
  }

  @override
  void dispose() {
    _imeiCtrl.dispose();
    _batteryCtrl.dispose();
    _buyPriceCtrl.dispose();
    _sellerNameCtrl.dispose();
    _sellerNationalIdCtrl.dispose();
    _sellerPhoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadVariants() async {
    try {
      final db = getIt<AppDatabase>();
      final rows =
          await (db.select(db.productVariants).join([
                innerJoin(
                  db.products,
                  db.products.id.equalsExp(db.productVariants.productId),
                ),
              ])..where(
                db.productVariants.deletedAt.isNull() &
                    db.products.deletedAt.isNull(),
              ))
              .get();

      final list = rows.map((r) {
        final v = r.readTable(db.productVariants);
        final p = r.readTable(db.products);
        return _VariantPickerOption(
          variantId: v.id,
          productName: p.name,
          sku: v.sku,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _variants = list;
        if (list.isNotEmpty) {
          _selectedVariantId = list.first.variantId;
        }
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  DeviceSerialService _resolveSerialService() {
    if (getIt.isRegistered<DeviceSerialService>()) {
      return getIt<DeviceSerialService>();
    }
    final db = getIt<AppDatabase>();
    final bp = getIt.isRegistered<BranchProvider>()
        ? getIt<BranchProvider>()
        : BranchProvider(db);
    final tx = getIt.isRegistered<TxWriter>()
        ? getIt<TxWriter>()
        : TxWriter(db);
    return DeviceSerialService(db, bp, tx);
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    if (_formKey.currentState?.validate() != true) return;
    if (_selectedVariantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار الموديل / الصنف أولاً'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final selectedOption = _variants.firstWhere(
        (v) => v.variantId == _selectedVariantId,
      );
      final buyPricePiasters = Money.fromString(
        _buyPriceCtrl.text.trim(),
      ).piasters;
      final batteryText = _batteryCtrl.text.trim();
      final batteryHealth = batteryText.isEmpty
          ? null
          : int.tryParse(batteryText);

      final svc = _resolveSerialService();
      final result = await svc.registerUsedOrTradeInDevice(
        variantId: selectedOption.variantId,
        productName: selectedOption.productName,
        imei: _imeiCtrl.text.trim(),
        condition: _condition,
        batteryHealth: batteryHealth,
        notes: _notesCtrl.text.trim(),
        sellerName: _sellerNameCtrl.text.trim(),
        sellerNationalId: _sellerNationalIdCtrl.text.trim(),
        sellerPhone: _sellerPhoneCtrl.text.trim(),
        buyPricePiasters: buyPricePiasters,
        deductFromDrawer: widget.isTradeInMode ? false : _deductFromDrawer,
        userId: widget.userId,
      );

      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _submit,
        const SingleActivator(LogicalKeyboardKey.f12): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isSaving) Navigator.of(context).pop();
        },
      },
      child: AlertDialog(
        key: const Key('used_device_intake_dialog'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              widget.isTradeInMode
                  ? Icons.swap_horiz_rounded
                  : Icons.phone_android_rounded,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.isTradeInMode
                    ? 'استبدال جهاز مستعمل (Trade-in)'
                    : 'شراء جهاز مستعمل وتسجيل بياناته',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
        content: SizedBox(
          width: 540,
          child: _isLoading
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          key: const Key('used_device_variant_dropdown'),
                          initialValue: _selectedVariantId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'الموديل / الصنف *',
                            prefixIcon: const Icon(Icons.devices_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: _variants
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v.variantId,
                                  child: Text('${v.productName} (${v.sku})'),
                                ),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _selectedVariantId = val),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                key: const Key('used_device_imei_field'),
                                controller: _imeiCtrl,
                                autofocus: true,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'رقم السيريال / IMEI *',
                                  prefixIcon: const Icon(
                                    Icons.qr_code_2_rounded,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'رقم الـ IMEI مطلوب';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _condition,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'حالة الجهاز',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'used',
                                    child: Text('مستعمل'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'refurbished',
                                    child: Text('مجدد'),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _condition = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: const Key('used_device_buy_price_field'),
                                controller: _buyPriceCtrl,
                                textInputAction: TextInputAction.next,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: widget.isTradeInMode
                                      ? 'قيمة الاستبدال (ج.م) *'
                                      : 'سعر الشراء (ج.م) *',
                                  prefixIcon: const Icon(
                                    Icons.payments_outlined,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'مطلوب';
                                  }
                                  final n = double.tryParse(v.trim());
                                  if (n == null || n < 0) return 'سعر غير صالح';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                key: const Key('used_device_battery_field'),
                                controller: _batteryCtrl,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: 'نسبة البطارية % (اختياري)',
                                  prefixIcon: const Icon(
                                    Icons.battery_charging_full_rounded,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return null;
                                  }
                                  final b = int.tryParse(v.trim());
                                  if (b == null || b < 0 || b > 100) {
                                    return '0 إلى 100';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'بيانات البائع الأمنية (اختيارية)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: const Key('used_device_seller_name_field'),
                                controller: _sellerNameCtrl,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'اسم البائع',
                                  prefixIcon: const Icon(Icons.person_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                key: const Key(
                                  'used_device_seller_phone_field',
                                ),
                                controller: _sellerPhoneCtrl,
                                textInputAction: TextInputAction.next,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                validator: (v) => PhoneValidator.validate(
                                  v,
                                  required: false,
                                ),
                                decoration: InputDecoration(
                                  labelText: 'هاتف البائع',
                                  prefixIcon: const Icon(Icons.phone_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          key: const Key('used_device_national_id_field'),
                          controller: _sellerNationalIdCtrl,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.number,
                          maxLength: 14,
                          decoration: InputDecoration(
                            labelText: 'الرقم القومي للبائع (14 رقم - اختياري)',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            if (!RegExp(r'^\d{14}$').hasMatch(v.trim())) {
                              return 'الرقم القومي يجب أن يتكون من 14 رقماً';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _notesCtrl,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'ملاحظات حالة الجهاز (اختياري)',
                            prefixIcon: const Icon(Icons.notes_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        if (!widget.isTradeInMode) ...[
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _deductFromDrawer,
                            activeColor: AppColors.primary,
                            onChanged: (val) => setState(
                              () => _deductFromDrawer = val ?? false,
                            ),
                            title: const Text(
                              'خصم سعر الشراء كمصروف من الدرج النقدي',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            key: const Key('used_device_save_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _isSaving ? null : _submit,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, color: Colors.white),
            label: Text(
              widget.isTradeInMode
                  ? 'اعتماد الاستبدال (F12)'
                  : 'حفظ الجهاز (F12)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
