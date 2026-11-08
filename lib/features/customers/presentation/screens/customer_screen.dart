import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../domain/entities/customer_entity.dart';
import '../cubits/customer_cubit.dart';

class CustomerScreen extends StatelessWidget {
  const CustomerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<CustomerCubit>(),
      child: const _CustomerView(),
    );
  }
}

class _CustomerView extends StatefulWidget {
  const _CustomerView();

  @override
  State<_CustomerView> createState() => _CustomerViewState();
}

class _CustomerViewState extends State<_CustomerView> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'سجل العملاء والمزايا',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'إدارة بيانات العملاء ونسب الخصم وتصنيف الجملة/القطاعي ونقاط الولاء',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: ElevatedButton.icon(
              icon: const Icon(
                Icons.person_add_rounded,
                color: Colors.white,
                size: 18,
              ),
              label: const Text(
                'إضافة عميل جديد',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _showCustomerDialog(context),
            ),
          ),
        ],
      ),
      body: BlocConsumer<CustomerCubit, CustomerState>(
        listener: (context, state) {
          if (state.status == CustomerStatus.error &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        builder: (context, state) {
          return Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'البحث عن عميل بالاسم أو رقم الهاتف...',
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.primary,
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    context
                                        .read<CustomerCubit>()
                                        .searchCustomers('');
                                    setState(() {});
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppColors.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (query) {
                          context
                              .read<CustomerCubit>()
                              .searchCustomers(query);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (state.status == CustomerStatus.loading) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (state.customers.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.people_outline_rounded,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchCtrl.text.isEmpty
                                  ? 'لا يوجد عملاء مسجلون حتى الآن. اضغط على "إضافة عميل جديد" للبدء.'
                                  : 'لا يوجد عملاء يطابقون "${_searchCtrl.text}".',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.customers.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final customer = state.customers[index];
                        final isWholesale = customer.isWholesale;
                        final isVip = customer.isVip;

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isWholesale
                                  ? Colors.purple.shade50
                                  : isVip
                                      ? Colors.amber.shade50
                                      : AppColors.primary.withValues(alpha: 0.12),
                              child: Icon(
                                isWholesale
                                    ? Icons.storefront_rounded
                                    : isVip
                                        ? Icons.workspace_premium_rounded
                                        : Icons.person_rounded,
                                color: isWholesale
                                    ? Colors.purple.shade700
                                    : isVip
                                        ? Colors.amber.shade800
                                        : AppColors.primary,
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  customer.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isWholesale)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.purple.shade200),
                                    ),
                                    child: Text(
                                      'تاجر جملة',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade800),
                                    ),
                                  )
                                else if (isVip)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.amber.shade200),
                                    ),
                                    child: Text(
                                      'عميل مميز (VIP)',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                    ),
                                  ),
                                if (customer.discountPercent > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.green.shade300),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.percent_rounded, size: 12, color: Colors.green),
                                        Text(
                                          'خصم ${customer.discountPercent}%',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Row(
                                children: [
                                  Text(
                                    customer.phone,
                                    style: TextStyle(color: Colors.grey.shade700),
                                  ),
                                  const SizedBox(width: 14),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.amber.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          size: 14,
                                          color: Colors.amber,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${customer.loyaltyPoints} نقطة',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: AppColors.primary,
                                  ),
                                  tooltip: 'تعديل بيانات العميل ومزاياه',
                                  onPressed: () => _showCustomerDialog(
                                    context,
                                    customer: customer,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppColors.error,
                                  ),
                                  tooltip: 'حذف العميل',
                                  onPressed: () => _confirmDelete(
                                    context,
                                    customer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCustomerDialog(BuildContext context, {CustomerEntity? customer}) {
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

  void _confirmDelete(BuildContext context, CustomerEntity customer) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف العميل "${customer.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () {
              context.read<CustomerCubit>().deleteCustomer(customer.id);
              Navigator.pop(dialogCtx);
            },
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
