import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
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
                        hintText: 'مثال: L أو 42',
                        prefixIcon: Icons.straighten_rounded,
                      ),
                      onChanged: cubit.onSizeChanged,
                    ),
                  ),
                ),
              ],
            ),
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

        final footerActions = Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: isLoading ? null : () => _closeDialog(context),
              child: Text(
                _savedInSessionCount > 0 ? 'إغلاق' : 'إلغاء',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
            const Spacer(),
            if (!state.isEdit) ...[
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
              const SizedBox(width: 10),
            ],
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
