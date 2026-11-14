import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

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
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'خطط التقسيط',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
            Text(
              'تعريف الشروط، مدد السداد، ونسب الفوائد',
              style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.onSurface),
            tooltip: 'تحديث',
            onPressed: () => cubit.loadPlans(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPlanDialog(context, cubit),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          'إضافة خطة جديدة',
          style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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
                  Text(
                    'خطأ: ${state.errorMessage ?? "تعذر تحميل خطط التقسيط"}',
                    style: GoogleFonts.cairo(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => cubit.loadPlans(),
                    child: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
                  ),
                ],
              ),
            );
          }

          if (state.plans.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.playlist_add_rounded, size: 56, color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لا توجد خطط تقسيط معرفة حتى الآن',
                    style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'أنشئ خطط تقسيط مرنة (مثل: 6 أشهر بدون فوائد، 12 شهر بفائدة 10%)',
                    style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showPlanDialog(context, cubit),
                    icon: const Icon(Icons.add_rounded),
                    label: Text('إضافة أول خطة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                itemCount: state.plans.length,
                separatorBuilder: (_, index) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final plan = state.plans[index];
                  return _PlanCard(
                    plan: plan,
                    onEdit: () => _showPlanDialog(context, cubit, plan: plan),
                    onDeactivate: () => _confirmDeactivate(context, cubit, plan),
                  );
                },
              ),
            ),
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
    showDialog(
      context: context,
      builder: (dialogCtx) => _PlanFormDialog(
        plan: plan,
        onSave: (name, description, durationMonths, downPaymentPiasters, interestBp) async {
          if (plan != null) {
            final updated = InstallmentPlanEntity(
              id: plan.id,
              branchId: plan.branchId,
              name: name,
              description: description,
              durationMonths: durationMonths,
              downPaymentPiasters: downPaymentPiasters,
              interestBp: interestBp,
              isActive: plan.isActive,
              createdAt: plan.createdAt,
              updatedAt: DateTime.now(),
            );
            await cubit.updatePlan(updated);
          } else {
            await cubit.createPlan(
              name: name,
              description: description,
              durationMonths: durationMonths,
              downPaymentPiasters: downPaymentPiasters,
              interestBp: interestBp,
            );
          }
        },
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'تعطيل خطة التقسيط',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل أنت متأكد من تعطيل خطة "${plan.name}"؟ لن يمكن اختيارها لعقود جديدة.',
          style: GoogleFonts.cairo(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              cubit.deactivatePlan(plan.id);
            },
            child: Text('تعطيل', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _PlanFormDialog extends StatefulWidget {
  final InstallmentPlanEntity? plan;
  final Future<void> Function(
    String name,
    String? description,
    int durationMonths,
    int downPaymentPiasters,
    int interestBp,
  ) onSave;

  const _PlanFormDialog({
    this.plan,
    required this.onSave,
  });

  @override
  State<_PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends State<_PlanFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _durationController;
  late final TextEditingController _downPaymentController;
  late final TextEditingController _interestPercentController;
  bool _isZeroInterest = false;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _nameController = TextEditingController(text: p?.name ?? '');
    _descController = TextEditingController(text: p?.description ?? '');
    _durationController = TextEditingController(text: p != null ? '${p.durationMonths}' : '6');
    _downPaymentController = TextEditingController(
      text: p != null ? '${p.downPaymentPiasters ~/ 100}' : '0',
    );
    final initialInterestPct = p != null ? (p.interestBp / 100.0) : 0.0;
    _isZeroInterest = (initialInterestPct == 0.0);
    _interestPercentController = TextEditingController(
      text: initialInterestPct > 0 ? '$initialInterestPct' : '0',
    );

    _durationController.addListener(() => setState(() {}));
    _downPaymentController.addListener(() => setState(() {}));
    _interestPercentController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _durationController.dispose();
    _downPaymentController.dispose();
    _interestPercentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.plan != null;

    // Simulation calculation for 1,000 EGP sample invoice
    const sampleInvoiceEgp = 1000.0;
    final duration = int.tryParse(_durationController.text.trim()) ?? 6;
    final downPaymentEgp = double.tryParse(_downPaymentController.text.trim()) ?? 0.0;
    final interestPct = _isZeroInterest
        ? 0.0
        : (double.tryParse(_interestPercentController.text.trim()) ?? 0.0);

    final effectiveDown = downPaymentEgp.clamp(0.0, sampleInvoiceEgp);
    final financed = (sampleInvoiceEgp - effectiveDown).clamp(0.0, sampleInvoiceEgp);
    final interestAmount = (financed * (interestPct / 100.0));
    final totalObligation = effectiveDown + financed + interestAmount;
    final monthlyPayment = duration > 0 ? ((financed + interestAmount) / duration) : 0.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isEditing ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isEditing ? 'تعديل خطة التقسيط' : 'إضافة خطة تقسيط جديدة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 17),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Plan Name
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'اسم الخطة (مثال: خطة 6 أشهر)',
                  labelStyle: GoogleFonts.cairo(),
                  hintText: 'مثال: تقسيط 6 شهور بدون فوائد',
                  hintStyle: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade400),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.bookmark_border_rounded),
                ),
              ),
              const SizedBox(height: 12),

              // Duration in Months + Quick Presets
              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'المدة بالشهور',
                  labelStyle: GoogleFonts.cairo(),
                  suffixText: 'شهور',
                  suffixStyle: GoogleFonts.cairo(fontSize: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.calendar_month_outlined),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [3, 6, 9, 12, 18, 24].map((m) {
                  final isSelected = duration == m;
                  return ChoiceChip(
                    label: Text('$m شهور', style: GoogleFonts.cairo(fontSize: 11)),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _durationController.text = '$m');
                    },
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.primary : Colors.grey.shade800,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // Down payment
              TextField(
                controller: _downPaymentController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'الدفعة المقدمة (ج.م)',
                  labelStyle: GoogleFonts.cairo(),
                  helperText: 'أدخل 0 إذا كانت الخطة تتيح التقسيط بدون مقدم',
                  helperStyle: GoogleFonts.cairo(fontSize: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 12),

              // Zero Interest Switch
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isZeroInterest ? const Color(0xFFF0FDF4) : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isZeroInterest ? const Color(0xFFBBF7D0) : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isZeroInterest ? Icons.verified_rounded : Icons.money_off_rounded,
                      color: _isZeroInterest ? AppColors.success : Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'خطة بدون فوائد (0% تقسيط بسعر الكاش)',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: _isZeroInterest ? AppColors.success : AppColors.onSurface,
                            ),
                          ),
                          Text(
                            'المبلغ الممول يُقسم بالتساوي على الشهور دون أي زيادة',
                            style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isZeroInterest,
                      activeThumbColor: AppColors.success,
                      onChanged: (val) {
                        setState(() {
                          _isZeroInterest = val;
                          if (val) {
                            _interestPercentController.text = '0';
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Interest Percentage Field (Enabled if not zero interest)
              if (!_isZeroInterest) ...[
                TextField(
                  controller: _interestPercentController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'نسبة الفائدة (%)',
                    labelStyle: GoogleFonts.cairo(),
                    helperText: 'نسبة مئوية من أصل المبلغ الممول (مثال: 5 = 5%، 10 = 10%)',
                    helperStyle: GoogleFonts.cairo(fontSize: 11),
                    suffixText: '%',
                    suffixStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.percent_rounded),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [5.0, 7.5, 10.0, 12.0, 15.0, 20.0].map((pct) {
                    final isSelected = interestPct == pct;
                    return ChoiceChip(
                      label: Text('$pct%', style: GoogleFonts.cairo(fontSize: 11)),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() => _interestPercentController.text = '$pct');
                      },
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.primary : Colors.grey.shade800,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],

              // Live Simulation Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'محاكاة توضيحية لفاتورة بقيمة 1,000 ج.م:',
                            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$duration شهور',
                            style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المقدم:', style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade700)),
                        Text('${effectiveDown.toStringAsFixed(2)} ج.م', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المبلغ الممول:', style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade700)),
                        Text('${financed.toStringAsFixed(2)} ج.م', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('قيمة الفائدة ($interestPct%):', style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade700)),
                        Text(
                          interestAmount > 0 ? '+${interestAmount.toStringAsFixed(2)} ج.م' : '0.00 ج.م (بدون فائدة)',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: interestAmount > 0 ? AppColors.warning : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('القسط الشهري:', style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade700)),
                        Text(
                          '${monthlyPayment.toStringAsFixed(2)} ج.م / شهر',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                    const Divider(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('إجمالي ما يدفعه العميل:', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)),
                        Text(
                          '${totalObligation.toStringAsFixed(2)} ج.م',
                          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Description (Optional)
              TextField(
                controller: _descController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'الوصف (اختياري)',
                  labelStyle: GoogleFonts.cairo(),
                  hintText: 'ملاحظات أو شروط خاصة بالخطة (ضامن، صورة بطاقة...)',
                  hintStyle: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade400),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          onPressed: () async {
            final name = _nameController.text.trim();
            if (name.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('اسم الخطة مطلوب')),
              );
              return;
            }

            final durationVal = int.tryParse(_durationController.text.trim()) ?? 6;
            final downPaymentVal = double.tryParse(_downPaymentController.text.trim()) ?? 0.0;
            final interestPctVal = _isZeroInterest
                ? 0.0
                : (double.tryParse(_interestPercentController.text.trim()) ?? 0.0);
            final interestBp = (interestPctVal * 100).round().clamp(0, 10000);

            Navigator.of(context).pop();

            await widget.onSave(
              name,
              _descController.text.trim().isEmpty ? null : _descController.text.trim(),
              durationVal,
              (downPaymentVal * 100).round(),
              interestBp,
            );
          },
          child: Text(
            isEditing ? 'حفظ التعديلات' : 'إضافة الخطة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
        ),
      ],
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
    final isZeroInterest = (plan.interestBp == 0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.event_repeat_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (plan.description != null && plan.description!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        plan.description!,
                        style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: plan.isActive ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: plan.isActive ? const Color(0xFFBBF7D0) : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      plan.isActive ? Icons.check_circle_rounded : Icons.block_rounded,
                      size: 14,
                      color: plan.isActive ? AppColors.success : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      plan.isActive ? 'مفعلة' : 'معطلة',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: plan.isActive ? AppColors.success : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildPlanBadge(
                Icons.calendar_month_outlined,
                'المدة: ${plan.durationMonths} شهور',
                const Color(0xFFF0FDF4),
                const Color(0xFF166534),
              ),
              _buildPlanBadge(
                Icons.payments_outlined,
                plan.downPaymentPiasters > 0
                    ? 'المقدم: ${Money(plan.downPaymentPiasters).toDisplay()} ج.م'
                    : 'بدون مقدم (0 ج.م)',
                const Color(0xFFEFF6FF),
                const Color(0xFF1E40AF),
              ),
              _buildPlanBadge(
                Icons.percent_rounded,
                isZeroInterest ? 'بدون فوائد (0%)' : 'الفائدة: $interestPct%',
                isZeroInterest ? const Color(0xFFDCFCE7) : const Color(0xFFFFF7ED),
                isZeroInterest ? AppColors.success : const Color(0xFFC2410C),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text('تعديل', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
              if (plan.isActive) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  onPressed: onDeactivate,
                  icon: const Icon(Icons.block_rounded, size: 16),
                  label: Text('تعطيل', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlanBadge(IconData icon, String label, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textCol),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textCol,
            ),
          ),
        ],
      ),
    );
  }
}
