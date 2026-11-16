import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/di/injection.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/domain/repositories/category_repository.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../domain/entities/promotion.dart';
import '../cubits/promotions_cubit.dart';
import 'category_picker_dialog.dart';
import 'product_picker_dialog.dart';

class PromotionFormDialog extends StatefulWidget {
  final Promotion? existing;
  final Future<void> Function(Promotion)? onSubmit;
  final ProductRepository? productRepo;
  final CategoryRepository? categoryRepo;

  const PromotionFormDialog({
    super.key,
    this.existing,
    this.onSubmit,
    this.productRepo,
    this.categoryRepo,
  });

  @override
  State<PromotionFormDialog> createState() => _PromotionFormDialogState();
}

class _PromotionFormDialogState extends State<PromotionFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _valueCtrl;
  late TextEditingController _minQtyCtrl;
  late TextEditingController _priorityCtrl;

  late String _type; // 'percent' | 'fixed'
  late String _scope; // 'all' | 'product' | 'category'
  late DateTime _startsAt;
  late DateTime _endsAt;
  late bool _isActive;

  List<String> _selectedTargetIds = [];
  List<String> _selectedTargetNames = [];
  String? _targetError;

  ProductRepository get _pRepo =>
      widget.productRepo ?? getIt<ProductRepository>();
  CategoryRepository get _cRepo =>
      widget.categoryRepo ?? getIt<CategoryRepository>();

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
    _minQtyCtrl =
        TextEditingController(text: (p?.minQuantity ?? 1).toString());
    _priorityCtrl =
        TextEditingController(text: (p?.priority ?? 0).toString());

    _type = p?.type ?? 'percent';
    _scope = p?.scope ?? 'all';
    _startsAt = p?.startsAt ?? DateTime.now();
    _endsAt = p?.endsAt ?? DateTime.now().add(const Duration(days: 7));
    _isActive = p?.isActive ?? true;

    if (p != null) {
      final targets = p.targetIds.isNotEmpty
          ? p.targetIds
          : (p.targetId != null && p.targetId!.isNotEmpty
              ? [p.targetId!]
              : <String>[]);
      _selectedTargetIds = List<String>.from(targets);
      _loadTargetNames();
    }
  }

  Future<void> _loadTargetNames() async {
    if (_selectedTargetIds.isEmpty) return;

    if (_scope == 'product') {
      final res = await _pRepo.getProducts();
      final products = res.getOrElse(() => <ProductEntity>[]);
      final names = <String>[];
      for (final id in _selectedTargetIds) {
        final match = products.where((p) => p.id == id).toList();
        names.add(match.isNotEmpty ? match.first.name : id);
      }
      if (mounted) setState(() => _selectedTargetNames = names);
    } else if (_scope == 'category') {
      final res = await _cRepo.getCategories();
      final categories = res.getOrElse(() => <CategoryEntity>[]);
      final names = <String>[];
      for (final id in _selectedTargetIds) {
        final match = categories.where((c) => c.id == id).toList();
        names.add(match.isNotEmpty ? match.first.name : id);
      }
      if (mounted) setState(() => _selectedTargetNames = names);
    }
  }

  Future<void> _pickProducts() async {
    final result = await showDialog<List<ProductEntity>>(
      context: context,
      builder: (_) => ProductPickerDialog(
        initialSelectedIds: _selectedTargetIds,
        repository: widget.productRepo,
      ),
    );
    if (result != null) {
      setState(() {
        _selectedTargetIds = result.map((p) => p.id).toList();
        _selectedTargetNames = result.map((p) => p.name).toList();
        _targetError = null;
      });
    }
  }

  Future<void> _pickCategories() async {
    final result = await showDialog<List<CategoryEntity>>(
      context: context,
      builder: (_) => CategoryPickerDialog(
        initialSelectedIds: _selectedTargetIds,
        repository: widget.categoryRepo,
      ),
    );
    if (result != null) {
      setState(() {
        _selectedTargetIds = result.map((c) => c.id).toList();
        _selectedTargetNames = result.map((c) => c.name).toList();
        _targetError = null;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _valueCtrl.dispose();
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
        style:
            const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
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
                            style:
                                TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                        icon: Icon(Icons.percent_rounded, size: 16),
                      ),
                      ButtonSegment(
                        value: 'fixed',
                        label: Text('مبلغ ثابت (ج.م)',
                            style:
                                TextStyle(fontFamily: 'Cairo', fontSize: 13)),
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
                  decoration:
                      const InputDecoration(border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'all',
                        child: Text('كل المنتجات',
                            style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'product',
                        child: Text('منتجات محددة',
                            style: TextStyle(fontFamily: 'Cairo'))),
                    DropdownMenuItem(
                        value: 'category',
                        child: Text('أقسام محددة',
                            style: TextStyle(fontFamily: 'Cairo'))),
                  ],
                  onChanged: (v) => setState(() {
                    _scope = v!;
                    _selectedTargetIds = [];
                    _selectedTargetNames = [];
                    _targetError = null;
                  }),
                ),
                const SizedBox(height: 12),

                // Multi-select Pickers
                if (_scope == 'product') ...[
                  OutlinedButton.icon(
                    onPressed: _pickProducts,
                    icon: const Icon(Icons.search),
                    label: Text(
                      _selectedTargetIds.isEmpty
                          ? 'اختيار المنتجات'
                          : '${_selectedTargetIds.length} منتج محدد',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                  if (_selectedTargetNames.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: List.generate(
                          _selectedTargetIds.length,
                          (i) => Chip(
                            label: Text(
                              i < _selectedTargetNames.length
                                  ? _selectedTargetNames[i]
                                  : _selectedTargetIds[i],
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 11),
                            ),
                            onDeleted: () => setState(() {
                              _selectedTargetIds.removeAt(i);
                              if (i < _selectedTargetNames.length) {
                                _selectedTargetNames.removeAt(i);
                              }
                            }),
                          ),
                        ),
                      ),
                    ),
                  if (_targetError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _targetError!,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.red,
                            fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                ] else if (_scope == 'category') ...[
                  OutlinedButton.icon(
                    onPressed: _pickCategories,
                    icon: const Icon(Icons.category_outlined),
                    label: Text(
                      _selectedTargetIds.isEmpty
                          ? 'اختيار الأقسام'
                          : '${_selectedTargetIds.length} قسم محدد',
                      style: const TextStyle(fontFamily: 'Cairo'),
                    ),
                  ),
                  if (_selectedTargetNames.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: List.generate(
                          _selectedTargetIds.length,
                          (i) => Chip(
                            label: Text(
                              i < _selectedTargetNames.length
                                  ? _selectedTargetNames[i]
                                  : _selectedTargetIds[i],
                              style: const TextStyle(
                                  fontFamily: 'Cairo', fontSize: 11),
                            ),
                            onDeleted: () => setState(() {
                              _selectedTargetIds.removeAt(i);
                              if (i < _selectedTargetNames.length) {
                                _selectedTargetNames.removeAt(i);
                              }
                            }),
                          ),
                        ),
                      ),
                    ),
                  if (_targetError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _targetError!,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.red,
                            fontSize: 12),
                      ),
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
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12),
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
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12),
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

    if (_scope != 'all' && _selectedTargetIds.isEmpty) {
      setState(() {
        _targetError = _scope == 'product'
            ? 'اختر منتجاً واحداً على الأقل'
            : 'اختر قسماً واحداً على الأقل';
      });
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

    final branchId = await getIt<BranchProvider>().getBranchId();
    final now = DateTime.now();

    final promo = Promotion(
      id: widget.existing?.id ?? const Uuid().v4(),
      branchId: branchId,
      name: _nameCtrl.text.trim(),
      description:
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      type: _type,
      scope: _scope,
      targetIds: _scope == 'all' ? const [] : _selectedTargetIds,
      targetId: _scope == 'all'
          ? null
          : (_selectedTargetIds.isNotEmpty ? _selectedTargetIds.first : null),
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

    if (widget.onSubmit != null) {
      await widget.onSubmit!(promo);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (!mounted) return;
    final cubit = context.read<PromotionsCubit>();
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
