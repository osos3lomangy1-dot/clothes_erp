import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/installment_plan_entity.dart';
import '../cubits/installment_plans_cubit.dart';

class InstallmentPlansScreen extends StatelessWidget {
  const InstallmentPlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<InstallmentPlansCubit>(),
      child: const _InstallmentPlansView(),
    );
  }
}

class _InstallmentPlansView extends StatefulWidget {
  const _InstallmentPlansView();

  @override
  State<_InstallmentPlansView> createState() => _InstallmentPlansViewState();
}

class _InstallmentPlansViewState extends State<_InstallmentPlansView> {
  @override
  void initState() {
    super.initState();
    _guardFeature();
    _checkAdminAccess();
  }

  Future<void> _guardFeature() async {
    final enabled = await getIt<FeatureGate>().isEnabled(FeatureKeys.installments);
    if (!enabled && mounted) {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ميزة التقسيط غير مفعلة')),
      );
    }
  }

  void _checkAdminAccess() async {
    final featureGate = getIt<FeatureGate>();
    final isAdmin = await featureGate.isCurrentUserAdmin();
    if (!isAdmin && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('غير مصرح: إدارة خطط التقسيط متاحة للمدير فقط'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<InstallmentPlansCubit>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'خطط التقسيط',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            tooltip: 'تحديث',
            onPressed: () => cubit.loadPlans(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPlanDialog(context, cubit),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('إضافة خطة جديدة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: BlocConsumer<InstallmentPlansCubit, InstallmentPlansState>(
        listener: (context, state) {
          if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!), backgroundColor: Colors.red),
            );
          }
        },
        builder: (context, state) {
          if (state.status == InstallmentPlansStatus.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.status == InstallmentPlansStatus.error) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text('خطأ: ${state.errorMessage ?? "تعذر تحميل خطط التقسيط"}'),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => cubit.loadPlans(), child: const Text('إعادة المحاولة')),
                ],
              ),
            );
          }

          if (state.plans.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt_rounded, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('لا توجد خطط تقسيط معرفة حتى الآن', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showPlanDialog(context, cubit),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('إضافة أول خطة'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: state.plans.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final plan = state.plans[index];
              return _PlanCard(
                plan: plan,
                onEdit: () => _showPlanDialog(context, cubit, plan: plan),
                onDeactivate: () => _confirmDeactivate(context, cubit, plan),
              );
            },
          );
        },
      ),
    );
  }

  void _showPlanDialog(
    BuildContext context,
    InstallmentPlansCubit cubit, {
    InstallmentPlanEntity? plan,
  }) {
    final isEditing = plan != null;
    final nameController = TextEditingController(text: plan?.name ?? '');
    final descController = TextEditingController(text: plan?.description ?? '');
    final durationController = TextEditingController(text: plan != null ? '${plan.durationMonths}' : '6');
    final downPaymentController = TextEditingController(
      text: plan != null ? '${plan.downPaymentPiasters ~/ 100}' : '0',
    );
    final interestPercentController = TextEditingController(
      text: plan != null ? '${plan.interestBp / 100}' : '0',
    );

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(isEditing ? 'تعديل خطة التقسيط' : 'إضافة خطة تقسيط جديدة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'اسم الخطة (مثال: خطة 6 أشهر)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'الوصف (اختياري)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: durationController,
                keyboardType: TextInputType.number,
                enabled: !isEditing, // Duration immutable once created if contracts linked
                decoration: const InputDecoration(labelText: 'المدة بالشهور', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: downPaymentController,
                keyboardType: TextInputType.number,
                enabled: !isEditing,
                decoration: const InputDecoration(labelText: 'الدفعة المقدمة (ج.م)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: interestPercentController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                enabled: !isEditing,
                decoration: const InputDecoration(labelText: 'نسبة الفائدة (%)', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اسم الخطة مطلوب')));
                return;
              }

              final duration = int.tryParse(durationController.text.trim()) ?? 6;
              final downPaymentEgp = int.tryParse(downPaymentController.text.trim()) ?? 0;
              final interestPct = double.tryParse(interestPercentController.text.trim()) ?? 0.0;
              final interestBp = (interestPct * 100).round();

              Navigator.of(dialogCtx).pop();

              if (isEditing) {
                final updated = InstallmentPlanEntity(
                  id: plan.id,
                  branchId: plan.branchId,
                  name: name,
                  description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                  durationMonths: plan.durationMonths,
                  downPaymentPiasters: plan.downPaymentPiasters,
                  interestBp: plan.interestBp,
                  isActive: plan.isActive,
                  createdAt: plan.createdAt,
                  updatedAt: DateTime.now(),
                );
                await cubit.updatePlan(updated);
              } else {
                await cubit.createPlan(
                  name: name,
                  description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                  durationMonths: duration,
                  downPaymentPiasters: downPaymentEgp * 100,
                  interestBp: interestBp,
                );
              }
            },
            child: Text(isEditing ? 'حفظ التعديلات' : 'إضافة الخطة'),
          ),
        ],
      ),
    );
  }

  void _confirmDeactivate(
    BuildContext context,
    InstallmentPlansCubit cubit,
    InstallmentPlanEntity plan,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('تعطيل خطة التقسيط'),
        content: Text('هل أنت متأكد من تعطيل خطة "${plan.name}"؟ لن يمكن اختيارها لعقود جديدة.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              cubit.deactivatePlan(plan.id);
            },
            child: const Text('تعطيل'),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final InstallmentPlanEntity plan;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;

  const _PlanCard({
    required this.plan,
    required this.onEdit,
    required this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    final interestPct = plan.interestBp / 100.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(plan.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: plan.isActive ? Colors.green.shade50 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  plan.isActive ? 'مفعلة' : 'معطلة',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: plan.isActive ? Colors.green.shade800 : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          if (plan.description != null) ...[
            const SizedBox(height: 6),
            Text(plan.description!, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('المدة: ${plan.durationMonths} شهور', style: const TextStyle(fontSize: 13)),
              Text('المقدم: ${Money(plan.downPaymentPiasters).toDisplay()} ج.م', style: const TextStyle(fontSize: 13)),
              Text('الفائدة: $interestPct%', style: const TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('تعديل'),
              ),
              if (plan.isActive)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: onDeactivate,
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('تعطيل'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

