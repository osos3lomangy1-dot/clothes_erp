
import 'package:clothes_erp/core/constants/app_colors.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/core/utils/phone_validator.dart';
import 'package:clothes_erp/core/widgets/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/customers/domain/entities/customer_entity.dart';
import '../../features/customers/presentation/cubits/customer_cubit.dart';

Future<void> showCustomerDialog(BuildContext context, {CustomerEntity? customer}) async {
    bool creditEnabled = true;
    try {
      if (getIt.isRegistered<FeatureGate>()) {
        final gate = getIt<FeatureGate>();
        final meta = await gate.getMeta('payment.credit');
        creditEnabled = meta == null || meta != '0';
      }
    } catch (_) {}
    if (!context.mounted) return;
    final showCreditLimitField = creditEnabled || (customer != null && customer.creditLimit > 0);

    final nameCtrl = TextEditingController(text: customer?.name ?? '');
    final phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    final pointsCtrl = TextEditingController(
      text: '${customer?.loyaltyPoints ?? 0}',
    );
    final discountCtrl = TextEditingController(
      text: customer != null && customer.discountPercent > 0 ? '${customer.discountPercent}' : '',
    );
    final creditLimitCtrl = TextEditingController(
      text: customer != null && customer.creditLimit > 0
          ? (customer.creditLimit % 100 == 0
              ? '${customer.creditLimit ~/ 100}'
              : (customer.creditLimit / 100.0).toStringAsFixed(2))
          : '',
    );
    String selectedType = customer?.customerType ?? 'retail';
    final isEditing = customer != null;
    final cubit = context.read<CustomerCubit>();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submitCustomer() async {
            final name = nameCtrl.text.trim();
            final phone = phoneCtrl.text.trim();
            final points = int.tryParse(pointsCtrl.text.trim()) ?? 0;
            final discount = int.tryParse(discountCtrl.text.trim()) ?? 0;
            final creditLimitNum = double.tryParse(creditLimitCtrl.text.trim()) ?? 0.0;
            final creditLimit = (creditLimitNum * 100).round();

            if (name.isEmpty) {
              AppFeedback.showError(dialogCtx, 'يرجى إدخال اسم العميل');
              return;
            }
            final phoneError = PhoneValidator.validate(phone, required: true);
            if (phoneError != null) {
              AppFeedback.showError(dialogCtx, phoneError);
              return;
            }
            final normalizedPhone = PhoneValidator.normalize(phone);
            if (discount < 0 || discount > 100) {
              AppFeedback.showError(dialogCtx, 'نسبة الخصم يجب أن تكون بين 0% و 100%');
              return;
            }
            if (points < 0) {
              AppFeedback.showError(dialogCtx, 'رصيد نقاط الولاء لا يمكن أن يكون سالباً');
              return;
            }
            if (creditLimit < 0) {
              AppFeedback.showError(dialogCtx, 'الحد الائتماني لا يمكن أن يكون سالباً');
              return;
            }

            if (isEditing) {
              final ok = await cubit.updateCustomer(
                customer.copyWith(
                  name: name,
                  phone: normalizedPhone,
                  loyaltyPoints: points,
                  discountPercent: discount,
                  customerType: selectedType,
                  creditLimit: creditLimit,
                ),
              );
              if (!dialogCtx.mounted) return;
              if (ok) {
                Navigator.pop(dialogCtx);
                if (context.mounted) {
                  AppFeedback.showSuccess(context, 'تم تعديل بيانات العميل بنجاح');
                }
              } else {
                final err = cubit.state.errorMessage ?? 'تعذر تعديل بيانات العميل';
                AppFeedback.showError(
                  dialogCtx,
                  err.replaceFirst('Exception: ', ''),
                );
              }
            } else {
              final ok = await cubit.addCustomer(
                CustomerEntity(
                  id: '',
                  name: name,
                  phone: normalizedPhone,
                  loyaltyPoints: points,
                  discountPercent: discount,
                  customerType: selectedType,
                  creditLimit: creditLimit,
                  createdAt: DateTime.now(),
                ),
              );
              if (!dialogCtx.mounted) return;
              if (ok) {
                Navigator.pop(dialogCtx);
                if (context.mounted) {
                  AppFeedback.showSuccess(context, 'تمت إضافة العميل "$name" بنجاح');
                }
              } else {
                final err = cubit.state.errorMessage ?? 'تعذر إضافة العميل';
                AppFeedback.showError(
                  dialogCtx,
                  err.replaceFirst('Exception: ', ''),
                );
              }
            }
          }

          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  submitCustomer,
              const SingleActivator(LogicalKeyboardKey.f12): submitCustomer,
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.pop(dialogCtx),
            },
            child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.person_pin_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                isEditing ? 'تعديل بيانات العميل والمزايا' : 'إضافة عميل جديد',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'اسم العميل *',
                      hintText: 'مثال: محمد أحمد',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'رقم الهاتف *',
                      hintText: 'مثال: 01012345678',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: InputDecoration(
                      labelText: 'نوع العميل / التصنيف',
                      prefixIcon: const Icon(Icons.category_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'retail', child: Text('عميل عادي (قطاعي)')),
                      DropdownMenuItem(value: 'wholesale', child: Text('تاجر جملة (Wholesale)')),
                      DropdownMenuItem(value: 'vip', child: Text('عميل مميز (VIP)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedType = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: discountCtrl,
                          decoration: InputDecoration(
                            labelText: 'نسبة خصم دائمة للعميل (%)',
                            hintText: 'مثال: 5 أو 10',
                            suffixText: '%',
                            prefixIcon: const Icon(Icons.percent_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: pointsCtrl,
                          decoration: InputDecoration(
                            labelText: 'رصيد نقاط الولاء',
                            prefixIcon: const Icon(Icons.stars_rounded, color: Colors.amber),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  if (showCreditLimitField) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: creditLimitCtrl,
                      decoration: InputDecoration(
                        labelText: 'الحد الأقصى للآجل (الائتماني)',
                        hintText: 'اتركه فارغاً أو 0 إذا كان غير مقيد',
                        suffixText: 'ج.م',
                        prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              key: const Key('customer_dialog_save_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: submitCustomer,
              child: Text(
                isEditing ? 'حفظ التعديلات' : 'إضافة العميل',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
            ),
          );
        },
      ),
    );
  }
