import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../domain/entities/promotion.dart';
import '../cubits/promotions_cubit.dart';

class PromotionsScreen extends StatelessWidget {
  const PromotionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<PromotionsCubit>()..loadAll(),
      child: const _PromotionsView(),
    );
  }
}

class _PromotionsView extends StatefulWidget {
  const _PromotionsView();

  @override
  State<_PromotionsView> createState() => _PromotionsViewState();
}

class _PromotionsViewState extends State<_PromotionsView> {
  String _selectedFilter = 'all'; // 'all', 'active', 'inactive', 'expired'

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
  }

  void _checkAdminAccess() async {
    final featureGate = getIt<FeatureGate>();
    final isAdmin = await featureGate.isCurrentUserAdmin();
    if (!isAdmin && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'غير مصرح: إدارة العروض الترويجية متاحة للمدير فقط',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        title: const Text(
          'إدارة العروض والخصومات الترويجية',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
            onPressed: () => context.read<PromotionsCubit>().loadAll(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                _buildFilterChip('all', 'الكل'),
                const SizedBox(width: 8),
                _buildFilterChip('active', 'النشطة حالياً'),
                const SizedBox(width: 8),
                _buildFilterChip('inactive', 'المعطلة'),
                const SizedBox(width: 8),
                _buildFilterChip('expired', 'المنتهية'),
              ],
            ),
          ),
          const Divider(height: 1),

          // Promotions List
          Expanded(
            child: BlocConsumer<PromotionsCubit, PromotionsState>(
              listener: (context, state) {
                if (state.errorMessage != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        state.errorMessage!,
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state.status == PromotionsStatus.loading) {
                  return const Center(child: CircularProgressIndicator());
                }

                final now = DateTime.now();
                var filtered = state.promotions;
                if (_selectedFilter == 'active') {
                  filtered = filtered.where((p) => p.isEffectiveAt(now)).toList();
                } else if (_selectedFilter == 'inactive') {
                  filtered = filtered.where((p) => !p.isActive).toList();
                } else if (_selectedFilter == 'expired') {
                  filtered = filtered.where((p) => p.endsAt.isBefore(now)).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.local_offer_outlined,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد عروض مسجلة تطابق الفلتر',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final promo = filtered[index];
                    return _PromotionCard(
                      promotion: promo,
                      onEdit: () => _openFormDialog(context, existing: promo),
                      onToggleActive: () {
                        if (promo.isActive) {
                          context
                              .read<PromotionsCubit>()
                              .deactivatePromotion(promo.id);
                        } else {
                          context
                              .read<PromotionsCubit>()
                              .updatePromotion(promo.copyWith(
                                isActive: true,
                                updatedAt: DateTime.now(),
                              ));
                        }
                      },
                      onDelete: () => _confirmDelete(context, promo),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _openFormDialog(context),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'إنشاء عرض جديد',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.primaryContainer,
      labelStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? AppColors.primary : Colors.grey.shade700,
      ),
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }

  void _openFormDialog(BuildContext context, {Promotion? existing}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => BlocProvider.value(
        value: context.read<PromotionsCubit>(),
        child: PromotionFormDialog(existing: existing),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Promotion promo) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('تأكيد الحذف', style: TextStyle(fontFamily: 'Cairo')),
        content: Text(
          'هل تريد بالتأكيد حذف العرض "${promo.name}"؟',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              context.read<PromotionsCubit>().deletePromotion(promo.id);
            },
            child: const Text('حذف',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _PromotionCard extends StatelessWidget {
  final Promotion promotion;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _PromotionCard({
    required this.promotion,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrentlyActive = promotion.isEffectiveAt(now);

    String valueDisplay = '';
    if (promotion.type == 'percent') {
      final percent = (promotion.valueBp ?? 0) / 100;
      valueDisplay = '$percent%';
    } else {
      valueDisplay = '${Money(promotion.valuePiasters ?? 0).toDisplay()} ج.م';
    }

    String scopeDisplay = 'كل المنتجات';
    if (promotion.scope == 'product') {
      scopeDisplay = 'منتج محدد (${promotion.targetId ?? ""})';
    } else if (promotion.scope == 'category') {
      scopeDisplay = 'قسم محدد (${promotion.targetId ?? ""})';
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    promotion.name,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isCurrentlyActive
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isCurrentlyActive
                          ? Colors.green.shade300
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    isCurrentlyActive ? 'سارٍ الآن' : 'غير نشط',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isCurrentlyActive
                          ? Colors.green.shade700
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEdit,
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: Colors.red),
                  onPressed: onDelete,
                  tooltip: 'حذف',
                ),
              ],
            ),
            if (promotion.description != null &&
                promotion.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                promotion.description!,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildTag(Icons.discount_outlined, 'قيمة الخصم: $valueDisplay',
                    AppColors.primary),
                _buildTag(Icons.category_outlined, 'النطاق: $scopeDisplay',
                    Colors.indigo),
                if (promotion.minQuantity > 1)
                  _buildTag(Icons.shopping_bag_outlined,
                      'حد أدنى: ${promotion.minQuantity} قطع', Colors.teal),
                _buildTag(Icons.star_outline,
                    'الأولوية: ${promotion.priority}', Colors.orange.shade800),
                _buildTag(
                  Icons.calendar_today_outlined,
                  'من ${_formatDate(promotion.startsAt)} إلى ${_formatDate(promotion.endsAt)}',
                  Colors.blueGrey,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}/${d.month}/${d.day}';
  }
}

class PromotionFormDialog extends StatefulWidget {
  final Promotion? existing;

  const PromotionFormDialog({super.key, this.existing});

  @override
  State<PromotionFormDialog> createState() => _PromotionFormDialogState();
}

class _PromotionFormDialogState extends State<PromotionFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _valueCtrl;
  late TextEditingController _targetIdCtrl;
  late TextEditingController _minQtyCtrl;
  late TextEditingController _priorityCtrl;

  late String _type; // 'percent' | 'fixed'
  late String _scope; // 'all' | 'product' | 'category'
  late DateTime _startsAt;
  late DateTime _endsAt;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');

    String initVal = '';
    if (p != null) {
      if (p.type == 'percent') {
        initVal = ((p.valueBp ?? 0) / 100).toString();
      } else {
        initVal = ((p.valuePiasters ?? 0) / 100).toString();
      }
    }
    _valueCtrl = TextEditingController(text: initVal);
    _targetIdCtrl = TextEditingController(text: p?.targetId ?? '');
    _minQtyCtrl =
        TextEditingController(text: (p?.minQuantity ?? 1).toString());
    _priorityCtrl =
        TextEditingController(text: (p?.priority ?? 0).toString());

    _type = p?.type ?? 'percent';
    _scope = p?.scope ?? 'all';
    _startsAt = p?.startsAt ?? DateTime.now();
    _endsAt = p?.endsAt ?? DateTime.now().add(const Duration(days: 7));
    _isActive = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _valueCtrl.dispose();
    _targetIdCtrl.dispose();
    _minQtyCtrl.dispose();
    _priorityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return AlertDialog(
      title: Text(
        isEdit ? 'تعديل العرض الترويجي' : 'إنشاء عرض ترويجي جديد',
        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم العرض *',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'Cairo'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'اسم العرض مطلوب' : null,
                ),
                const SizedBox(height: 12),

                // Description
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الوصف (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
                const SizedBox(height: 12),

                // Type selector
                const Text('نوع الخصم:',
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'percent',
                        label: Text('نسبة مئوية (%)',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                        icon: Icon(Icons.percent_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: 'fixed',
                        label: Text('مبلغ ثابت (ج.م)',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                        icon: Icon(Icons.attach_money_rounded, size: 16),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (set) =>
                        setState(() => _type = set.first),
                  ),
                ),
                const SizedBox(height: 12),

                // Value input
                TextFormField(
                  controller: _valueCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: _type == 'percent'
                        ? 'النسبة المئوية (%) * (مثال: 15)'
                        : 'المبلغ الثابت للقطعة (ج.م) * (مثال: 50)',
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'Cairo'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'القيمة مطلوبة';
                    final n = double.tryParse(v);
                    if (n == null || n <= 0) return 'أدخل رقماً موجباً أكبر من 0';
                    if (_type == 'percent' && n > 100) {
                      return 'النسبة المئوية لا يمكن أن تتجاوز 100%';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Scope selector
                const Text('نطاق التطبيق:',
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                DropdownButtonFormField<String>(
                  initialValue: _scope,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'all',
                        child: Text('كل المنتجات',
                            style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'product',
                        child: Text('منتج محدد',
                            style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'category',
                        child: Text('قسم محدد',
                            style: TextStyle(fontFamily: 'Cairo'))),
                  ],
                  onChanged: (v) => setState(() => _scope = v!),
                ),
                const SizedBox(height: 12),

                // Target ID if not all
                if (_scope != 'all') ...[
                  TextFormField(
                    controller: _targetIdCtrl,
                    decoration: InputDecoration(
                      labelText: _scope == 'product'
                          ? 'معرّف المنتج (Target ID) *'
                          : 'معرّف القسم (Target ID) *',
                      border: const OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'Cairo'),
                    validator: (v) {
                      if (_scope != 'all' && (v == null || v.trim().isEmpty)) {
                        return 'معرّف الهدف مطلوب عند تحديد النطاق';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // Min Quantity & Priority
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minQtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الحد الأدنى للكمية',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Cairo'),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n < 1) return 'يجب أن يكون 1 أو أكثر';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _priorityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الأولوية (رقم)',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Dates
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range, size: 16),
                        label: Text(
                          'من: ${_startsAt.year}/${_startsAt.month}/${_startsAt.day}',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                        ),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _startsAt,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (d != null) setState(() => _startsAt = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.date_range, size: 16),
                        label: Text(
                          'إلى: ${_endsAt.year}/${_endsAt.month}/${_endsAt.day}',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                        ),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _endsAt,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (d != null) setState(() => _endsAt = d);
                        },
                      ),
                    ),
                  ],
                ),
                if (!_endsAt.isAfter(_startsAt)) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'يجب أن يكون تاريخ النهاية بعد تاريخ البداية',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: Colors.red, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 12),

                // Active Switch
                SwitchListTile(
                  title: const Text('العرض مفعل',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: _submit,
          child: Text(
            isEdit ? 'حفظ التعديلات' : 'إنشاء العرض',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_endsAt.isAfter(_startsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تاريخ النهاية يجب أن يكون بعد تاريخ البداية',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final rawVal = double.parse(_valueCtrl.text.trim());
    int? valueBp;
    int? valuePiasters;
    if (_type == 'percent') {
      valueBp = (rawVal * 100).round();
    } else {
      valuePiasters = (rawVal * 100).round();
    }

    final cubit = context.read<PromotionsCubit>();
    final branchId = await getIt<BranchProvider>().getBranchId();
    final now = DateTime.now();

    final promo = Promotion(
      id: widget.existing?.id ?? const Uuid().v4(),
      branchId: branchId,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      type: _type,
      scope: _scope,
      targetId: _scope == 'all' ? null : _targetIdCtrl.text.trim(),
      valueBp: valueBp,
      valuePiasters: valuePiasters,
      minQuantity: int.parse(_minQtyCtrl.text.trim()),
      startsAt: _startsAt,
      endsAt: _endsAt,
      isActive: _isActive,
      priority: int.tryParse(_priorityCtrl.text.trim()) ?? 0,
      createdBy: widget.existing?.createdBy ?? 'admin',
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    bool success;
    if (widget.existing != null) {
      success = await cubit.updatePromotion(promo);
    } else {
      success = await cubit.createPromotion(promo);
    }

    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }
}

