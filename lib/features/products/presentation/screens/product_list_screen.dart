import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/excel_service.dart';
import '../../../product_variants/presentation/screens/variant_list_screen.dart';
import '../../domain/entities/product_entity.dart';
import '../cubits/product_cubit.dart';
import '../cubits/product_state.dart';
import 'product_form_screen.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => getIt<ProductCubit>()..getProducts(),
      child: const _ProductListView(),
    );
  }
}

class _ProductListView extends StatefulWidget {
  const _ProductListView();

  @override
  State<_ProductListView> createState() => _ProductListViewState();
}

class _ProductListViewState extends State<_ProductListView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openAddProductDialog(BuildContext context, [ProductEntity? product]) async {
    final cubit = context.read<ProductCubit>();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductFormDialog(product: product),
    );
    if (context.mounted) {
      cubit.getProducts();
    }
  }

  Future<void> _confirmDelete(BuildContext context, ProductEntity product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('تأكيد حذف المنتج', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف المنتج "${product.name}"؟ لا يمكن التراجع عن هذه العملية.'),
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
      context.read<ProductCubit>().deleteProduct(product.id);
    }
  }

  Future<void> _exportToExcel(BuildContext context) async {
    try {
      await ExcelService().exportProducts();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('تم تصدير قائمة المنتجات بنجاح'),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('فشل التصدير: $e'),
          ),
        );
      }
    }
  }

  Color _getCategoryColor(String category) {
    if (category.isEmpty) return AppColors.primary;
    final hash = category.codeUnits.fold(0, (prev, elem) => prev + elem);
    const palette = [
      Color(0xFF340588),
      Color(0xFF1E88E5),
      Color(0xFF00897B),
      Color(0xFFD81B60),
      Color(0xFFFB8C00),
      Color(0xFF8E24AA),
      Color(0xFF3949AB),
      Color(0xFF00ACC1),
    ];
    return palette[hash % palette.length];
  }

  List<ProductEntity> _filterProducts(List<ProductEntity> products) {
    return products.where((p) {
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        if (p.categoryName != _selectedCategory) return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final name = p.name.toLowerCase();
        final cat = p.categoryName.toLowerCase();
        final desc = p.description.toLowerCase();
        if (!name.contains(q) && !cat.contains(q) && !desc.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'دليل المنتجات',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.onSurface),
            ),
            Text(
              'إدارة وتعديل المنتجات والمقاسات وجداول الأسعار',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: AppColors.primary),
            tooltip: 'تصدير إكسيل',
            onPressed: () => _exportToExcel(context),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
              label: const Text(
                'إضافة منتج جديد',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _openAddProductDialog(context),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: BlocBuilder<ProductCubit, ProductState>(
        builder: (context, state) {
          if (state is ProductLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is ProductError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text('حدث خطأ: ${state.message}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.read<ProductCubit>().getProducts(),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          } else if (state is ProductLoaded) {
            final allProducts = state.products;
            final categories = allProducts
                .map((p) => p.categoryName)
                .where((c) => c.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

            final filtered = _filterProducts(allProducts);

            return Column(
              children: [
                // Search & Filter Header
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (val) => setState(() => _searchQuery = val),
                              decoration: InputDecoration(
                                hintText: 'ابحث باسم المنتج، الوصف، أو التصنيف...',
                                prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 18),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                filled: true,
                                fillColor: AppColors.surfaceContainer,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'العدد: ${filtered.length}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (categories.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: ChoiceChip(
                                  label: const Text('جميع التصنيفات'),
                                  selected: _selectedCategory == null,
                                  onSelected: (sel) {
                                    if (sel) setState(() => _selectedCategory = null);
                                  },
                                  selectedColor: AppColors.primary,
                                  labelStyle: TextStyle(
                                    color: _selectedCategory == null ? Colors.white : AppColors.onSurface,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              ...categories.map((cat) {
                                final isSel = _selectedCategory == cat;
                                return Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: ChoiceChip(
                                    label: Text(cat),
                                    selected: isSel,
                                    onSelected: (sel) {
                                      setState(() => _selectedCategory = sel ? cat : null);
                                    },
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: isSel ? Colors.white : AppColors.onSurface,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Content Area
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery.isNotEmpty || _selectedCategory != null
                                    ? 'لا توجد منتجات تطابق البحث الحالي'
                                    : 'لا توجد منتجات مسجلة في النظام بعد',
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add, color: Colors.white),
                                label: const Text('إضافة منتج جديد الآن', style: TextStyle(color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => _openAddProductDialog(context),
                              ),
                            ],
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth > 750) {
                              return GridView.builder(
                                padding: const EdgeInsets.all(16),
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 460,
                                  mainAxisExtent: 160,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  return _buildProductCard(context, filtered[index]);
                                },
                              );
                            }
                            return ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              separatorBuilder: (_, index) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                return _buildProductCard(context, filtered[index]);
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          } else if (state is ProductEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'لا توجد منتجات مضافة حتى الآن',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ابدأ بإضافة أول منتج مع مقاساته وألوانه وجدول الأسعار',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('إضافة منتج جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _openAddProductDialog(context),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _openAddProductDialog(context),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'إضافة منتج',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, ProductEntity product) {
    final catColor = _getCategoryColor(product.categoryName);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  product.name.isNotEmpty ? product.name.characters.first : 'م',
                  style: TextStyle(
                    color: catColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            product.categoryName.isNotEmpty ? product.categoryName : 'بدون تصنيف',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: catColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: product.isActive ? Colors.green.shade50 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: product.isActive ? Colors.green.shade300 : Colors.grey.shade400,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            product.isActive ? 'نشط' : 'معطل',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: product.isActive ? Colors.green.shade800 : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                tooltip: 'حذف المنتج',
                onPressed: () => _confirmDelete(context, product),
              ),
            ],
          ),
          if (product.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              product.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
          const Spacer(),
          const Divider(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.style_outlined, size: 15),
                label: const Text('المقاسات والألوان', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => VariantListScreen(product: product)),
                  );
                  if (context.mounted) {
                    context.read<ProductCubit>().getProducts();
                  }
                },
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('تعديل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                onPressed: () => _openAddProductDialog(context, product),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
