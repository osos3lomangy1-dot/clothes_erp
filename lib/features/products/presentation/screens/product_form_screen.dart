import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/navigation/app_navigator.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../data/datasources/product_local_data_source.dart';
import '../../domain/entities/product_entity.dart';
import '../cubits/product_form_cubit.dart';
import '../cubits/product_form_state.dart';

class ProductFormScreen extends StatelessWidget {
  final ProductEntity? product;

  const ProductFormScreen({super.key, this.product});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          product != null ? 'تعديل المنتج' : 'إضافة منتج ومقاسات جديدة',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: ProductFormView(product: product, isDialog: false),
    );
  }
}

class ProductFormDialog extends StatelessWidget {
  final ProductEntity? product;

  const ProductFormDialog({super.key, this.product});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 780),
        child: ProductFormView(product: product, isDialog: true),
      ),
    );
  }
}

class ProductFormView extends StatelessWidget {
  final ProductEntity? product;
  final bool isDialog;

  const ProductFormView({super.key, this.product, this.isDialog = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<ProductFormCubit>()..init(product),
      child: _ProductFormInternal(product: product, isDialog: isDialog),
    );
  }
}

class _ProductFormInternal extends StatefulWidget {
  final ProductEntity? product;
  final bool isDialog;

  const _ProductFormInternal({this.product, this.isDialog = false});

  @override
  State<_ProductFormInternal> createState() => _ProductFormInternalState();
}

class _VariantRowModel {
  final TextEditingController sizeCtrl;
  final TextEditingController colorCtrl;
  final TextEditingController skuCtrl;
  final TextEditingController costCtrl;
  final TextEditingController sellCtrl;
  final TextEditingController qtyCtrl;

  _VariantRowModel({
    required String size,
    required String color,
    required String sku,
    required String cost,
    required String sell,
    required String qty,
  })  : sizeCtrl = TextEditingController(text: size),
        colorCtrl = TextEditingController(text: color),
        skuCtrl = TextEditingController(text: sku),
        costCtrl = TextEditingController(text: cost),
        sellCtrl = TextEditingController(text: sell),
        qtyCtrl = TextEditingController(text: qty);

  void dispose() {
    sizeCtrl.dispose();
    colorCtrl.dispose();
    skuCtrl.dispose();
    costCtrl.dispose();
    sellCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class _ProductFormInternalState extends State<_ProductFormInternal> {
  final List<_VariantRowModel> _rows = [];
  final TextEditingController _batchCostCtrl = TextEditingController(text: '100');
  final TextEditingController _batchSellCtrl = TextEditingController(text: '150');
  final TextEditingController _batchQtyCtrl = TextEditingController(text: '10');
  String? _validationError;

  @override
  void initState() {
    super.initState();
    if (widget.product == null) {
      _initDefaultRows();
    }
  }

  void _initDefaultRows() {
    _rows.add(_VariantRowModel(size: 'M', color: 'أسود', sku: _makeSku('M', 1), cost: '100', sell: '150', qty: '10'));
    _rows.add(_VariantRowModel(size: 'L', color: 'أسود', sku: _makeSku('L', 2), cost: '100', sell: '150', qty: '10'));
    _rows.add(_VariantRowModel(size: 'XL', color: 'أسود', sku: _makeSku('XL', 3), cost: '100', sell: '150', qty: '10'));
  }

  String _makeSku(String size, int index) {
    final millis = DateTime.now().millisecondsSinceEpoch.toString();
    final suffix = millis.substring(millis.length - 3);
    return 'SKU-$size-$index$suffix';
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _batchCostCtrl.dispose();
    _batchSellCtrl.dispose();
    _batchQtyCtrl.dispose();
    super.dispose();
  }

  void _addRow() {
    setState(() {
      final last = _rows.isNotEmpty ? _rows.last : null;
      final nextIdx = _rows.length + 1;
      _rows.add(_VariantRowModel(
        size: 'L',
        color: last?.colorCtrl.text ?? 'أسود',
        sku: _makeSku('L', nextIdx),
        cost: last?.costCtrl.text ?? '100',
        sell: last?.sellCtrl.text ?? '150',
        qty: last?.qtyCtrl.text ?? '10',
      ));
    });
  }

  void _loadStandardSizes() {
    setState(() {
      for (final r in _rows) {
        r.dispose();
      }
      _rows.clear();
      final sizes = ['S', 'M', 'L', 'XL', 'XXL'];
      final cost = _batchCostCtrl.text.isNotEmpty ? _batchCostCtrl.text : '100';
      final sell = _batchSellCtrl.text.isNotEmpty ? _batchSellCtrl.text : '150';
      final qty = _batchQtyCtrl.text.isNotEmpty ? _batchQtyCtrl.text : '10';

      for (int i = 0; i < sizes.length; i++) {
        _rows.add(_VariantRowModel(
          size: sizes[i],
          color: 'أسود',
          sku: _makeSku(sizes[i], i + 1),
          cost: cost,
          sell: sell,
          qty: qty,
        ));
      }
    });
  }

  void _applyBatchValues() {
    setState(() {
      final cost = _batchCostCtrl.text.trim();
      final sell = _batchSellCtrl.text.trim();
      final qty = _batchQtyCtrl.text.trim();
      for (final r in _rows) {
        if (cost.isNotEmpty) r.costCtrl.text = cost;
        if (sell.isNotEmpty) r.sellCtrl.text = sell;
        if (qty.isNotEmpty) r.qtyCtrl.text = qty;
      }
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  void _handleSubmit(BuildContext context, ProductFormState state) {
    setState(() => _validationError = null);

    if (state.name.trim().isEmpty) {
      setState(() => _validationError = 'يرجى إدخال اسم المنتج');
      return;
    }
    if (state.categoryId == null || state.categoryId!.isEmpty) {
      setState(() => _validationError = 'يرجى اختيار تصنيف للمنتج');
      return;
    }

    if (state.isEdit) {
      context.read<ProductFormCubit>().submit(widget.product?.id);
      return;
    }

    if (_rows.isEmpty) {
      setState(() => _validationError = 'يرجى إضافة سطر واحد على الأقل في جدول المقاسات');
      return;
    }

    final List<VariantInput> variants = [];
    for (int i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final size = r.sizeCtrl.text.trim();
      final color = r.colorCtrl.text.trim();
      final sku = r.skuCtrl.text.trim();
      final costPounds = double.tryParse(r.costCtrl.text.trim()) ?? 0.0;
      final sellPounds = double.tryParse(r.sellCtrl.text.trim()) ?? 0.0;
      final qty = int.tryParse(r.qtyCtrl.text.trim()) ?? 0;

      if (size.isEmpty || color.isEmpty || sku.isEmpty) {
        setState(() => _validationError = 'السطر رقم ${i + 1}: المقاس واللون والكود حقول مطلوبة');
        return;
      }

      variants.add(VariantInput(
        sku: sku,
        color: color,
        size: size,
        costPrice: (costPounds * 100).toInt(),
        sellPrice: (sellPounds * 100).toInt(),
        quantity: qty,
      ));
    }

    context.read<ProductFormCubit>().submitWithVariants(
          id: widget.product?.id,
          variants: variants,
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProductFormCubit, ProductFormState>(
      listener: (context, state) {
        if (state.status == ProductFormStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade800,
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    state.isEdit ? 'تم تحديث بيانات المنتج بنجاح' : 'تم إضافة المنتج وجميع المقاسات والكميات بنجاح',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );
          AppNavigator.pop(context);
        } else if (state.status == ProductFormStatus.error && state.errorMessage != null) {
          setState(() => _validationError = state.errorMessage);
        }
      },
      builder: (context, state) {
        if (state.status == ProductFormStatus.loading && state.categories.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Padding(
          padding: EdgeInsets.all(widget.isDialog ? 20.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dialog Header if dialog
              if (widget.isDialog) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_business_rounded, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.isEdit ? 'تعديل المنتج' : 'إضافة منتج وجدول المقاسات',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                          ),
                          Text(
                            'تسجيل المنتج الجديد والمقاسات والأسعار والأرصدة الأولية دفعة واحدة',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: state.status == ProductFormStatus.loading ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
              ],

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Section 1: Basic Product Information Card
                      Card(
                        elevation: 0.5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'البيانات الأساسية للمنتج',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      initialValue: state.name,
                                      decoration: InputDecoration(
                                        labelText: 'اسم المنتج *',
                                        hintText: 'مثال: بنطلون جينز سليم فيت',
                                        prefixIcon: const Icon(Icons.checkroom),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onChanged: (value) => context.read<ProductFormCubit>().onNameChanged(value),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: state.categoryId,
                                      decoration: InputDecoration(
                                        labelText: 'التصنيف *',
                                        prefixIcon: const Icon(Icons.category),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      items: state.categories.map((category) {
                                        return DropdownMenuItem(
                                          value: category.id,
                                          child: Text(category.name),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          final category = state.categories.firstWhere((c) => c.id == value);
                                          context.read<ProductFormCubit>().onCategoryChanged(category.id, category.name);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                initialValue: state.description,
                                decoration: InputDecoration(
                                  labelText: 'وصف أو ملاحظات (اختياري)',
                                  hintText: 'مثال: خامة قطن 100% تصنيع محلي',
                                  prefixIcon: const Icon(Icons.description_outlined),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onChanged: (value) => context.read<ProductFormCubit>().onDescriptionChanged(value),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Section 2: Variants Table (Only for new products or when adding)
                      if (!state.isEdit) ...[
                        Card(
                          elevation: 0.5,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.table_chart_outlined, color: AppColors.primary, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'جدول المقاسات والألوان والأسعار والكميات',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                          icon: const Icon(Icons.flash_on, size: 16),
                                          label: const Text('مقاسات قياسية (S-XXL)', style: TextStyle(fontSize: 12)),
                                          onPressed: _loadStandardSizes,
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.surfaceContainer,
                                            foregroundColor: AppColors.primary,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                          icon: const Icon(Icons.add, size: 16),
                                          label: const Text('إضافة سطر جديد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          onPressed: _addRow,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Batch Pricing Helper Bar
                                Builder(
                                  builder: (context) {
                                    final authState = context.watch<AuthCubit>().state;
                                    final isCashier = authState is AuthAuthenticated && authState.user.role.toLowerCase() == 'cashier';

                                    return Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceContainer.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.tune, size: 18, color: AppColors.primary),
                                          const SizedBox(width: 8),
                                          const Text('تطبيق موحد:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          const SizedBox(width: 12),
                                          if (!isCashier) ...[
                                            SizedBox(
                                              width: 100,
                                              child: TextField(
                                                controller: _batchCostCtrl,
                                                keyboardType: TextInputType.number,
                                                decoration: const InputDecoration(
                                                  isDense: true,
                                                  labelText: 'التكلفة (ج.م)',
                                                  border: OutlineInputBorder(),
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          SizedBox(
                                            width: 100,
                                            child: TextField(
                                              controller: _batchSellCtrl,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                labelText: 'البيع (ج.م)',
                                                border: OutlineInputBorder(),
                                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 80,
                                            child: TextField(
                                              controller: _batchQtyCtrl,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                labelText: 'الكمية',
                                                border: OutlineInputBorder(),
                                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          TextButton.icon(
                                            icon: const Icon(Icons.done_all, size: 16),
                                            label: const Text('تطبيق على كل المقاسات', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                            onPressed: _applyBatchValues,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),

                                const SizedBox(height: 14),

                                // Table Header
                                Builder(
                                  builder: (context) {
                                    final authState = context.watch<AuthCubit>().state;
                                    final isCashier = authState is AuthAuthenticated && authState.user.role.toLowerCase() == 'cashier';

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          const SizedBox(width: 28, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          const Expanded(flex: 2, child: Text('المقاس (Size)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          const SizedBox(width: 8),
                                          const Expanded(flex: 2, child: Text('اللون (Color)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          const SizedBox(width: 8),
                                          const Expanded(flex: 3, child: Text('كود الصنف / SKU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          if (!isCashier) ...[
                                            const SizedBox(width: 8),
                                            const Expanded(flex: 2, child: Text('التكلفة (ج.م)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          ],
                                          const SizedBox(width: 8),
                                          const Expanded(flex: 2, child: Text('سعر البيع (ج.م)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          const SizedBox(width: 8),
                                          const Expanded(flex: 2, child: Text('الكمية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                          const SizedBox(width: 40),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 6),

                                // Table Rows
                                Builder(
                                  builder: (context) {
                                    final authState = context.watch<AuthCubit>().state;
                                    final isCashier = authState is AuthAuthenticated && authState.user.role.toLowerCase() == 'cashier';

                                    return ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: _rows.length,
                                      separatorBuilder: (_, index) => const SizedBox(height: 8),
                                      itemBuilder: (context, idx) {
                                        final r = _rows[idx];
                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.shade200),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 28,
                                                child: Text('${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: r.sizeCtrl,
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    hintText: 'M / 32',
                                                    border: OutlineInputBorder(),
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: r.colorCtrl,
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    hintText: 'أسود',
                                                    border: OutlineInputBorder(),
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 3,
                                                child: TextFormField(
                                                  controller: r.skuCtrl,
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    hintText: 'الكود / SKU',
                                                    border: OutlineInputBorder(),
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  ),
                                                ),
                                              ),
                                              if (!isCashier) ...[
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  flex: 2,
                                                  child: TextFormField(
                                                    controller: r.costCtrl,
                                                    keyboardType: TextInputType.number,
                                                    decoration: const InputDecoration(
                                                      isDense: true,
                                                      hintText: 'التكلفة',
                                                      border: OutlineInputBorder(),
                                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: r.sellCtrl,
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    hintText: 'البيع',
                                                    border: OutlineInputBorder(),
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: r.qtyCtrl,
                                                  keyboardType: TextInputType.number,
                                                  decoration: const InputDecoration(
                                                    isDense: true,
                                                    hintText: 'الكمية',
                                                    border: OutlineInputBorder(),
                                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                                                tooltip: 'حذف هذا السطر',
                                                onPressed: _rows.length > 1 ? () => _removeRow(idx) : null,
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      if (_validationError != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _validationError!,
                                  style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: state.status == ProductFormStatus.loading ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: state.status == ProductFormStatus.loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 20),
                    label: Text(
                      state.status == ProductFormStatus.loading
                          ? 'جاري الحفظ...'
                          : (state.isEdit ? 'تحديث المنتج' : 'حفظ المنتج وجدول المقاسات'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: state.status == ProductFormStatus.loading ? null : () => _handleSubmit(context, state),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
