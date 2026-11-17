import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../../categories/domain/repositories/category_repository.dart';
import '../../../products/data/datasources/product_local_data_source.dart';
import '../../domain/entities/promotion.dart';
import '../cubits/promotions_cubit.dart';
import '../widgets/promotion_form_dialog.dart';

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
  Map<String, String> _productNames = const {};
  Map<String, String> _categoryNames = const {};

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
    _loadTargetNames();
  }

  Future<void> _loadTargetNames() async {
    final prodNames = <String, String>{};
    final catNames = <String, String>{};

    try {
      if (getIt.isRegistered<ProductLocalDataSource>()) {
        final products =
            await getIt<ProductLocalDataSource>().getProductsWithVariants();
        for (final pwv in products) {
          prodNames[pwv.product.id] = pwv.product.name;
          for (final v in pwv.variants) {
            prodNames[v.id] = '${pwv.product.name} (${v.color} - ${v.size})';
          }
        }
      }
    } catch (_) {}

    try {
      if (getIt.isRegistered<CategoryRepository>()) {
        final catsRes = await getIt<CategoryRepository>().getCategories();
        catsRes.fold((_) {}, (cats) {
          for (final c in cats) {
            catNames[c.id] = c.name;
          }
        });
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _productNames = prodNames;
        _categoryNames = catNames;
      });
    }
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
                      productNames: _productNames,
                      categoryNames: _categoryNames,
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
      selectedColor: AppColors.primary.withValues(alpha: 0.14),
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
  final Map<String, String> productNames;
  final Map<String, String> categoryNames;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  const _PromotionCard({
    required this.promotion,
    this.productNames = const {},
    this.categoryNames = const {},
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  String _formatTargetNames(List<String> ids, Map<String, String> lookup) {
    if (ids.isEmpty) return '';
    final names = ids.map((id) => lookup[id] ?? id).toList();
    if (names.length <= 3) {
      return names.join('، ');
    }
    return '${names.take(3).join('، ')} (+${names.length - 3} آخرين)';
  }

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

    final effectiveTargetIds = promotion.targetIds.isNotEmpty
        ? promotion.targetIds
        : (promotion.targetId != null && promotion.targetId!.isNotEmpty
            ? [promotion.targetId!]
            : const <String>[]);

    String scopeDisplay = 'كل المنتجات';
    if (promotion.scope == 'product') {
      final resolved = _formatTargetNames(effectiveTargetIds, productNames);
      scopeDisplay = resolved.isNotEmpty ? 'منتج محدد: $resolved' : 'منتج محدد';
    } else if (promotion.scope == 'category') {
      final resolved = _formatTargetNames(effectiveTargetIds, categoryNames);
      scopeDisplay = resolved.isNotEmpty ? 'قسم محدد: $resolved' : 'قسم محدد';
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

