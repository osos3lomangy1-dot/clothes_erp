
  import 'package:clothes_erp/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/customers/domain/entities/customer_entity.dart';
import '../../features/customers/presentation/cubits/customer_cubit.dart';

void showCustomerDialog(BuildContext context, {CustomerEntity? customer}) {
    final nameCtrl = TextEditingController(text: customer?.name ?? '');
    final phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    final pointsCtrl = TextEditingController(
      text: '${customer?.loyaltyPoints ?? 0}',
    );
    final discountCtrl = TextEditingController(
      text: customer != null && customer.discountPercent > 0 ? '${customer.discountPercent}' : '',
    );
    String selectedType = customer?.customerType ?? 'retail';
    final isEditing = customer != null;
    final cubit = context.read<CustomerCubit>();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.person_pin_rounded, color: AppColors.primary),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                final points = int.tryParse(pointsCtrl.text.trim()) ?? 0;
                final discount = int.tryParse(discountCtrl.text.trim()) ?? 0;

                if (name.isEmpty || phone.isEmpty) return;

                if (isEditing) {
                  await cubit.updateCustomer(
                    customer.copyWith(
                      name: name,
                      phone: phone,
                      loyaltyPoints: points,
                      discountPercent: discount,
                      customerType: selectedType,
                    ),
                  );
                } else {
                  await cubit.addCustomer(
                    CustomerEntity(
                      id: '',
                      name: name,
                      phone: phone,
                      loyaltyPoints: points,
                      discountPercent: discount,
                      customerType: selectedType,
                      createdAt: DateTime.now(),
                    ),
                  );
                }
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              },
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
      ),
    );
  }
