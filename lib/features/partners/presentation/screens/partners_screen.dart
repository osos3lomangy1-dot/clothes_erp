import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../cubits/partners_cubit.dart';
import '../cubits/partners_state.dart';
import '../../domain/entities/partner_entity.dart';

class PartnersScreen extends StatefulWidget {
  const PartnersScreen({super.key});

  @override
  State<PartnersScreen> createState() => _PartnersScreenState();
}

class _PartnersScreenState extends State<PartnersScreen> {
  DateTimeRange? _dateRange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
  }

  int get _daysInSelectedPeriod {
    if (_dateRange == null) return 30;
    final diff = _dateRange!.end.difference(_dateRange!.start).inDays;
    return diff <= 0 ? 1 : diff + 1;
  }

  void _openPartnerDialog(
    BuildContext context, {
    PartnerEntity? partner,
    required double currentTotalPercentage,
    required List<PartnerEntity> existingPartners,
  }) {
    final cubit = context.read<PartnersCubit>();
    final isEdit = partner != null;

    final nameCtrl = TextEditingController(text: partner?.name ?? '');
    final phoneCtrl = TextEditingController(text: partner?.phone ?? '');
    final percentageCtrl = TextEditingController(text: partner != null ? '${partner.percentage}' : '');
    final capitalCtrl = TextEditingController(text: partner != null && partner.capital > 0 ? '${partner.capital / 100}' : '');
    final roiCtrl = TextEditingController(text: partner != null && partner.roiPercentage > 0 ? '${partner.roiPercentage}' : '15');
    final salaryCtrl = TextEditingController(text: partner != null && partner.monthlySalary > 0 ? '${partner.monthlySalary / 100}' : '');
    final notesCtrl = TextEditingController(text: partner?.notes ?? '');
    final formKey = GlobalKey<FormState>();

    // Initial state
    String partnershipType = partner?.partnershipType ?? 'capital_and_effort';
    String profitMode = partner?.profitMode ?? 'net_profit_share';
    bool showSmartCalculator = false;
    final customTotalCapitalCtrl = TextEditingController();

    // calculate max percentage allowed
    final otherPercentages = isEdit ? (currentTotalPercentage - partner.percentage) : currentTotalPercentage;
    final maxAllowed = (100.0 - otherPercentages).clamp(0.0, 100.0);

    // Sum of other partners' capital
    final otherPartnersCapital = existingPartners
        .where((p) => !isEdit || p.id != partner.id)
        .fold<int>(0, (sum, p) => sum + p.capital);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isEffortOnly = partnershipType == 'effort_only';
          final isFixedRoi = profitMode == 'fixed_roi';

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.handshake_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  isEdit ? 'تعديل بيانات الشريك' : 'إضافة شريك جديد وحساب نسبته',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Basic Info
                      TextFormField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'اسم الشريك *',
                          hintText: 'مثال: أستاذ أحمد فؤاد',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        validator: (val) => val == null || val.trim().isEmpty ? 'يرجى إدخال اسم الشريك' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف (اختياري)',
                          hintText: 'مثال: 01012345678',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. Partnership Type Selection
                      const Text('نوع الشراكة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTypeOption(
                              title: 'بالمال والمجهود',
                              subtitle: 'رأس مال + إدارة',
                              icon: Icons.business_center_rounded,
                              isSelected: partnershipType == 'capital_and_effort',
                              onTap: () => setDialogState(() => partnershipType = 'capital_and_effort'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTypeOption(
                              title: 'بالمال فقط',
                              subtitle: 'مستثمر مموّل',
                              icon: Icons.savings_rounded,
                              isSelected: partnershipType == 'capital_only',
                              onTap: () => setDialogState(() => partnershipType = 'capital_only'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildTypeOption(
                              title: 'بالمجهود فقط',
                              subtitle: 'بدون رأس مال',
                              icon: Icons.directions_run_rounded,
                              isSelected: partnershipType == 'effort_only',
                              onTap: () {
                                setDialogState(() {
                                  partnershipType = 'effort_only';
                                  capitalCtrl.text = '0';
                                  showSmartCalculator = false;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 3. Capital Input (if not effort only)
                      if (!isEffortOnly) ...[
                        TextFormField(
                          controller: capitalCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'رأس المال المستثمر (ج.م) *',
                            hintText: 'مثال: 100000',
                            suffixText: 'ج.م',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.monetization_on_outlined, color: AppColors.primary),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'يرجى إدخال مبلغ رأس المال';
                            final num = double.tryParse(val.trim());
                            if (num == null || num <= 0) return 'المبلغ يجب أن يكون أكبر من الصفر';
                            return null;
                          },
                          onChanged: (_) {
                            if (showSmartCalculator) setDialogState(() {});
                          },
                        ),
                        const SizedBox(height: 8),

                        // Smart Percentage Calculator Toggle
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            setDialogState(() {
                              showSmartCalculator = !showSmartCalculator;
                              if (showSmartCalculator && customTotalCapitalCtrl.text.isEmpty) {
                                final thisCap = (double.tryParse(capitalCtrl.text.trim()) ?? 0.0) * 100;
                                final estTotal = (otherPartnersCapital + thisCap) / 100.0;
                                customTotalCapitalCtrl.text = estTotal > 0 ? estTotal.toStringAsFixed(0) : '';
                              }
                            });
                          },
                          icon: Icon(showSmartCalculator ? Icons.keyboard_arrow_up_rounded : Icons.calculate_outlined, size: 18),
                          label: Text(
                            showSmartCalculator ? 'إخفاء الحاسبة الذكية' : '⚡ احسب النسبة المئوية تلقائياً من رأس المال',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),

                        // Smart Percentage Calculator Box
                        if (showSmartCalculator) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.auto_graph_rounded, color: Colors.blue, size: 18),
                                    SizedBox(width: 6),
                                    Text('حاسبة النسبة التلقائية حسب رأس المال', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '• رؤوس أموال باقي الشركاء: ${Money(otherPartnersCapital).toDisplay()} ج.م',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: customTotalCapitalCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: 'إجمالي رأس مال المحل المعتمد (ج.م)',
                                    isDense: true,
                                    suffixText: 'ج.م',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  onChanged: (_) => setDialogState(() {}),
                                ),
                                const SizedBox(height: 10),
                                Builder(
                                  builder: (c) {
                                    final thisCap = double.tryParse(capitalCtrl.text.trim()) ?? 0.0;
                                    final totalCap = double.tryParse(customTotalCapitalCtrl.text.trim()) ?? 0.0;
                                    double calcPercent = 0.0;
                                    if (totalCap > 0 && thisCap > 0) {
                                      calcPercent = (thisCap / totalCap) * 100.0;
                                    }
                                    return Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'النسبة المحسوبة: ${calcPercent > 0 ? calcPercent.toStringAsFixed(2) : "0.0"}%',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue.shade700,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: calcPercent > 0
                                              ? () {
                                                  setDialogState(() {
                                                    percentageCtrl.text = calcPercent.toStringAsFixed(2);
                                                    showSmartCalculator = false;
                                                  });
                                                }
                                              : null,
                                          child: const Text('اعتماد هذه النسبة', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],

                      // 4. Profit Calculation Mode
                      const Text('طريقة احتساب أرباح الشريك:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => setDialogState(() => profitMode = 'net_profit_share'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: profitMode == 'net_profit_share' ? AppColors.surfaceContainer : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: profitMode == 'net_profit_share' ? AppColors.primary : Colors.grey.shade300,
                                    width: profitMode == 'net_profit_share' ? 1.5 : 1,
                                  ),
                                ),
                                child: const Column(
                                  children: [
                                    Text('نسبة من صافي الربح', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    SizedBox(height: 2),
                                    Text('تتغير حسب مبيعات ومصاريف المحل', style: TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (!isEffortOnly) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => setDialogState(() => profitMode = 'fixed_roi'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: profitMode == 'fixed_roi' ? AppColors.surfaceContainer : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: profitMode == 'fixed_roi' ? AppColors.primary : Colors.grey.shade300,
                                      width: profitMode == 'fixed_roi' ? 1.5 : 1,
                                    ),
                                  ),
                                  child: const Column(
                                    children: [
                                      Text('عائد سنوي محدد على رأس المال', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      SizedBox(height: 2),
                                      Text('عائد استثماري ثابت % من رأس المال', style: TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Percentage or ROI Field
                      if (!isFixedRoi) ...[
                        TextFormField(
                          controller: percentageCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'نسبة الشريك من صافي الأرباح (%) *',
                            hintText: 'الحد الأقصى المتاح حالياً: ${maxAllowed.toStringAsFixed(1)}%',
                            suffixText: '%',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'يرجى إدخال النسبة المئوية';
                            final num = double.tryParse(val.trim());
                            if (num == null || num <= 0) return 'النسبة يجب أن تكون أكبر من الصفر';
                            if (num > maxAllowed + 0.001) {
                              return 'مجموع نسب الشركاء لا يمكن أن يتجاوز 100% (المتاح: ${maxAllowed.toStringAsFixed(1)}%)';
                            }
                            return null;
                          },
                        ),
                      ] else ...[
                        TextFormField(
                          controller: roiCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'معدل العائد الاستثماري السنوي (%) *',
                            hintText: 'مثال: 15 أو 20',
                            suffixText: '% سنوياً',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'يرجى إدخال معدل العائد';
                            final num = double.tryParse(val.trim());
                            if (num == null || num <= 0) return 'المعدل يجب أن يكون أكبر من الصفر';
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 14),

                      // Optional Monthly Allowance / Salary
                      TextFormField(
                        controller: salaryCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'بدل / راتب إدارة شهري (اختياري)',
                          hintText: 'مثال: 5000 (للشريك المدير إن وجد)',
                          suffixText: 'ج.م / شهرياً',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Notes
                      TextFormField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'ملاحظات وتفاصيل الاتفاق (اختياري)',
                          hintText: 'مثال: تم الاتفاق على توزيع الأرباح كل أول شهر...',
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
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  if (formKey.currentState?.validate() != true) return;
                  final percent = double.tryParse(percentageCtrl.text.trim()) ?? 0.0;
                  final capPounds = double.tryParse(capitalCtrl.text.trim()) ?? 0.0;
                  final roiVal = double.tryParse(roiCtrl.text.trim()) ?? 0.0;
                  final salPounds = double.tryParse(salaryCtrl.text.trim()) ?? 0.0;

                  final toSave = (partner ?? PartnerEntity(
                    id: '',
                    name: '',
                    percentage: 0,
                    createdAt: DateTime.now(),
                  )).copyWith(
                    id: partner?.id ?? '',
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                    percentage: isFixedRoi ? 0.0 : percent,
                    capital: isEffortOnly ? 0 : (capPounds * 100).toInt(),
                    partnershipType: partnershipType,
                    profitMode: profitMode,
                    roiPercentage: isFixedRoi ? roiVal : 0.0,
                    monthlySalary: (salPounds * 100).toInt(),
                    notes: notesCtrl.text.trim().isNotEmpty ? notesCtrl.text.trim() : null,
                    createdAt: partner?.createdAt ?? DateTime.now(),
                  );

                  final ok = await cubit.savePartner(toSave);
                  if (ok && dialogCtx.mounted) {
                    Navigator.pop(dialogCtx);
                  }
                },
                child: Text(
                  isEdit ? 'حفظ التعديلات' : 'إضافة الشريك',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTypeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppColors.primary : Colors.grey.shade600, size: 22),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, fontSize: 11, color: isSelected ? AppColors.primary : AppColors.onSurface), textAlign: TextAlign.center),
            Text(subtitle, style: TextStyle(fontSize: 9, color: Colors.grey.shade600), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // Record a withdrawal / payout dialog
  void _openWithdrawalDialog(BuildContext context, PartnerEntity partner, int currentEarnedProfit) {
    final cubit = context.read<PartnersCubit>();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String withdrawalType = 'profit'; // 'profit' or 'capital'

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.payments_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('صرف أرباح / مسحوبات: ${partner.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('الأرباح المستحقة حالياً', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('${Money(currentEarnedProfit).toDisplay()} ج.م', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('رأس المال النشط', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('${Money(partner.currentCapital).toDisplay()} ج.م', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text('نوع الصرف:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('صرف من الأرباح المستحقة'),
                          selected: withdrawalType == 'profit',
                          onSelected: (val) => setDialogState(() => withdrawalType = 'profit'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('استرداد من رأس المال'),
                          selected: withdrawalType == 'capital',
                          onSelected: (val) => setDialogState(() => withdrawalType = 'capital'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المنصرف (ج.م) *',
                      suffixText: 'ج.م',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.attach_money_rounded, color: AppColors.primary),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال المبلغ';
                      final num = double.tryParse(val.trim());
                      if (num == null || num <= 0) return 'المبلغ يجب أن يكون أكبر من الصفر';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظة / بيان الصرف (اختياري)',
                      hintText: 'مثال: أرباح شهر أكتوبر، استرداد جزء من المساهمة...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                final pounds = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final piasters = (pounds * 100).toInt();

                final ok = await cubit.recordWithdrawal(
                  partnerId: partner.id,
                  amount: piasters,
                  type: withdrawalType,
                  note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                );

                if (ok && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم تسجيل حركة الصرف للشريك بنجاح!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              child: const Text('تأكيد الصرف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Withdrawals history dialog
  void _showWithdrawalHistoryDialog(BuildContext context, PartnerEntity partner) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.history_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('سجل مسحوبات: ${partner.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 440,
          height: 360,
          child: partner.withdrawals.isEmpty
              ? const Center(
                  child: Text('لا توجد مسحوبات مسجلة لهذا الشريك حتى الآن', style: TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  itemCount: partner.withdrawals.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final w = partner.withdrawals[idx];
                    final isProfit = w.type == 'profit';
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        backgroundColor: isProfit ? Colors.green.shade50 : Colors.blue.shade50,
                        child: Icon(
                          isProfit ? Icons.arrow_downward_rounded : Icons.account_balance_wallet_outlined,
                          color: isProfit ? Colors.green.shade700 : Colors.blue.shade700,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        '${Money(w.amount).toDisplay()} ج.م (${isProfit ? "سحب أرباح" : "استرداد رأس مال"})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text(
                        '${w.date.year}-${w.date.month.toString().padLeft(2, '0')}-${w.date.day.toString().padLeft(2, '0')}${w.note != null ? " • ${w.note}" : ""}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // Confirm auto rebalancing
  Future<void> _confirmAutoBalance(BuildContext context) async {
    final cubit = context.read<PartnersCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.auto_mode_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('موازنة جميع الحصص تلقائياً', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'سيقوم النظام تلقائياً بإعادة حساب نسبة كل شريك بناءً على نسبة رأس ماله من إجمالي رؤوس أموال الشركاء لتساوي 100% تماماً وبأعلى دقة.\n\nهل تريد تنفيذ الموازنة الآن؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تنفيذ الموازنة التلقائية', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ok = await cubit.autoBalancePercentagesByCapital();
      if (ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت موازنة نسب جميع الشركاء تلقائياً بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, PartnerEntity partner) async {
    final cubit = context.read<PartnersCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('تأكيد حذف الشريك', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف الشريك "${partner.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف نهائي', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await cubit.deletePartner(partner.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<PartnersCubit>()
        ..loadData(
          from: _dateRange?.start,
          to: _dateRange?.end,
        ),
      child: Builder(
        builder: (context) {
          return Scaffold(
            backgroundColor: AppColors.surface,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الشركاء وحساب وتوزيع الأرباح',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
                  ),
                  Text(
                    'إدارة الشركاء، رؤوس الأموال، نسب الأرباح، وحساب صافي الدخل والمسحوبات',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                BlocBuilder<PartnersCubit, PartnersState>(
                  builder: (context, state) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _openPartnerDialog(
                          context,
                          currentTotalPercentage: state.totalPercentage,
                          existingPartners: state.partners,
                        ),
                        icon: const Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
                        label: const Text('إضافة شريك جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: BlocBuilder<PartnersCubit, PartnersState>(
              builder: (context, state) {
                final summary = state.profitSummary;
                final netProfit = summary?.netProfit ?? 0;
                final days = _daysInSelectedPeriod;

                return Column(
                  children: [
                    // Date picker bar
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.date_range_rounded, color: AppColors.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    _dateRange != null
                                        ? 'الفترة المحتسبة: ${_dateRange!.start.toLocal().toString().split(' ')[0]} إلى ${_dateRange!.end.toLocal().toString().split(' ')[0]} ($days يوم)'
                                        : 'جميع المبيعات',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () async {
                              final picked = await showDateRangePicker(
                                context: context,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                                initialDateRange: _dateRange,
                              );
                              if (picked != null) {
                                setState(() {
                                  _dateRange = DateTimeRange(
                                    start: picked.start,
                                    end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
                                  );
                                });
                                if (context.mounted) {
                                  context.read<PartnersCubit>().loadData(
                                        from: _dateRange!.start,
                                        to: _dateRange!.end,
                                      );
                                }
                              }
                            },
                            icon: const Icon(Icons.calendar_month_outlined, size: 18),
                            label: const Text('تغيير الفترة'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Profit and Shares Metrics
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              title: 'إجمالي المبيعات',
                              value: '${Money(summary?.totalRevenue ?? 0).toDisplay()} ج.م',
                              icon: Icons.monetization_on_rounded,
                              color: Colors.green.shade700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              title: 'تكلفة البضاعة',
                              value: '${Money(summary?.totalCost ?? 0).toDisplay()} ج.م',
                              icon: Icons.inventory_2_outlined,
                              color: Colors.orange.shade800,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              title: 'المصروفات التشغيلية',
                              value: '${Money(summary?.totalExpenses ?? 0).toDisplay()} ج.م',
                              icon: Icons.outbox_rounded,
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              title: 'صافي الربح القابل للتوزيع',
                              value: '${Money(netProfit).toDisplay()} ج.م',
                              icon: Icons.account_balance_wallet_rounded,
                              color: netProfit >= 0 ? AppColors.primary : AppColors.error,
                              isHighlighted: true,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Capital Summary & Auto-Balance Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.pie_chart_outline_rounded, color: AppColors.primary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'إجمالي رأس المال المسجل: ${Money(state.totalCapital).toDisplay()} ج.م',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(width: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (state.totalPercentage >= 99.9 && state.totalPercentage <= 100.1)
                                    ? Colors.green.shade50
                                    : Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: (state.totalPercentage >= 99.9 && state.totalPercentage <= 100.1)
                                      ? Colors.green.shade300
                                      : Colors.amber.shade400,
                                ),
                              ),
                              child: Text(
                                'توزيع الحصص: ${state.totalPercentage.toStringAsFixed(1)}% من 100%',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: (state.totalPercentage >= 99.9 && state.totalPercentage <= 100.1)
                                      ? Colors.green.shade800
                                      : Colors.amber.shade900,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (state.partners.where((p) => p.capital > 0).length >= 2) ...[
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  backgroundColor: AppColors.surfaceContainer,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _confirmAutoBalance(context),
                                icon: const Icon(Icons.auto_mode_rounded, size: 16),
                                label: const Text('⚡ موازنة كل النسب حسب رأس المال', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Partners List
                    Expanded(
                      child: state.status == PartnersStatus.loading
                          ? const Center(child: CircularProgressIndicator())
                          : state.partners.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.handshake_outlined, size: 64, color: Colors.grey.shade400),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'لم يتم تسجيل أي شركاء حتى الآن',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'سجل الشركاء ونسبهم من الأرباح ورؤوس أموالهم ليقوم النظام باحتساب وتوزيع الأرباح تلقائياً',
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () => _openPartnerDialog(
                                          context,
                                          currentTotalPercentage: state.totalPercentage,
                                          existingPartners: state.partners,
                                        ),
                                        icon: const Icon(Icons.add, color: Colors.white),
                                        label: const Text('إضافة أول شريك الآن', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  itemCount: state.partners.length,
                                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final partner = state.partners[index];
                                    final partnerShare = partner.calculateProfitShare(netProfit, days: days);
                                    final totalWithdrawn = partner.totalProfitWithdrawn;
                                    final remainingProfitToPayout = (partnerShare - totalWithdrawn).clamp(0, 100000000000);

                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                radius: 24,
                                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                                child: Text(
                                                  partner.name.isNotEmpty ? partner.name[0] : 'ش',
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Wrap(
                                                      crossAxisAlignment: WrapCrossAlignment.center,
                                                      spacing: 8,
                                                      runSpacing: 4,
                                                      children: [
                                                        Text(partner.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: AppColors.surfaceContainer,
                                                            borderRadius: BorderRadius.circular(8),
                                                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                                          ),
                                                          child: Text(
                                                            partner.typeLabel,
                                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primary),
                                                          ),
                                                        ),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.blue.shade50,
                                                            borderRadius: BorderRadius.circular(8),
                                                            border: Border.all(color: Colors.blue.shade200),
                                                          ),
                                                          child: Text(
                                                            partner.profitModeLabel,
                                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blue.shade800),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Wrap(
                                                      spacing: 16,
                                                      runSpacing: 4,
                                                      children: [
                                                        if (partner.capital > 0)
                                                          Text(
                                                            'رأس المال المستثمر: ${Money(partner.capital).toDisplay()} ج.م',
                                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                                                          ),
                                                        if (partner.phone != null && partner.phone!.isNotEmpty)
                                                          Text(
                                                            'الهاتف: ${partner.phone}',
                                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                          ),
                                                        if (partner.monthlySalary > 0)
                                                          Text(
                                                            'بدل إدارة شهري: ${Money(partner.monthlySalary).toDisplay()} ج.م',
                                                            style: TextStyle(fontSize: 12, color: Colors.indigo.shade700, fontWeight: FontWeight.bold),
                                                          ),
                                                      ],
                                                    ),
                                                    if (partner.notes != null && partner.notes!.isNotEmpty) ...[
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        partner.notes!,
                                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                                                tooltip: 'تعديل الشريك',
                                                onPressed: () => _openPartnerDialog(
                                                  context,
                                                  partner: partner,
                                                  currentTotalPercentage: state.totalPercentage,
                                                  existingPartners: state.partners,
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                                                tooltip: 'حذف الشريك',
                                                onPressed: () => _confirmDelete(context, partner),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          const Divider(height: 1),
                                          const SizedBox(height: 10),

                                          // Financial summary bar for this partner
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: netProfit >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text('نصيب الأرباح في الفترة ($days يوم)', style: TextStyle(fontSize: 10, color: netProfit >= 0 ? Colors.green.shade900 : Colors.red.shade900)),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${Money(partnerShare).toDisplay()} ج.م',
                                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: netProfit >= 0 ? Colors.green.shade900 : Colors.red.shade900),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade50,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: Colors.grey.shade200),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Text('المسحوبات المنصرفة', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${Money(totalWithdrawn).toDisplay()} ج.م',
                                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey.shade800),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.surfaceContainer,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      const Text('صافي المستحق غير المصروف', style: TextStyle(fontSize: 10, color: AppColors.primary)),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${Money(remainingProfitToPayout).toDisplay()} ج.م',
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.primary,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                onPressed: () => _openWithdrawalDialog(context, partner, partnerShare),
                                                icon: const Icon(Icons.payments_outlined, color: Colors.white, size: 16),
                                                label: const Text('صرف أرباح', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                              const SizedBox(width: 6),
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                onPressed: () => _showWithdrawalHistoryDialog(context, partner),
                                                icon: const Icon(Icons.history_rounded, size: 16),
                                                label: const Text('السجل', style: TextStyle(fontSize: 11)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isHighlighted ? AppColors.surfaceContainer : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlighted ? AppColors.primary.withValues(alpha: 0.4) : Colors.grey.shade200,
          width: isHighlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
