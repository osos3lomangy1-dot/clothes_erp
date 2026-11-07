import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/excel_service.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../categories/domain/entities/category_entity.dart';
import '../../../categories/presentation/cubits/category_cubit.dart';
import '../../../categories/presentation/cubits/category_state.dart';
import '../../../categories/presentation/screens/category_form_screen.dart';
import '../../../product_variants/presentation/screens/variant_list_screen.dart';
import '../../domain/entities/product_entity.dart';
import '../cubits/product_cubit.dart';
import '../cubits/product_state.dart';
import 'product_form_screen.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => getIt<ProductCubit>()..getProducts()),
        BlocProvider(create: (_) => getIt<CategoryCubit>()..getCategories()),
      ],
      child: const _ProductsAndCategoriesView(),
    );
  }
}

class _ProductsAndCategoriesView extends StatefulWidget {
  const _ProductsAndCategoriesView();

  @override
  State<_ProductsAndCategoriesView> createState() => _ProductsAndCategoriesViewState();
}

class _ProductsAndCategoriesViewState extends State<_ProductsAndCategoriesView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategoryId;
  String? _selectedCategoryName;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openAddCategoryDialog(BuildContext context, [CategoryEntity? category]) async {
    final catCubit = context.read<CategoryCubit>();
    final prodCubit = context.read<ProductCubit>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CategoryFormDialog(category: category),
    );

    if (context.mounted) {
      catCubit.getCategories();
      prodCubit.getProducts();
    }
  }

  Future<void> _confirmDeleteCategory(BuildContext context, CategoryEntity category) async {
    final catCubit = context.read<CategoryCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('تأكيد حذف القسم', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text('هل أنت متأكد من حذف قسم "${category.name}"؟'),
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
      await catCubit.deleteCategory(category.id);
      if (_selectedCategoryId == category.id || _selectedCategoryName == category.name) {
        setState(() {
          _selectedCategoryId = null;
          _selectedCategoryName = null;
        });
      }
    }
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

  Future<void> _confirmDeleteProduct(BuildContext context, ProductEntity product) async {
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
                Text('تم تصدير قائمة المنتجات بنجاح إلى ملف إكسيل'),
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

  Future<void> _importFromExcel(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر قراءة ملف الإكسيل المحدد'), backgroundColor: AppColors.error),
        );
      }
      return;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );

    ExcelImportAnalysis analysis;
    try {
      analysis = await ExcelService().analyzeExcel(bytes);
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تحليل ملف الإكسيل: $e'), backgroundColor: AppColors.error),
        );
      }
      return;
    }

    if (context.mounted) {
      Navigator.pop(context);
    }

    if (analysis.totalRows == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الملف لا يحتوي على أي صفوف منتجات صالحة للتحميل')),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ExcelImportOptionsDialog(analysis: analysis),
    );

    if (proceed == true && context.mounted) {
      context.read<ProductCubit>().getProducts();
      context.read<CategoryCubit>().getCategories();
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
      if (_selectedCategoryId != null && _selectedCategoryId!.isNotEmpty) {
        final matchesId = p.categoryId == _selectedCategoryId;
        final matchesName = p.categoryName == _selectedCategoryName;
        if (!matchesId && !matchesName) return false;
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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'دليل المنتجات والتصنيفات',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
            ),
            Text(
              'إدارة الأقسام والأصناف والمقاسات وجداول الأسعار في مكان واحد',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: AppColors.primary),
            tooltip: 'تصدير إكسيل',
            onPressed: () => _exportToExcel(context),
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_rounded, color: AppColors.primary),
            tooltip: 'استيراد من إكسيل',
            onPressed: () => _importFromExcel(context),
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
        builder: (context, prodState) {
          final allProducts = prodState is ProductLoaded ? prodState.products : <ProductEntity>[];

          return BlocBuilder<CategoryCubit, CategoryState>(
            builder: (context, catState) {
              final categories = catState is CategoryLoaded ? catState.categories : <CategoryEntity>[];

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isWideScreen = constraints.maxWidth >= 850;

                  if (isWideScreen) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Right Side Panel: Categories
                        SizedBox(
                          width: 280,
                          child: _buildCategoriesPanel(context, categories, allProducts),
                        ),
                        const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFE8DEF8)),
                        // Main Left Area: Products
                        Expanded(
                          child: _buildProductsArea(context, prodState, allProducts),
                        ),
                      ],
                    );
                  }

                  // Fallback for smaller screens: Top chips + Products
                  return Column(
                    children: [
                      _buildTopCategoriesBar(context, categories, allProducts),
                      const Divider(height: 1),
                      Expanded(
                        child: _buildProductsArea(context, prodState, allProducts),
                      ),
                    ],
                  );
                },
              );
            },
          );
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

  // Categories Sidebar for desktop
  Widget _buildCategoriesPanel(
    BuildContext context,
    List<CategoryEntity> categories,
    List<ProductEntity> allProducts,
  ) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF2EAFF))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.category_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'أقسام المتجر',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.onSurface),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${categories.length}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _openAddCategoryDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('قسم جديد', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              children: [
                // "All Products" Tile
                _buildCategoryTile(
                  title: 'جميع المنتجات',
                  count: allProducts.length,
                  isSelected: _selectedCategoryId == null,
                  icon: Icons.grid_view_rounded,
                  color: AppColors.primary,
                  onTap: () {
                    setState(() {
                      _selectedCategoryId = null;
                      _selectedCategoryName = null;
                    });
                  },
                ),
                const SizedBox(height: 4),
                // Categories Tiles
                ...categories.map((cat) {
                  final isSelected = _selectedCategoryId == cat.id || _selectedCategoryName == cat.name;
                  final catCount = allProducts.where((p) => p.categoryId == cat.id || p.categoryName == cat.name).length;
                  final catColor = _getCategoryColor(cat.name);

                  return _buildCategoryTile(
                    title: cat.name,
                    count: catCount,
                    isSelected: isSelected,
                    icon: Icons.checkroom_rounded,
                    color: catColor,
                    onTap: () {
                      setState(() {
                        _selectedCategoryId = cat.id;
                        _selectedCategoryName = cat.name;
                      });
                    },
                    onEdit: () => _openAddCategoryDialog(context, cat),
                    onDelete: () => _confirmDeleteCategory(context, cat),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile({
    required String title,
    required int count,
    required bool isSelected,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.surfaceContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.3) : Colors.transparent,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        onTap: onTap,
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isSelected ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: 13,
            color: isSelected ? AppColors.primary : AppColors.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 16, color: Colors.grey.shade500),
                padding: EdgeInsets.zero,
                tooltip: 'خيارات القسم',
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'delete' && onDelete != null) onDelete();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text('تعديل القسم'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('حذف القسم', style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Top Bar for smaller screens
  Widget _buildTopCategoriesBar(
    BuildContext context,
    List<CategoryEntity> categories,
    List<ProductEntity> allProducts,
  ) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              label: Text('جميع المنتجات (${allProducts.length})'),
              selected: _selectedCategoryId == null,
              onSelected: (sel) {
                if (sel) {
                  setState(() {
                    _selectedCategoryId = null;
                    _selectedCategoryName = null;
                  });
                }
              },
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: _selectedCategoryId == null ? Colors.white : AppColors.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          ...categories.map((cat) {
            final isSel = _selectedCategoryId == cat.id || _selectedCategoryName == cat.name;
            final catCount = allProducts.where((p) => p.categoryId == cat.id || p.categoryName == cat.name).length;

            return Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                label: Text('${cat.name} ($catCount)'),
                selected: isSel,
                onSelected: (sel) {
                  setState(() {
                    _selectedCategoryId = sel ? cat.id : null;
                    _selectedCategoryName = sel ? cat.name : null;
                  });
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
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 16, color: AppColors.primary),
              label: const Text('قسم جديد'),
              onPressed: () => _openAddCategoryDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  // Products Area (Search + Cards)
  Widget _buildProductsArea(
    BuildContext context,
    ProductState state,
    List<ProductEntity> allProducts,
  ) {
    if (state is ProductLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is ProductError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
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
    }

    final filtered = _filterProducts(allProducts);

    return Column(
      children: [
        // Search & Filter Sub-header
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: _selectedCategoryName != null
                        ? 'البحث داخل قسم "$_selectedCategoryName"...'
                        : 'ابحث باسم المنتج، الوصف، أو الكود...',
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
                      'المعروض: ${filtered.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Product Cards
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isNotEmpty || _selectedCategoryId != null
                            ? 'لا توجد منتجات مطابقة في هذا القسم'
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
                    if (constraints.maxWidth > 650) {
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
                onPressed: () => _confirmDeleteProduct(context, product),
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

class _ExcelImportOptionsDialog extends StatefulWidget {
  final ExcelImportAnalysis analysis;

  const _ExcelImportOptionsDialog({required this.analysis});

  @override
  State<_ExcelImportOptionsDialog> createState() => _ExcelImportOptionsDialogState();
}

class _ExcelImportOptionsDialogState extends State<_ExcelImportOptionsDialog> {
  bool _replaceExisting = false;
  bool _isImporting = false;

  void _applyToAll(DuplicateResolution res) {
    setState(() {
      for (final c in widget.analysis.conflicts) {
        c.resolution = res;
      }
    });
  }

  Future<void> _startImport() async {
    setState(() => _isImporting = true);

    String userId = 'admin';
    try {
      final auth = context.read<AuthCubit>().state;
      if (auth is AuthAuthenticated) userId = auth.user.name;
    } catch (_) {}

    try {
      await ExcelService().executeImport(
        newRows: widget.analysis.newRows,
        conflicts: widget.analysis.conflicts,
        replaceExisting: _replaceExisting,
        userId: userId,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'تم استيراد ${widget.analysis.newRows.length} صنف جديد وتحديث ${widget.analysis.conflicts.where((c) => c.resolution != DuplicateResolution.skip).length} صنف بنجاح',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الاستيراد: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = widget.analysis.conflicts;
    final newRows = widget.analysis.newRows;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.upload_file_rounded, color: AppColors.primary, size: 26),
                      SizedBox(width: 10),
                      Text(
                        'خيارات استيراد ملف الإكسيل وفحص التكرار',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.onSurface),
                      ),
                    ],
                  ),
                  if (!_isImporting)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                ],
              ),
              const Divider(height: 20),

              // Summary Badges
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.add_circle_outline_rounded, color: Colors.green.shade800),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('أصناف جديدة بالكامل', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Text('${newRows.length} صنف جاهز للإضافة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green.shade900)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: conflicts.isNotEmpty ? Colors.amber.shade50 : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: conflicts.isNotEmpty ? Colors.amber.shade300 : Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: conflicts.isNotEmpty ? Colors.amber.shade900 : Colors.grey),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('أصناف مكررة الكود (SKU)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              Text('${conflicts.length} أصناف موجودة مسبقاً', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: conflicts.isNotEmpty ? Colors.amber.shade900 : Colors.grey.shade700)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Import Mode Options
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('طريقة الاستيراد:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _isImporting ? null : () => setState(() => _replaceExisting = false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                        child: Row(
                          children: [
                            Icon(
                              !_replaceExisting ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              color: !_replaceExisting ? AppColors.primary : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('إضافة وتحديث على البيانات الحالية (دمج الأرصدة والأسعار - موصى به)', style: TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _isImporting ? null : () => setState(() => _replaceExisting = true),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                        child: Row(
                          children: [
                            Icon(
                              _replaceExisting ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              color: _replaceExisting ? AppColors.primary : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('استبدال كافة الأصناف غير المباعة الموجودة في النظام بملف الإكسيل', style: TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Conflicts Section
              if (conflicts.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'معالجة الأصناف المكررة:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _isImporting ? null : () => _applyToAll(DuplicateResolution.updatePricesAndQty),
                      child: const Text('تحديث السعر والرصيد للكل', style: TextStyle(fontSize: 11)),
                    ),
                    TextButton(
                      onPressed: _isImporting ? null : () => _applyToAll(DuplicateResolution.addQuantity),
                      child: const Text('إضافة الكمية فوق الرصيد للكل', style: TextStyle(fontSize: 11)),
                    ),
                    TextButton(
                      onPressed: _isImporting ? null : () => _applyToAll(DuplicateResolution.skip),
                      child: const Text('تخطي الكل', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: conflicts.length,
                      separatorBuilder: (_, index) => const Divider(height: 12),
                      itemBuilder: (context, index) {
                        final conflict = conflicts[index];
                        final row = conflict.excelRow;
                        final existing = conflict.existingVariant;

                        return Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${conflict.existingProductName} (${row.sku})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    'المقاس: ${row.size} | اللون: ${row.color}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'الحالي: رصيد ${existing.quantity} | بيع ${(existing.sellPrice / 100).toStringAsFixed(1)} ج.م',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                  ),
                                  Text(
                                    'الإكسيل: كمية ${row.quantity} | بيع ${row.salePrice.toStringAsFixed(1)} ج.م',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ),
                            DropdownButton<DuplicateResolution>(
                              value: conflict.resolution,
                              isDense: true,
                              style: const TextStyle(fontSize: 12, color: AppColors.onSurface),
                              items: const [
                                DropdownMenuItem(
                                  value: DuplicateResolution.updatePricesAndQty,
                                  child: Text('تحديث السعر والرصيد'),
                                ),
                                DropdownMenuItem(
                                  value: DuplicateResolution.addQuantity,
                                  child: Text('إضافة الكمية فوق الرصيد'),
                                ),
                                DropdownMenuItem(
                                  value: DuplicateResolution.skip,
                                  child: Text('تخطي الصنف الحالي'),
                                ),
                              ],
                              onChanged: _isImporting
                                  ? null
                                  : (val) {
                                      if (val != null) {
                                        setState(() => conflict.resolution = val);
                                      }
                                    },
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ] else
                const Spacer(),

              const SizedBox(height: 16),
              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isImporting ? null : () => Navigator.pop(context, false),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isImporting ? null : _startImport,
                    child: _isImporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'بدء الاستيراد وتحديث المخزن',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
