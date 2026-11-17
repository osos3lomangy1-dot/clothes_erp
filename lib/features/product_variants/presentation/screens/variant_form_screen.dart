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
      child: _VariantFormBody(product: product, variant: variant),
    );
  }
}

class _VariantFormBody extends StatefulWidget {
  final ProductEntity product;
  final VariantEntity? variant;

  const _VariantFormBody({required this.product, this.variant});

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
  bool _siblingPrefillSynced = false;

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

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VariantFormCubit, VariantFormState>(
      listener: (context, state) {
        _syncFromSiblingState(state);

        if (state.status == VariantFormStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.green,
              content: Text('تم حفظ بيانات المقاس بنجاح'),
            ),
          );
          AppNavigator.pop(context);
        } else if (state.status == VariantFormStatus.error &&
            state.errorMessage != null) {
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
        return Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.onSurface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.onSurface),
              tooltip: 'رجوع',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              state.isEdit
                  ? 'تعديل المقاس: ${widget.product.name}'
                  : 'إضافة مقاس جديد: ${widget.product.name}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppColors.onSurface,
              ),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!state.isEdit && state.prefilledFromSibling) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.auto_fix_high_rounded,
                                    color: Colors.blue.shade700, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'تم تعبئة اللون والأسعار تلقائياً من آخر مقاس مسجل — أدخل المقاس الجديد والكمية فقط.',
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
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _skuCtrl,
                          decoration: InputDecoration(
                            labelText: 'كود المنتج / الباركود',
                            hintText: 'مثال: TSH-BLK-M',
                            errorText: state.hasDuplicateSku
                                ? 'هذا الكود مسجل بالفعل لصنف آخر. لا يمكن تكرار الأكواد.'
                                : null,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onChanged: cubit.onProductCodeChanged,
                        ),
                        if (state.hasDuplicateSku) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red.shade800, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'عفواً، الكود ("${state.productCode.trim()}") مستخدم بالفعل لصنف آخر ولا يمكن تكراره.',
                                    style: TextStyle(
                                      color: Colors.red.shade900,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _colorCtrl,
                                decoration: InputDecoration(
                                  labelText: 'اللون',
                                  hintText: 'مثال: أسود',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                onChanged: cubit.onColorChanged,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: TextFormField(
                                controller: _sizeCtrl,
                                autofocus: !state.isEdit,
                                decoration: InputDecoration(
                                  labelText: 'المقاس',
                                  hintText: 'مثال: L أو 42',
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                onChanged: cubit.onSizeChanged,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _qtyCtrl,
                          decoration: InputDecoration(
                            labelText: 'الكمية الحالية (الرصيد)',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) => cubit
                              .onQuantityChanged(int.tryParse(value) ?? 0),
                        ),
                        const SizedBox(height: 16),
                        Builder(
                          builder: (context) {
                            final authState = context.watch<AuthCubit>().state;
                            final isCashier = authState is AuthAuthenticated &&
                                authState.user.role.toLowerCase() == 'cashier';

                            return Row(
                              children: [
                                if (!isCashier) ...[
                                  Expanded(
                                    child: TextFormField(
                                      controller: _costCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'التكلفة (ج.م)',
                                        hintText: '0.00',
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      onChanged: (value) {
                                        final pounds =
                                            double.tryParse(value) ?? 0.0;
                                        cubit.onCostPriceChanged(
                                            (pounds * 100).round());
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: TextFormField(
                                    controller: _saleCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'سعر القطاعي (ج.م)',
                                      hintText: '0.00',
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    onChanged: (value) {
                                      final pounds =
                                          double.tryParse(value) ?? 0.0;
                                      cubit.onSalePriceChanged(
                                          (pounds * 100).round());
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: _wholesaleCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'سعر الجملة (ج.م)',
                                      hintText: 'اختياري',
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    onChanged: (value) {
                                      final pounds =
                                          double.tryParse(value) ?? 0.0;
                                      cubit.onWholesalePriceChanged(
                                          (pounds * 100).round());
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _minStockCtrl,
                          decoration: InputDecoration(
                            labelText: 'حد إعادة الطلب (تنبيه نقص المخزون)',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (value) => cubit
                              .onMinStockChanged(int.tryParse(value) ?? 0),
                        ),
                        const SizedBox(height: 28),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: (state.status ==
                                      VariantFormStatus.loading ||
                                  state.hasDuplicateSku)
                              ? null
                              : () => cubit.submit(
                                    id: widget.variant?.id,
                                    productId: widget.product.id,
                                  ),
                          child: state.status == VariantFormStatus.loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  state.isEdit ? 'تحديث المقاس' : 'حفظ المقاس',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
