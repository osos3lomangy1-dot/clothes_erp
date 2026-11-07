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

  void _openPartnerDialog(BuildContext context, {PartnerEntity? partner, required double currentTotalPercentage}) {
    final cubit = context.read<PartnersCubit>();
    final isEdit = partner != null;
    final nameCtrl = TextEditingController(text: partner?.name ?? '');
    final phoneCtrl = TextEditingController(text: partner?.phone ?? '');
    final percentageCtrl = TextEditingController(text: partner != null ? '${partner.percentage}' : '');
    final capitalCtrl = TextEditingController(text: partner != null && partner.capital > 0 ? '${partner.capital / 100}' : '');
    final notesCtrl = TextEditingController(text: partner?.notes ?? '');
    final formKey = GlobalKey<FormState>();

    // calculate max percentage allowed
    final otherPercentages = isEdit ? (currentTotalPercentage - partner.percentage) : currentTotalPercentage;
    final maxAllowed = (100.0 - otherPercentages).clamp(0.0, 100.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.handshake_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              isEdit ? 'تعديل بيانات الشريك' : 'إضافة شريك جديد',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'اسم الشريك *',
                      hintText: 'مثال: أستاذ أحمد فؤاد',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    validator: (val) => val == null || val.trim().isEmpty ? 'يرجى إدخال اسم الشريك' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'رقم الهاتف (اختياري)',
                      hintText: 'مثال: 01012345678',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: percentageCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'النسبة المئوية من الأرباح (%) *',
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: capitalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'رأس المال المستثمر (ج.م) (اختياري)',
                      hintText: 'مثال: 100000',
                      suffixText: 'ج.م',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'ملاحظات إضافية (اختياري)',
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final percent = double.tryParse(percentageCtrl.text.trim()) ?? 0.0;
              final capPounds = double.tryParse(capitalCtrl.text.trim()) ?? 0.0;

              final toSave = PartnerEntity(
                id: partner?.id ?? '',
                name: nameCtrl.text.trim(),
                phone: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                percentage: percent,
                capital: (capPounds * 100).toInt(),
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
      ),
    );
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
                    'نظام الشركاء وتوزيع الأرباح',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
                  ),
                  Text(
                    'تحديد حصص الشركاء واحتساب صافي الأرباح المستحقة عن أي فترة',
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
                                        ? 'الفترة المحتسبة: ${_dateRange!.start.toLocal().toString().split(' ')[0]} إلى ${_dateRange!.end.toLocal().toString().split(' ')[0]}'
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

                    // Partners Shares Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.people_outline_rounded, color: AppColors.primary, size: 22),
                          const SizedBox(width: 8),
                          const Text(
                            'بيان أنصبة وأرباح الشركاء',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: state.totalPercentage == 100.0 ? Colors.green.shade50 : Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: state.totalPercentage == 100.0 ? Colors.green.shade300 : Colors.amber.shade400,
                              ),
                            ),
                            child: Text(
                              'إجمالي الحصص المسجلة: ${state.totalPercentage.toStringAsFixed(1)}% من 100%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: state.totalPercentage == 100.0 ? Colors.green.shade800 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
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
                                        'سجل الشركاء ونسبهم من الأرباح ليقوم النظام بتوزيع صافي الدخل تلقائياً',
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
                                    final partnerShare = partner.calculateProfitShare(netProfit);

                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
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
                                                Row(
                                                  children: [
                                                    Text(partner.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                    const SizedBox(width: 10),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.surfaceContainer,
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                                      ),
                                                      child: Text(
                                                        'نسبة الربح: ${partner.percentage.toStringAsFixed(1)}%',
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    if (partner.phone != null && partner.phone!.isNotEmpty) ...[
                                                      Text(
                                                        'الهاتف: ${partner.phone}',
                                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                                      ),
                                                      const SizedBox(width: 14),
                                                    ],
                                                    if (partner.capital > 0) ...[
                                                      Text(
                                                        'رأس المال: ${Money(partner.capital).toDisplay()} ج.م',
                                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                if (partner.notes != null && partner.notes!.isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    partner.notes!,
                                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: netProfit >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: netProfit >= 0 ? Colors.green.shade300 : Colors.red.shade300,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  'نصيب الشريك المستحق',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: netProfit >= 0 ? Colors.green.shade900 : Colors.red.shade900,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${Money(partnerShare).toDisplay()} ج.م',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 18,
                                                    color: netProfit >= 0 ? Colors.green.shade900 : Colors.red.shade900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                                            tooltip: 'تعديل الشريك',
                                            onPressed: () => _openPartnerDialog(
                                              context,
                                              partner: partner,
                                              currentTotalPercentage: state.totalPercentage,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                                            tooltip: 'حذف الشريك',
                                            onPressed: () => _confirmDelete(context, partner),
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

