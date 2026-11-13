import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/show_customer_dialog.dart';
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
              onPressed: () => showCustomerDialog(context),
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
                    if (state.status == CustomerStatus.error && state.customers.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 64,
                              color: AppColors.error,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              state.errorMessage ?? 'حدث خطأ أثناء تحميل بيانات العملاء',
                              style: const TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => context.read<CustomerCubit>().loadCustomers(),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('إعادة المحاولة', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    if (state.customers.isEmpty) {
                      return AppEmptyState(
                        icon: Icons.people_outline_rounded,
                        title: _searchCtrl.text.isEmpty
                            ? 'لا يوجد عملاء مسجلون حتى الآن'
                            : 'لا يوجد عملاء يطابقون "${_searchCtrl.text}"',
                        subtitle: _searchCtrl.text.isEmpty
                            ? 'قم بإضافة عملاء جدد لحفظ نقاط الولاء والخصومات الخاصة بهم.'
                            : 'تأكد من كتابة الاسم أو رقم الهاتف بشكل صحيح.',
                        actionLabel: _searchCtrl.text.isEmpty ? 'إضافة عميل جديد' : null,
                        onAction: _searchCtrl.text.isEmpty ? () => showCustomerDialog(context) : null,
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
                                  onPressed: () => showCustomerDialog(
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

  Future<void> _confirmDelete(BuildContext context, CustomerEntity customer) async {
    final confirmed = await AppFeedback.confirmDelete(
      context: context,
      title: 'تأكيد حذف العميل',
      content: 'هل أنت متأكد من حذف العميل "${customer.name}"؟ سيتم حذف بيانات نقاطه وتصنيفه.',
    );

    if (confirmed && context.mounted) {
      await context.read<CustomerCubit>().deleteCustomer(customer.id);
      if (context.mounted) {
        AppFeedback.showSuccess(context, 'تم حذف العميل "${customer.name}" بنجاح');
      }
    }
  }
}
