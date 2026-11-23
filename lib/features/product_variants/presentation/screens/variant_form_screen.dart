import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../../../../core/utils/barcode_helper.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../domain/entities/variant_entity.dart';
import '../cubits/variant_form_cubit.dart';
import '../cubits/variant_form_state.dart';

/// Opens a polished modal dialog to add or edit a product variant (size/color/prices).
/// Returns `true` if at least one variant was saved/updated.
Future<bool?> showVariantFormDialog(
  BuildContext context, {
  required ProductEntity product,
  VariantEntity? variant,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => BlocProvider(
      create: (_) => getIt<VariantFormCubit>()
        ..init(
          variant,
          productId: product.id,
          productName: product.name,
        ),
      child: _VariantFormDialogShell(product: product, variant: variant),
    ),
  );
}

/// Legacy full-screen wrapper preserved for backwards compatibility.
class VariantFormScreen extends StatelessWidget {
  final ProductEntity product;
  final VariantEntity? variant;

  const VariantFormScreen({super.key, required this.product, this.variant});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<VariantFormCubit>()
        ..init(
          variant,
          productId: product.id,
          productName: product.name,
        ),
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.onSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.onSurface,
            ),
            tooltip: 'رجوع',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            variant != null
                ? 'تعديل المقاس: ${product.name}'
                : 'إضافة مقاس جديد: ${product.name}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppColors.onSurface,
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _VariantFormBody(
                    product: product,
                    variant: variant,
                    isDialog: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VariantFormDialogShell extends StatelessWidget {
  final ProductEntity product;
  final VariantEntity? variant;

  const _VariantFormDialogShell({required this.product, this.variant});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _VariantFormBody(
          product: product,
          variant: variant,
          isDialog: true,
        ),
      ),
    );
  }
}

class _VariantFormBody extends StatefulWidget {
  final ProductEntity product;
  final VariantEntity? variant;
  final bool isDialog;

  const _VariantFormBody({
    required this.product,
    this.variant,
    required this.isDialog,
  });

  @override
  State<_VariantFormBody> createState() => _VariantFormBodyState();
}

class _VariantFormBodyState extends State<_VariantFormBody> {
  late final TextEditingController _skuCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _sizeCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _saleCtrl;
  late final TextEditingController _wholesaleCtrl;
  late final TextEditingController _minStockCtrl;
  final FocusNode _sizeFocusNode = FocusNode();

  late ActivityType _activeSector;
  bool _siblingPrefillSynced = false;
  bool _addAnotherRequested = false;
  int _savedInSessionCount = 0;

  String _formatPounds(int piasters) {
    if (piasters <= 0) return '';
    final pounds = piasters / 100.0;
    return pounds == pounds.roundToDouble()
        ? pounds.toInt().toString()
        : pounds.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    _activeSector = widget.product.activityTypeEnum;
    final v = widget.variant;
    _skuCtrl = TextEditingController(text: v?.productCode ?? '');
    _colorCtrl = TextEditingController(text: v?.color ?? '');
    _sizeCtrl = TextEditingController(text: v?.size ?? '');
    _qtyCtrl = TextEditingController(text: v != null ? '${v.quantity}' : '0');
    _costCtrl = TextEditingController(
      text: v != null ? _formatPounds(v.costPrice) : '',
    );
    _saleCtrl = TextEditingController(
      text: v != null ? _formatPounds(v.salePrice) : '',
    );
    _wholesaleCtrl = TextEditingController(
      text: v != null && v.wholesalePrice > 0
          ? _formatPounds(v.wholesalePrice)
          : '',
    );
    _minStockCtrl = TextEditingController(
      text: v != null ? '${v.minStock}' : '5',
    );
  }

  @override
  void dispose() {
    _skuCtrl.dispose();
    _colorCtrl.dispose();
    _sizeCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _saleCtrl.dispose();
    _wholesaleCtrl.dispose();
    _minStockCtrl.dispose();
    _sizeFocusNode.dispose();
    super.dispose();
  }

  List<String> _getSizesForCurrentSector() {
    switch (_activeSector) {
      case ActivityType.clothing:
        return const ['S', 'M', 'L', 'XL', '2XL', '3XL', '4XL', '5XL', 'Free Size'];
      case ActivityType.footwearBags:
        return const ['37', '38', '39', '40', '41', '42', '43', '44', '45'];
      case ActivityType.textilesDecor:
        return const ['1.5×2 م', '2×3 م', '2.5×3.5 م', '3×4 م', 'مشاية 1×3 م', 'مشاية 80×2 م', 'رول كامل', 'بالمتر'];
      default:
        return _activeSector.standardSizes.isNotEmpty
            ? _activeSector.standardSizes
            : const ['S', 'M', 'L', 'XL', '2XL', 'Free Size'];
    }
  }

  void _selectSizeChip(String size, VariantFormCubit cubit) {
    _sizeCtrl.text = size;
    cubit.onSizeChanged(size);
    final cleanSku = BarcodeHelper.generateSku(size: size);
    _skuCtrl.text = cleanSku;
    cubit.onProductCodeChanged(cleanSku);
    setState(() {});
  }

  Future<void> _openDimensionToolDialog(VariantFormCubit cubit) async {
    final widthCtrl = TextEditingController(text: '2');
    final lengthCtrl = TextEditingController(text: '3');

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.straighten, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text('تحديد المقاس بالأمتار (مفروشات وسجاد)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'اختر نموذجاً سريعاً أو اكتب العرض والطول بالأمتار:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final preset in const [
                        {'w': '1.5', 'l': '2', 'label': '1.5×2 م'},
                        {'w': '2', 'l': '3', 'label': '2×3 م'},
                        {'w': '2.5', 'l': '3.5', 'label': '2.5×3.5 م'},
                        {'w': '3', 'l': '4', 'label': '3×4 م'},
                        {'w': '1', 'l': '3', 'label': 'مشاية 1×3 م'},
                        {'w': '0.8', 'l': '2', 'label': 'مشاية 80×2 م'},
                      ])
                        ActionChip(
                          label: Text(preset['label']!, style: const TextStyle(fontSize: 11)),
                          onPressed: () {
                            setDialogState(() {
                              widthCtrl.text = preset['w']!;
                              lengthCtrl.text = preset['l']!;
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('dimension_width_field'),
                          controller: widthCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'العرض (م)',
                            hintText: 'مثال: 2 أو 1.8',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('×', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('dimension_length_field'),
                          controller: lengthCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'الطول (م)',
                            hintText: 'مثال: 3 أو 2.7',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                key: const Key('confirm_dimension_btn'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                icon: const Icon(Icons.check, color: Colors.white, size: 18),
                label: const Text('تطبيق المقاس', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  final w = widthCtrl.text.trim();
                  final l = lengthCtrl.text.trim();
                  if (w.isEmpty || l.isEmpty) return;
                  final formatted = '$w×$l م';
                  _selectSizeChip(formatted, cubit);
                  Navigator.pop(dialogCtx);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectorDropdown() {
    return PopupMenuButton<ActivityType>(
      tooltip: 'تغيير نوع المقاسات',
      initialValue: _activeSector,
      onSelected: (act) => setState(() => _activeSector = act),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _activeSector.labelArabic,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          Icon(Icons.arrow_drop_down, size: 18, color: AppColors.primary),
        ],
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: ActivityType.clothing,
          child: Text('ملابس وأزياء (S..5XL)'),
        ),
        const PopupMenuItem(
          value: ActivityType.footwearBags,
          child: Text('أحذية وشنط (37..45)'),
        ),
        const PopupMenuItem(
          value: ActivityType.textilesDecor,
          child: Text('مفروشات وسجاد وأقمشة'),
        ),
      ],
    );
  }

  Widget _buildAdaptiveSizeChipsSection(VariantFormCubit cubit) {
    final sizes = _getSizesForCurrentSector();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'مقاسات سريعة:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              _buildSectorDropdown(),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final size in sizes)
                ActionChip(
                  key: Key('size_chip_$size'),
                  label: Text(
                    size,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: _sizeCtrl.text == size
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: _sizeCtrl.text == size
                          ? AppColors.primary
                          : Colors.grey.shade800,
                    ),
                  ),
                  backgroundColor: _sizeCtrl.text == size
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : Colors.white,
                  side: BorderSide(
                    color: _sizeCtrl.text == size
                        ? AppColors.primary
                        : Colors.grey.shade300,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  onPressed: () => _selectSizeChip(size, cubit),
                ),
              OutlinedButton.icon(
                key: const Key('variant_dimension_tool_btn'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.blueGrey.shade300),
                  ),
                ),
                icon: const Icon(Icons.straighten, size: 14),
                label: const Text(
                  'مقاس بالأمتار',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _openDimensionToolDialog(cubit),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _syncFromSiblingState(VariantFormState state) {
    if (_siblingPrefillSynced || widget.variant != null) return;
    if (!state.prefilledFromSibling) return;
    _siblingPrefillSynced = true;

    if (_skuCtrl.text.isEmpty && state.productCode.isNotEmpty) {
      _skuCtrl.text = state.productCode;
    }
    if (_colorCtrl.text.isEmpty && state.color.isNotEmpty) {
      _colorCtrl.text = state.color;
    }
    if (_costCtrl.text.isEmpty && state.costPrice > 0) {
      _costCtrl.text = _formatPounds(state.costPrice);
    }
    if (_saleCtrl.text.isEmpty && state.salePrice > 0) {
      _saleCtrl.text = _formatPounds(state.salePrice);
    }
    if (_wholesaleCtrl.text.isEmpty && state.wholesalePrice > 0) {
      _wholesaleCtrl.text = _formatPounds(state.wholesalePrice);
    }
  }

  Future<void> _handleSaveSuccess(
    BuildContext context,
    VariantFormCubit cubit,
  ) async {
    _savedInSessionCount++;
    if (_addAnotherRequested && widget.variant == null) {
      _addAnotherRequested = false;
      await cubit.prepareNextVariant(productName: widget.product.name);
      if (!mounted) return;
      _skuCtrl.text = cubit.state.productCode;
      _sizeCtrl.clear();
      _qtyCtrl.text = '0';
      setState(() {});
      _sizeFocusNode.requestFocus();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Text(
          widget.variant != null
              ? 'تم تحديث بيانات المقاس بنجاح'
              : 'تم حفظ بيانات المقاس بنجاح',
        ),
      ),
    );
    if (widget.isDialog) {
      Navigator.of(context).pop(true);
    } else {
      AppNavigator.pop(context);
    }
  }

  void _closeDialog(BuildContext context) {
    if (widget.isDialog) {
      Navigator.of(context).pop(_savedInSessionCount > 0);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  InputDecoration _cleanFieldDecoration({
    String? hintText,
    String? errorText,
    IconData? prefixIcon,
  }) {
    final borderRadius = BorderRadius.circular(10);
    final normalBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
      errorText: errorText,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      isDense: true,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: Colors.grey.shade600)
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: normalBorder,
      enabledBorder: normalBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: AppColors.primary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: AppColors.error, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: const BorderSide(color: AppColors.error, width: 1.8),
      ),
    );
  }

  Widget _labeledField({
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, right: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VariantFormCubit, VariantFormState>(
      listener: (context, state) {
        _syncFromSiblingState(state);

        if (state.status == VariantFormStatus.success) {
          _handleSaveSuccess(context, context.read<VariantFormCubit>());
        } else if (state.status == VariantFormStatus.error &&
            state.errorMessage != null) {
          _addAnotherRequested = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppColors.error,
              content: Text(state.errorMessage!),
            ),
          );
        }
      },
      builder: (context, state) {
        final cubit = context.read<VariantFormCubit>();
        final isLoading = state.status == VariantFormStatus.loading;
        final canSubmit = !isLoading && !state.hasDuplicateSku;

        final formFields = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_savedInSessionCount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم حفظ $_savedInSessionCount مقاس بنجاح — يمكنك إدخال المقاس التالي مباشرة.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!state.isEdit &&
                state.prefilledFromSibling &&
                _savedInSessionCount == 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_fix_high_rounded,
                      color: Colors.blue.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تم تعبئة اللون والأسعار تلقائياً من آخر مقاس — أدخل المقاس الجديد والكمية فقط.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            _labeledField(
              label: 'كود الصنف / الباركود (SKU)',
              child: TextFormField(
                controller: _skuCtrl,
                decoration: _cleanFieldDecoration(
                  hintText: 'مثال: TSH-BLK-M',
                  prefixIcon: Icons.qr_code_2_rounded,
                  errorText: state.hasDuplicateSku
                      ? 'هذا الكود مسجل بالفعل لصنف آخر ولا يمكن تكراره.'
                      : null,
                ),
                onChanged: cubit.onProductCodeChanged,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _labeledField(
                    label: 'اللون',
                    child: TextFormField(
                      controller: _colorCtrl,
                      decoration: _cleanFieldDecoration(
                        hintText: 'مثال: أسود',
                        prefixIcon: Icons.palette_outlined,
                      ),
                      onChanged: cubit.onColorChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _labeledField(
                    label: 'المقاس',
                    child: TextFormField(
                      controller: _sizeCtrl,
                      focusNode: _sizeFocusNode,
                      autofocus: !state.isEdit,
                      decoration: _cleanFieldDecoration(
                        hintText: 'مثال: L أو 42 أو 2×3 م',
                        prefixIcon: Icons.straighten_rounded,
                      ),
                      onChanged: (val) {
                        cubit.onSizeChanged(val);
                        setState(() {});
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildAdaptiveSizeChipsSection(cubit),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _labeledField(
                    label: 'الكمية الحالية (الرصيد)',
                    child: TextFormField(
                      controller: _qtyCtrl,
                      decoration: _cleanFieldDecoration(
                        hintText: '0',
                        prefixIcon: Icons.inventory_2_outlined,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) =>
                          cubit.onQuantityChanged(int.tryParse(value) ?? 0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _labeledField(
                    label: 'حد إعادة الطلب (التنبيه)',
                    child: TextFormField(
                      controller: _minStockCtrl,
                      decoration: _cleanFieldDecoration(
                        hintText: '5',
                        prefixIcon: Icons.notifications_active_outlined,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) =>
                          cubit.onMinStockChanged(int.tryParse(value) ?? 0),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Builder(
              builder: (context) {
                final authState = context.watch<AuthCubit>().state;
                final isCashier = authState is AuthAuthenticated &&
                    authState.user.role.toLowerCase() == 'cashier';

                return Row(
                  children: [
                    if (!isCashier) ...[
                      Expanded(
                        child: _labeledField(
                          label: 'التكلفة (ج.م)',
                          child: TextFormField(
                            controller: _costCtrl,
                            decoration: _cleanFieldDecoration(hintText: '0.00'),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (value) {
                              final pounds = double.tryParse(value) ?? 0.0;
                              cubit.onCostPriceChanged((pounds * 100).round());
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: _labeledField(
                        label: 'سعر القطاعي (ج.م)',
                        child: TextFormField(
                          controller: _saleCtrl,
                          decoration: _cleanFieldDecoration(hintText: '0.00'),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (value) {
                            final pounds = double.tryParse(value) ?? 0.0;
                            cubit.onSalePriceChanged((pounds * 100).round());
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _labeledField(
                        label: 'سعر الجملة (ج.م)',
                        child: TextFormField(
                          controller: _wholesaleCtrl,
                          decoration: _cleanFieldDecoration(
                            hintText: 'اختياري',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (value) {
                            final pounds = double.tryParse(value) ?? 0.0;
                            cubit.onWholesalePriceChanged(
                              (pounds * 100).round(),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );

        final footerActions = Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            TextButton(
              onPressed: isLoading ? null : () => _closeDialog(context),
              child: Text(
                _savedInSessionCount > 0 ? 'إغلاق' : 'إلغاء',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
            if (!state.isEdit)
              OutlinedButton.icon(
                key: const Key('variant_save_and_add_another_btn'),
                onPressed: canSubmit
                    ? () {
                        _addAnotherRequested = true;
                        cubit.submit(
                          id: null,
                          productId: widget.product.id,
                        );
                      }
                    : null,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: const Text('حفظ وإضافة آخر'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ElevatedButton.icon(
              key: const Key('variant_submit_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: canSubmit
                  ? () {
                      _addAnotherRequested = false;
                      cubit.submit(
                        id: widget.variant?.id,
                        productId: widget.product.id,
                      );
                    }
                  : null,
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      state.isEdit
                          ? Icons.save_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
              label: Text(
                state.isEdit ? 'تحديث المقاس' : 'حفظ المقاس',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14.5,
                ),
              ),
            ),
          ],
        );

        if (!widget.isDialog) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              formFields,
              const SizedBox(height: 24),
              footerActions,
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dialog Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      state.isEdit
                          ? Icons.edit_note_rounded
                          : Icons.add_box_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.isEdit ? 'تعديل المقاس' : 'إضافة مقاس جديد',
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          widget.product.name,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'إغلاق',
                    onPressed: isLoading ? null : () => _closeDialog(context),
                  ),
                ],
              ),
            ),
            // Scrollable Form Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: formFields,
              ),
            ),
            // Dialog Footer Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: footerActions,
            ),
          ],
        );
      },
    );
  }
}
