import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:clothes_erp/core/constants/app_colors.dart';
import 'package:clothes_erp/core/di/injection.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/products/domain/services/culinary_starter_pack_engine.dart';
import 'package:clothes_erp/features/products/presentation/cubits/product_cubit.dart';

class CulinaryStarterPackDialog extends StatefulWidget {
  const CulinaryStarterPackDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CulinaryStarterPackDialog(),
    );
  }

  @override
  State<CulinaryStarterPackDialog> createState() => _CulinaryStarterPackDialogState();
}

class _CulinaryStarterPackDialogState extends State<CulinaryStarterPackDialog> {
  CulinaryStarterPackType _selectedPack = CulinaryStarterPackType.burgerDiner;
  bool _isInstalling = false;
  String? _statusMessage;

  Future<void> _handleInstall() async {
    setState(() {
      _isInstalling = true;
      _statusMessage = 'جارِ تثبيت الباقة وتجهيز الخامات والوجبات...';
    });

    try {
      final prodRepo = getIt<ProductRepository>();
      final catRepo = getIt<CategoryRepository>();

      final result = await CulinaryStarterPackEngine.seedStarterPack(
        packType: _selectedPack,
        productRepository: prodRepo,
        categoryRepository: catRepo,
        skipIfExists: true,
      );

      if (!mounted) return;

      setState(() {
        _isInstalling = false;
      });

      try {
        context.read<ProductCubit>().getProducts();
      } catch (_) {}

      // Show brief success toast then pop
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تثبيت ${CulinaryStarterPackEngine.getPackTitle(_selectedPack)} بنجاح: '
            'تمت إضافة ${result.rawMaterialsCreated} خامات و ${result.mealsCreated} وجبات ومشروبات.',
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _statusMessage = 'فشل تثبيت الباقة: $e';
        });
      }
    }
  }

  Widget _buildPackOptionCard({
    required CulinaryStarterPackType type,
    required IconData icon,
    required String title,
    required String subtitle,
    required String countsLabel,
  }) {
    final isSelected = _selectedPack == type;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isInstalling ? null : () => setState(() => _selectedPack = type),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primary : Colors.grey.shade700,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? AppColors.primary : AppColors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          countsLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? AppColors.primary : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.bolt_rounded,
                      color: AppColors.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'باقات المنيو والخامات الجاهزة بنقرة واحدة',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'اختر باقة تشغيل متكاملة لتحميل خاماتها ومقاديرها (BOM) وأسعارها فوراً',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _isInstalling ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 18),

              // 3 Starter Pack Cards
              _buildPackOptionCard(
                type: CulinaryStarterPackType.burgerDiner,
                icon: Icons.lunch_dining_rounded,
                title: 'باقة برجر داينر (Burger Diner)',
                subtitle: 'لحم بقري، بريوش، شيدر أحمر، صوصات، بطاطس نصف مقلية، زيت وقلي، علب برجر وورق بطاطس مع 3 وجبات.',
                countsLabel: '8 خامات | 3 وجبات',
              ),

              const SizedBox(height: 12),

              _buildPackOptionCard(
                type: CulinaryStarterPackType.specialtyCafe,
                icon: Icons.coffee_rounded,
                title: 'باقة مقهى ومشروبات مختصة (Specialty Cafe)',
                subtitle: 'بن كولومبي مختص، حليب كامل الدسم، سيرب فانيليا، ماتشا ياباني، أكواب دبل 12 أونص مع 4 مشروبات.',
                countsLabel: '5 خامات | 4 مشروبات',
              ),

              const SizedBox(height: 12),

              _buildPackOptionCard(
                type: CulinaryStarterPackType.pizzeriaAndPasta,
                icon: Icons.local_pizza_rounded,
                title: 'باقة بيتزا نابوليتانو وباستا (Pizzeria & Pasta)',
                subtitle: 'دقيق Tipo 00، جبن موزاريلا، سان مارزانو، زيت زيتون، مكرونة بيني، كريمة طهي، علب 30 سم مع بيتزا ومكرونة.',
                countsLabel: '7 خامات | 2 أطباق',
              ),

              const SizedBox(height: 18),

              // Status message or progress
              if (_statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _isInstalling
                        ? AppColors.primary.withValues(alpha: 0.08)
                        : AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (_isInstalling) ...[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isInstalling ? AppColors.primary : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Footer Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'ملاحظة: لن يتم تكرار الأصناف الموجودة مسبقاً بنظامك.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _isInstalling ? null : () => Navigator.of(context).pop(false),
                        child: const Text('إلغاء'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        key: const Key('install_starter_pack_btn'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isInstalling ? null : _handleInstall,
                        icon: _isInstalling
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                        label: Text(
                          _isInstalling ? 'جارِ التثبيت...' : 'استعراض وتثبيت الباقة الآن',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
