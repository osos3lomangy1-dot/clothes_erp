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
    final capitalPercentageCtrl = TextEditingController(
      text: partner?.capitalPercentage != null
          ? '${partner!.capitalPercentage}'
          : (partner != null && partner.capital > 0 ? '${partner.percentage}' : ''),
    );
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
                Icon(Icons.handshake_rounded, color: AppColors.primary),
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
                              subtitle: 'نسبة مئوية أو رأس مال',
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
                            labelText: 'رأس المال المستثمر (اختياري)',
                            hintText: 'مثال: 100000 (اتركه فارغاً إذا كان الاتفاق بالنسبة المباشرة)',
                            helperText: 'اختياري: إذا كانت الشراكة بالنسبة المئوية مباشرة (مثل 50% أو 40%) دون تقييد برأس مال أولي، اتركه فارغاً',
                            helperMaxLines: 2,
                            suffixText: 'ج.م',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: Icon(Icons.monetization_on_outlined, color: AppColors.primary),
                          ),
                          validator: (val) {
                            if (isFixedRoi) {
                              if (val == null || val.trim().isEmpty) return 'يرجى إدخال رأس المال لاحتساب العائد الاستثماري الثابت';
                              final num = double.tryParse(val.trim());
                              if (num == null || num <= 0) return 'المبلغ يجب أن يكون أكبر من الصفر';
                              return null;
                            }
                            if (val == null || val.trim().isEmpty) return null; // Optional for percentage sharing
                            final num = double.tryParse(val.trim());
                            if (num == null || num < 0) return 'يرجى إدخال مبلغ صحيح (صفر أو أكثر)';
                            return null;
                          },
                          onChanged: (_) {
                            if (showSmartCalculator) setDialogState(() {});
                          },
                        ),
                        const SizedBox(height: 10),

                        // Capital Equity Share Input (حصة رأس المال / الملكية)
                        TextFormField(
                          controller: capitalPercentageCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'حصة رأس المال / الملكية (%) (اختياري)',
                            hintText: 'مثال: 50 (حصة الشريك في ملكية رأس مال المحل)',
                            helperText: 'يمكن كتابتها يدوياً أو حسابها تلقائياً بالأسفل، وقد تختلف عن نسبة الأرباح',
                            helperMaxLines: 2,
                            suffixText: '%',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.pie_chart_outline_rounded, color: Colors.blueGrey),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return null;
                            final num = double.tryParse(val.trim());
                            if (num == null || num < 0 || num > 100) {
                              return 'يرجى إدخال نسبة صحيحة بين 0 و 100%';
                            }
                            return null;
                          },
                          onChanged: (_) => setDialogState(() {}),
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
                            showSmartCalculator ? 'إخفاء الحاسبة الذكية' : 'احسب النسبة المئوية تلقائياً من رأس المال',
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
                                                    capitalPercentageCtrl.text = calcPercent.toStringAsFixed(2);
                                                    if (percentageCtrl.text.isEmpty) {
                                                      percentageCtrl.text = calcPercent.toStringAsFixed(2);
                                                    }
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
                            helperText: 'النسبة الفعلية التي يُحسب عليها نصيب الشريك عند توزيع الأرباح (مثال: 60%)',
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
                        if (capitalPercentageCtrl.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  percentageCtrl.text = capitalPercentageCtrl.text.trim();
                                });
                              },
                              icon: const Icon(Icons.sync_rounded, size: 16),
                              label: Text(
                                'مطابقة نسبة الأرباح مع حصة رأس المال (${capitalPercentageCtrl.text.trim()}%)',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
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
                  final capPercent = double.tryParse(capitalPercentageCtrl.text.trim());
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
                    capitalPercentage: isEffortOnly ? 0.0 : capPercent,
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
              Icon(Icons.payments_rounded, color: AppColors.primary),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('صرف من الأرباح المستحقة'),
                        selected: withdrawalType == 'profit',
                        onSelected: (val) => setDialogState(() => withdrawalType = 'profit'),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.handshake_outlined, size: 16),
                        label: const Text('سلفة شخصية مؤقتة (لا تؤثر على الأرباح)'),
                        selected: withdrawalType == 'advance',
                        onSelected: (val) => setDialogState(() => withdrawalType = 'advance'),
                      ),
                      if (partner.remainingDeposited > 0)
                        ChoiceChip(
                          avatar: const Icon(Icons.arrow_downward_rounded, size: 16),
                          label: Text('استرداد تمويل الجيب (${Money(partner.remainingDeposited).toDisplay()} ج.م)'),
                          selected: withdrawalType == 'deposit_refund',
                          onSelected: (val) => setDialogState(() => withdrawalType = 'deposit_refund'),
                        ),
                      ChoiceChip(
                        label: const Text('استرداد من رأس المال'),
                        selected: withdrawalType == 'capital',
                        onSelected: (val) => setDialogState(() => withdrawalType = 'capital'),
                      ),
                    ],
                  ),
                  if (withdrawalType == 'advance') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.amber.shade900, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'سلفة مؤقتة من الدرج لظرف شخصي، لا تخصم من أرباحك ولا رأس مالك، وتُسوى عند ردها.',
                              style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المنصرف (ج.م) *',
                      suffixText: 'ج.م',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: Icon(Icons.attach_money_rounded, color: AppColors.primary),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال المبلغ';
                      final num = double.tryParse(val.trim());
                      if (num == null || num <= 0) return 'المبلغ يجب أن يكون أكبر من الصفر';
                      final piasters = (num * 100).toInt();
                      if (withdrawalType == 'deposit_refund' && piasters > partner.remainingDeposited) {
                        return 'المبلغ يتجاوز رصيد تمويل الجيب المتبقي (${Money(partner.remainingDeposited).toDisplay()} ج.م)';
                      }
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

                final bool ok;
                if (withdrawalType == 'deposit_refund') {
                  ok = await cubit.refundDeposit(
                    partnerId: partner.id,
                    amount: piasters,
                    note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                  );
                } else {
                  ok = await cubit.recordWithdrawal(
                    partnerId: partner.id,
                    amount: piasters,
                    type: withdrawalType,
                    note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                  );
                }

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

  // Deposit / Personal funding dialog (دفع من الجيب)
  void _openDepositDialog(
    BuildContext context,
    PartnerEntity partner, {
    String initialCategory = 'goods',
  }) {
    final formKey = GlobalKey<FormState>();
    final initialAmount = (initialCategory == 'advance_repayment' && partner.remainingAdvance > 0)
        ? (partner.remainingAdvance / 100.0).toStringAsFixed(partner.remainingAdvance % 100 == 0 ? 0 : 2)
        : '';
    final amountCtrl = TextEditingController(text: initialAmount);
    final noteCtrl = TextEditingController(
      text: initialCategory == 'advance_repayment' ? 'رد السلفة الشخصية للدرج' : '',
    );
    final cubit = context.read<PartnersCubit>();
    String depositCategory = initialCategory;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                depositCategory == 'advance_repayment' ? Icons.assignment_return_outlined : Icons.add_card_rounded,
                color: depositCategory == 'advance_repayment' ? Colors.amber.shade900 : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  depositCategory == 'advance_repayment'
                      ? 'رد سلفة شخصية مؤقتة: ${partner.name}'
                      : 'تمويل ودفع من الجيب: ${partner.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
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
                            const Text('إجمالي المدفوع سابقاً من الجيب', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('${Money(partner.totalDeposited).toDisplay()} ج.م', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary)),
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

                  const Text('الغرض من التمويل / الدفع من الجيب:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                        label: const Text('تكملة / شراء بضاعة'),
                        selected: depositCategory == 'goods',
                        onSelected: (val) => setDialogState(() => depositCategory = 'goods'),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.receipt_long_outlined, size: 16),
                        label: const Text('سداد مصروفات / إيجار'),
                        selected: depositCategory == 'expenses',
                        onSelected: (val) => setDialogState(() => depositCategory = 'expenses'),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.point_of_sale_outlined, size: 16),
                        label: const Text('سيولة نقدية بالدرج'),
                        selected: depositCategory == 'cash',
                        onSelected: (val) => setDialogState(() => depositCategory = 'cash'),
                      ),
                      ChoiceChip(
                        avatar: const Icon(Icons.assignment_return_outlined, size: 16),
                        label: Text(
                          partner.remainingAdvance > 0
                              ? 'رد سلفة شخصية مؤقتة (${Money(partner.remainingAdvance).toDisplay()} ج.م)'
                              : 'رد سلفة شخصية مؤقتة',
                        ),
                        selected: depositCategory == 'advance_repayment',
                        onSelected: (val) => setDialogState(() => depositCategory = 'advance_repayment'),
                      ),
                    ],
                  ),
                  if (depositCategory == 'advance_repayment') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded, color: Colors.amber.shade900, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'إيداع رد السلفة المؤقتة في الخزينة: يسوي السلفة السابقة ويخلي ذمتك دون اعتباره تمويلاً أو ديناً جديداً على المحل.',
                              style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المدفوع (ج.م) *',
                      suffixText: 'ج.م',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: Icon(Icons.attach_money_rounded, color: AppColors.primary),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال المبلغ';
                      final num = double.tryParse(val.trim());
                      if (num == null || num <= 0) return 'المبلغ يجب أن يكون أكبر من الصفر';
                      if (depositCategory == 'advance_repayment' && partner.remainingAdvance > 0) {
                        final piasters = (num * 100).toInt();
                        if (piasters > partner.remainingAdvance) {
                          return 'المبلغ يتجاوز السلفة المستحقة عليك (${Money(partner.remainingAdvance).toDisplay()} ج.م)';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظة / تفاصيل الدفع (اختياري)',
                      hintText: depositCategory == 'advance_repayment'
                          ? 'مثال: رد كامل السلفة للدرج نقداً...'
                          : 'مثال: دفع تكلفة شحنة قماش كاش من جيبي لعدم توفر سيولة...',
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
                backgroundColor: depositCategory == 'advance_repayment' ? Colors.amber.shade800 : AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                final pounds = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final piasters = (pounds * 100).toInt();

                final ok = await cubit.recordDeposit(
                  partnerId: partner.id,
                  amount: piasters,
                  category: depositCategory,
                  note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                );

                if (ok && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  final msg = depositCategory == 'advance_repayment'
                      ? 'تم تسجيل رد السلفة الشخصية للدرج بمبلغ ${Money(piasters).toDisplay()} ج.م وتسويتها بنجاح!'
                      : 'تم تسجيل تمويل من جيب الشريك بمبلغ ${Money(piasters).toDisplay()} ج.م بنجاح!';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              child: Text(
                depositCategory == 'advance_repayment' ? 'تأكيد رد السلفة' : 'تأكيد الإيداع',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Reinvest retained profit into capital dialog (تدوير الأرباح في رأس المال)
  void _openReinvestDialog(BuildContext context, PartnerEntity partner, int unwithdrawnProfit) {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController(text: (unwithdrawnProfit / 100.0).toStringAsFixed(2));
    final noteCtrl = TextEditingController();
    final cubit = context.read<PartnersCubit>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.autorenew_rounded, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تدوير الأرباح كرأس مال: ${partner.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تدوير الأرباح يتيح للشريك ترك أرباحه في المحل وإضافتها تلقائياً إلى حصته في رأس المال بدلاً من سحبها.',
                          style: TextStyle(fontSize: 12, color: Colors.teal),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              'الأرباح المتبقية المتاحة: ${Money(unwithdrawnProfit).toDisplay()} ج.م',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'رأس المال الحالي: ${Money(partner.currentCapital).toDisplay()} ج.م',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المراد تدويره في رأس المال (ج.م) *',
                      suffixText: 'ج.م',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.price_change_outlined, color: Colors.teal),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال المبلغ';
                      final num = double.tryParse(val.trim());
                      if (num == null || num <= 0) return 'المبلغ يجب أن يكون أكبر من الصفر';
                      final piasters = (num * 100).toInt();
                      if (piasters > unwithdrawnProfit) return 'المبلغ لا يمكن أن يتجاوز الأرباح المتبقية (${Money(unwithdrawnProfit).toDisplay()} ج.م)';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                      hintText: 'مثال: تدوير أرباح الفترة لزيادة حصة رأس المال...',
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
                backgroundColor: Colors.teal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                final pounds = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final piasters = (pounds * 100).toInt();

                final ok = await cubit.reinvestProfitIntoCapital(
                  partnerId: partner.id,
                  amount: piasters,
                  note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                );

                if (ok && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم تدوير مبلغ ${Money(piasters).toDisplay()} ج.م وإضافته لرأس مال ${partner.name} بنجاح!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              child: const Text('تأكيد التدوير كزيادة رأس مال', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Refund out-of-pocket funding dialog (استرداد فلوس الجيب كاش)
  void _openRefundDepositDialog(BuildContext context, PartnerEntity partner) {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController(text: (partner.remainingDeposited / 100.0).toStringAsFixed(2));
    final noteCtrl = TextEditingController();
    final cubit = context.read<PartnersCubit>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.arrow_downward_rounded, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'استرداد تمويل شخصي من الجيب: ${partner.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'استرداد ما دفعته من جيبك كاش من سيولة المحل، ليتم سداد هذا الدين لك بالكامل دون المساس بأرباحك أو رأس مالك.',
                          style: TextStyle(fontSize: 12, color: Colors.teal),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              'الرصيد المتاح للاسترداد: ${Money(partner.remainingDeposited).toDisplay()} ج.م',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'إجمالي المدفوع: ${Money(partner.totalDeposited).toDisplay()} ج.م',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المسترد (ج.م) *',
                      suffixText: 'ج.م',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.money_rounded, color: Colors.teal),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال المبلغ';
                      final num = double.tryParse(val.trim());
                      if (num == null || num <= 0) return 'المبلغ يجب أن يكون أكبر من الصفر';
                      final piasters = (num * 100).toInt();
                      if (piasters > partner.remainingDeposited) {
                        return 'المبلغ يتجاوز رصيد تمويل الجيب المتبقي (${Money(partner.remainingDeposited).toDisplay()} ج.م)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                      hintText: 'مثال: استرداد كاش من الدرج عن دفعة البضاعة...',
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
                backgroundColor: Colors.teal.shade800,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                final pounds = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final piasters = (pounds * 100).toInt();

                final ok = await cubit.refundDeposit(
                  partnerId: partner.id,
                  amount: piasters,
                  note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                );

                if (ok && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم استرداد مبلغ ${Money(piasters).toDisplay()} ج.م من تمويل الجيب لـ ${partner.name} بنجاح!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              child: const Text('تأكيد الاسترداد كاش', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Convert personal funding to capital dialog (تحويل تمويل الجيب لرأس مال)
  void _openConvertDepositToCapitalDialog(BuildContext context, PartnerEntity partner) {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController(text: (partner.remainingDeposited / 100.0).toStringAsFixed(2));
    final noteCtrl = TextEditingController();
    final cubit = context.read<PartnersCubit>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.upgrade_rounded, color: Colors.indigo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تحويل تمويل الجيب لرأس مال: ${partner.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'هذا الإجراء يقوم بنقل المبالغ المدفوعة من جيبك لتضاف رسمياً إلى رأس مالك بالمحل، مما يرفع من حصتك الاستثمارية وقيمة مساهمتك.',
                          style: TextStyle(fontSize: 12, color: Colors.indigo),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(
                              'التمويل المتاح للتحويل: ${Money(partner.remainingDeposited).toDisplay()} ج.م',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'رأس المال الحالي: ${Money(partner.currentCapital).toDisplay()} ج.م',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'المبلغ المراد إضافته لرأس المال (ج.م) *',
                      suffixText: 'ج.م',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.price_change_outlined, color: Colors.indigo),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'يرجى إدخال المبلغ';
                      final num = double.tryParse(val.trim());
                      if (num == null || num <= 0) return 'المبلغ يجب أن يكون أكبر من الصفر';
                      final piasters = (num * 100).toInt();
                      if (piasters > partner.remainingDeposited) {
                        return 'المبلغ يتجاوز رصيد تمويل الجيب المتبقي (${Money(partner.remainingDeposited).toDisplay()} ج.م)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                      hintText: 'مثال: ضم دفعة البضاعة لحصة رأس المال...',
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
                backgroundColor: Colors.indigo.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (formKey.currentState?.validate() != true) return;
                final pounds = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final piasters = (pounds * 100).toInt();

                final ok = await cubit.convertDepositToCapital(
                  partnerId: partner.id,
                  amount: piasters,
                  note: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
                );

                if (ok && dialogCtx.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم تحويل مبلغ ${Money(piasters).toDisplay()} ج.م من تمويل الجيب وإضافته لرأس مال ${partner.name} بنجاح!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              },
              child: const Text('تأكيد التحويل لرأس المال', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // Unified financial history dialog (سجل الحركات المالية: إيداعات ومسحوبات)
  void _showFinancialHistoryDialog(BuildContext context, PartnerEntity partner) {
    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.history_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('سجل حركات الشريك: ${partner.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            height: 420,
            child: Column(
              children: [
                TabBar(
                  labelColor: AppColors.primary,
                  indicatorColor: AppColors.primary,
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.add_card_rounded, size: 18),
                      text: 'تمويل ودفع من الجيب (${partner.deposits.length})',
                    ),
                    Tab(
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      text: 'المسحوبات (${partner.withdrawals.length})',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Tab 1: Deposits
                      partner.deposits.isEmpty
                          ? const Center(
                              child: Text('لا توجد دفعات أو تمويل من الجيب مسجل حتى الآن', style: TextStyle(color: Colors.grey)),
                            )
                          : ListView.separated(
                              itemCount: partner.deposits.length,
                              separatorBuilder: (_, index) => const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final d = partner.deposits[idx];
                                final isAdvanceRepaid = d.category == 'advance_repayment';
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    backgroundColor: isAdvanceRepaid ? Colors.amber.shade50 : Colors.teal.shade50,
                                    child: Icon(
                                      isAdvanceRepaid ? Icons.assignment_return_outlined : Icons.add_circle_outline_rounded,
                                      color: isAdvanceRepaid ? Colors.amber.shade800 : Colors.teal.shade700,
                                      size: 18,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Text(
                                        '${Money(d.amount).toDisplay()} ج.م',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isAdvanceRepaid ? Colors.amber.shade50 : Colors.teal.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: isAdvanceRepaid ? Colors.amber.shade300 : Colors.teal.shade200),
                                        ),
                                        child: Text(
                                          d.categoryLabel,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isAdvanceRepaid ? Colors.amber.shade900 : Colors.teal.shade900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}-${d.date.day.toString().padLeft(2, '0')}${d.note != null ? " • ${d.note}" : ""}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                    tooltip: 'حذف حركة الإيداع',
                                    onPressed: () => _confirmDeleteDeposit(context, partner, d),
                                  ),
                                );
                              },
                            ),

                      // Tab 2: Withdrawals
                      partner.withdrawals.isEmpty
                          ? const Center(
                              child: Text('لا توجد مسحوبات مسجلة لهذا الشريك حتى الآن', style: TextStyle(color: Colors.grey)),
                            )
                          : ListView.separated(
                              itemCount: partner.withdrawals.length,
                              separatorBuilder: (_, index) => const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final w = partner.withdrawals[idx];
                                final isProfit = w.type == 'profit';
                                final isAdvance = w.type == 'advance';
                                final isDepositRefund = w.type == 'deposit_refund';
                                final isDepositToCap = w.type == 'deposit_to_capital';

                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    backgroundColor: isProfit
                                        ? Colors.green.shade50
                                        : (isAdvance
                                            ? Colors.amber.shade50
                                            : (isDepositRefund || isDepositToCap ? Colors.teal.shade50 : Colors.blue.shade50)),
                                    child: Icon(
                                      isProfit
                                          ? Icons.arrow_downward_rounded
                                          : (isAdvance
                                              ? Icons.handshake_outlined
                                              : (isDepositRefund
                                                  ? Icons.money_rounded
                                                  : (isDepositToCap ? Icons.upgrade_rounded : Icons.account_balance_wallet_outlined))),
                                      color: isProfit
                                          ? Colors.green.shade700
                                          : (isAdvance
                                              ? Colors.amber.shade800
                                              : (isDepositRefund || isDepositToCap ? Colors.teal.shade700 : Colors.blue.shade700)),
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    '${Money(w.amount).toDisplay()} ج.م (${w.typeLabel})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    '${w.date.year}-${w.date.month.toString().padLeft(2, '0')}-${w.date.day.toString().padLeft(2, '0')}${w.note != null ? " • ${w.note}" : ""}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                                    tooltip: 'حذف حركة الصرف',
                                    onPressed: () => _confirmDeleteWithdrawal(context, partner, w),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  // Delete specific withdrawal with confirmation
  Future<void> _confirmDeleteWithdrawal(
    BuildContext context,
    PartnerEntity partner,
    PartnerWithdrawal withdrawal,
  ) async {
    final cubit = context.read<PartnersCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('تأكيد حذف حركة الصرف', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل تريد حذف حركة الصرف بقيمة ${Money(withdrawal.amount).toDisplay()} ج.م (${withdrawal.typeLabel})؟\n\nسيتم إعادة احتساب أرصدة الشريك تلقائياً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ok = await cubit.deleteWithdrawal(
        partnerId: partner.id,
        withdrawalId: withdrawal.id,
      );
      if (ok && context.mounted) {
        Navigator.pop(context); // close history dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف حركة الصرف وإعادة ضبط الأرصدة بنجاح!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  // Delete specific deposit with confirmation
  Future<void> _confirmDeleteDeposit(
    BuildContext context,
    PartnerEntity partner,
    PartnerDeposit deposit,
  ) async {
    final cubit = context.read<PartnersCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('تأكيد حذف حركة الإيداع', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'هل تريد حذف دفعة التمويل بقيمة ${Money(deposit.amount).toDisplay()} ج.م (${deposit.categoryLabel})؟\n\nسيتم إعادة احتساب أرصدة التمويل تلقائياً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ok = await cubit.deleteDeposit(
        partnerId: partner.id,
        depositId: deposit.id,
      );
      if (ok && context.mounted) {
        Navigator.pop(context); // close history dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف حركة الإيداع وإعادة ضبط رصيد التمويل بنجاح!'),
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
                                  Icon(Icons.date_range_rounded, color: AppColors.primary, size: 20),
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
                              side: BorderSide(color: AppColors.primary),
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
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.pie_chart_outline_rounded, color: AppColors.primary, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'إجمالي رأس المال المسجل: ${Money(state.totalCapital).toDisplay()} ج.م',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
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

                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.grey.shade200),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.02),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        children: [
                                          // 1. Header: Avatar, Name, Clean Badges, Edit & Delete
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              CircleAvatar(
                                                radius: 22,
                                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                                child: Text(
                                                  partner.name.isNotEmpty ? partner.name[0] : 'ش',
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
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
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                          decoration: BoxDecoration(
                                                            color: AppColors.surfaceContainer,
                                                            borderRadius: BorderRadius.circular(8),
                                                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                                                          ),
                                                          child: Text(
                                                            partner.typeLabel,
                                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primary),
                                                          ),
                                                        ),
                                                        if (partner.partnershipType != 'effort_only' && (partner.capital > 0 || partner.capitalPercentage != null))
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                            decoration: BoxDecoration(
                                                              color: Colors.blueGrey.shade50,
                                                              borderRadius: BorderRadius.circular(8),
                                                              border: Border.all(color: Colors.blueGrey.shade200),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                const Icon(Icons.pie_chart_outline_rounded, size: 12, color: Colors.blueGrey),
                                                                const SizedBox(width: 4),
                                                                Text(
                                                                  'حصة رأس المال: ${partner.effectiveCapitalPercentage.toStringAsFixed(1)}%',
                                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blueGrey.shade800),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                          decoration: BoxDecoration(
                                                            color: Colors.purple.shade50,
                                                            borderRadius: BorderRadius.circular(8),
                                                            border: Border.all(color: Colors.purple.shade200),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const Icon(Icons.monetization_on_outlined, size: 12, color: Colors.purple),
                                                              const SizedBox(width: 4),
                                                              Text(
                                                                partner.profitMode == 'fixed_roi'
                                                                    ? 'عائد سنوي: ${partner.roiPercentage.toStringAsFixed(1)}%'
                                                                    : 'نسبة الأرباح: ${partner.percentage.toStringAsFixed(1)}%',
                                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.purple.shade800),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Wrap(
                                                      spacing: 16,
                                                      runSpacing: 4,
                                                      children: [
                                                        if (partner.currentCapital > 0)
                                                          Text(
                                                            'رأس المال النشط: ${Money(partner.currentCapital).toDisplay()} ج.م',
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
                                                        if (partner.notes != null && partner.notes!.isNotEmpty)
                                                          Text(
                                                            '• ${partner.notes!}',
                                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.edit_outlined, color: AppColors.primary, size: 20),
                                                tooltip: 'تعديل الشريك',
                                                visualDensity: VisualDensity.compact,
                                                onPressed: () => _openPartnerDialog(
                                                  context,
                                                  partner: partner,
                                                  currentTotalPercentage: state.totalPercentage,
                                                  existingPartners: state.partners,
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                                                tooltip: 'حذف الشريك',
                                                visualDensity: VisualDensity.compact,
                                                onPressed: () => _confirmDelete(context, partner),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          const Divider(height: 1),
                                          const SizedBox(height: 10),

                                          // 2. Compact Financial Strip for Funding & Advances (شريط التمويل والسلف المدمج)
                                          if (partner.totalDeposited > 0 || partner.remainingAdvance > 0) ...[
                                            Container(
                                              margin: const EdgeInsets.only(bottom: 12),
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade50,
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.grey.shade200),
                                              ),
                                              child: Column(
                                                children: [
                                                  // Personal funding row
                                                  if (partner.totalDeposited > 0) ...[
                                                    Row(
                                                      children: [
                                                        Icon(Icons.account_balance_wallet_outlined, size: 16, color: Colors.teal.shade700),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          'تمويل شخصي من الجيب (لك عند المحل):',
                                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.teal.shade900),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          '${Money(partner.remainingDeposited).toDisplay()} ج.م',
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal.shade900),
                                                        ),
                                                        if (partner.totalDepositsRefunded > 0) ...[
                                                          const SizedBox(width: 6),
                                                          Text(
                                                            '(متبقي من ${Money(partner.totalDeposited).toDisplay()} ج.م)',
                                                            style: TextStyle(fontSize: 11, color: Colors.teal.shade700),
                                                          ),
                                                        ],
                                                        const Spacer(),
                                                        if (partner.remainingDeposited > 0) ...[
                                                          ElevatedButton.icon(
                                                            style: ElevatedButton.styleFrom(
                                                              backgroundColor: Colors.teal.shade700,
                                                              foregroundColor: Colors.white,
                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                              minimumSize: Size.zero,
                                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                            ),
                                                            onPressed: () => _openRefundDepositDialog(context, partner),
                                                            icon: const Icon(Icons.arrow_downward_rounded, size: 12),
                                                            label: const Text('استرداد كاش', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          OutlinedButton.icon(
                                                            style: OutlinedButton.styleFrom(
                                                              foregroundColor: Colors.indigo.shade800,
                                                              side: BorderSide(color: Colors.indigo.shade300),
                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                              minimumSize: Size.zero,
                                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                            ),
                                                            onPressed: () => _openConvertDepositToCapitalDialog(context, partner),
                                                            icon: const Icon(Icons.upgrade_rounded, size: 12),
                                                            label: const Text('ضمه لرأس المال', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ],
                                                  if (partner.totalDeposited > 0 && partner.remainingAdvance > 0)
                                                    const Padding(
                                                      padding: EdgeInsets.symmetric(vertical: 6.0),
                                                      child: Divider(height: 1),
                                                    ),
                                                  // Temporary advance row
                                                  if (partner.remainingAdvance > 0) ...[
                                                    Row(
                                                      children: [
                                                        Icon(Icons.handshake_outlined, size: 16, color: Colors.amber.shade900),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          'سلفة شخصية مؤقتة (عليك للمحل):',
                                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.amber.shade900),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          '${Money(partner.remainingAdvance).toDisplay()} ج.م',
                                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900),
                                                        ),
                                                        const Spacer(),
                                                        ElevatedButton.icon(
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor: Colors.amber.shade800,
                                                            foregroundColor: Colors.white,
                                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                            minimumSize: Size.zero,
                                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                          ),
                                                          onPressed: () => _openDepositDialog(
                                                            context,
                                                            partner,
                                                            initialCategory: 'advance_repayment',
                                                          ),
                                                          icon: const Icon(Icons.assignment_return_outlined, size: 12),
                                                          label: const Text('رد السلفة للدرج', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],

                                          // 3. Financial Stat Grid (أرقام الأرباح والمسحوبات والمستحق)
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: Colors.green.shade200),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text('نصيب الأرباح ($days يوم)', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                                                          Icon(Icons.trending_up_rounded, size: 14, color: Colors.green.shade700),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '${Money(partnerShare).toDisplay()} ج.م',
                                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade800),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: Colors.grey.shade300),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          const Text('أرباح تم استلامها', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                                          Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.grey.shade600),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '${Money(totalWithdrawn).toDisplay()} ج.م',
                                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: Colors.amber.shade300),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text('أرباح باقية بالمحل', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
                                                          Icon(Icons.savings_outlined, size: 14, color: Colors.amber.shade800),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '${Money(partner.getUnwithdrawnProfit(partnerShare)).toDisplay()} ج.م',
                                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.surfaceContainer,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.2),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text('صافي المستحق الكلي', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                                          Icon(Icons.account_balance_wallet_rounded, size: 14, color: AppColors.primary),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        '${Money(partner.calculateNetBalance(partnerShare)).toDisplay()} ج.م',
                                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),

                                          // 4. Action buttons row
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.primary,
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                onPressed: () => _openWithdrawalDialog(context, partner, partnerShare),
                                                icon: const Icon(Icons.payments_outlined, color: Colors.white, size: 16),
                                                label: const Text('صرف أرباح ومسحوبات', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.teal.shade800,
                                                  side: BorderSide(color: Colors.teal.shade400),
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                onPressed: () => _openDepositDialog(context, partner),
                                                icon: const Icon(Icons.add_card_rounded, size: 16),
                                                label: const Text('تمويل ودفع من الجيب', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                              if (partner.getUnwithdrawnProfit(partnerShare) > 0)
                                                OutlinedButton.icon(
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: Colors.indigo.shade800,
                                                    side: BorderSide(color: Colors.indigo.shade300),
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  ),
                                                  onPressed: () => _openReinvestDialog(context, partner, partner.getUnwithdrawnProfit(partnerShare)),
                                                  icon: const Icon(Icons.autorenew_rounded, size: 16),
                                                  label: const Text('تدوير الأرباح كرأس مال', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                ),
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: Colors.grey.shade700,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                                onPressed: () => _showFinancialHistoryDialog(context, partner),
                                                icon: const Icon(Icons.history_rounded, size: 16),
                                                label: const Text('سجل الحركات', style: TextStyle(fontSize: 11)),
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
