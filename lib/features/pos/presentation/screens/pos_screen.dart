import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../customers/domain/entities/customer_entity.dart';
import '../../../customers/domain/repositories/customer_repository.dart';
import '../../../product_variants/domain/entities/variant_entity.dart';
import '../../domain/entities/sale_item_entity.dart';
import '../cubits/pos_cubit.dart';
import '../../../shifts/presentation/cubits/shift_cubit.dart';
import '../../../shifts/presentation/cubits/shift_state.dart';
import '../../../shifts/presentation/widgets/open_shift_dialog.dart';
import '../../../shifts/presentation/screens/shift_screen.dart';
import '../../../invoices/domain/entities/invoice_details_entity.dart';
import '../../../invoices/domain/repositories/invoices_repository.dart';
import '../../../invoices/presentation/widgets/sale_success_dialog.dart';

Color _getCategoryColor(String? categoryId) {
  if (categoryId == null || categoryId.isEmpty) return const Color(0xFF673AB7);
  final palette = [
    const Color(0xFF5E35B1), // Deep Purple
    const Color(0xFF1E88E5), // Blue
    const Color(0xFF00897B), // Teal
    const Color(0xFF43A047), // Green
    const Color(0xFFFB8C00), // Orange
    const Color(0xFFD81B60), // Pink
    const Color(0xFF8E24AA), // Purple
    const Color(0xFF3949AB), // Indigo
    const Color(0xFF00ACC1), // Cyan
    const Color(0xFFE64A19), // Deep Orange
  ];
  final hash = categoryId.codeUnits.fold(0, (acc, c) => acc + c);
  return palette[hash % palette.length];
}

Color _mapColorNameToColor(String name) {
  final n = name.trim().toLowerCase();
  if (n.contains('red') || n.contains('أحمر')) return Colors.red.shade600;
  if (n.contains('blue') || n.contains('أزرق')) return Colors.blue.shade600;
  if (n.contains('green') || n.contains('أخضر')) return Colors.green.shade600;
  if (n.contains('black') || n.contains('أسود')) return Colors.black87;
  if (n.contains('white') || n.contains('أبيض')) return Colors.white;
  if (n.contains('yellow') || n.contains('أصفر')) return Colors.amber.shade700;
  if (n.contains('purple') || n.contains('بنفسجي')) return Colors.purple.shade600;
  if (n.contains('grey') || n.contains('gray') || n.contains('رمادي')) return Colors.grey.shade600;
  if (n.contains('navy') || n.contains('كحلي')) return const Color(0xFF0D47A1);
  if (n.contains('brown') || n.contains('بني')) return Colors.brown.shade600;
  if (n.contains('pink') || n.contains('وردي')) return Colors.pink.shade400;
  if (n.contains('orange') || n.contains('برتقالي')) return Colors.orange.shade700;
  return AppColors.primary;
}

class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => getIt<PosCubit>()..init()),
        BlocProvider(create: (context) => getIt<ShiftCubit>()..loadShiftData()),
      ],
      child: const _PosView(),
    );
  }
}

class _PosView extends StatefulWidget {
  const _PosView();

  @override
  State<_PosView> createState() => _PosViewState();
}

class _PosViewState extends State<_PosView> {
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildContent(context);
    } catch (e, st) {
      return Scaffold(
        appBar: AppBar(title: const Text('POS Error')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText('PosView error:\n$e\n\n$st',
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    return BlocBuilder<ShiftCubit, ShiftState>(
      builder: (context, shiftState) {
        final authState = context.watch<AuthCubit>().state;
        final isAdmin = authState is! AuthAuthenticated || authState.user.role == 'admin';
        final cashierId = authState is AuthAuthenticated ? authState.user.id : 'admin';
        final cashierName = authState is AuthAuthenticated ? authState.user.name : 'المدير';

        if (shiftState.status == ShiftStatus.loading && !shiftState.hasActiveShift) {
          return const Scaffold(
            backgroundColor: AppColors.surface,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (shiftState.shiftsEnabled && !shiftState.hasActiveShift) {
          return _buildShiftRequiredScaffold(
            context,
            isAdmin: isAdmin,
            cashierId: cashierId,
            cashierName: cashierName,
            shiftState: shiftState,
          );
        }

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f2): () => _searchFocusNode.requestFocus(),
            const SingleActivator(LogicalKeyboardKey.escape): () => context.read<PosCubit>().clearCart(),
          },
          child: Scaffold(
            backgroundColor: AppColors.surface,
            appBar: AppBar(
              elevation: 0,
              backgroundColor: AppColors.primary,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'نقطة البيع (POS)',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              actions: [
                if (shiftState.shiftsEnabled && shiftState.activeShift != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ShiftScreen()),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.greenAccent),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_open_rounded, color: Colors.greenAccent, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'وردية مفتوحة',
                              style: GoogleFonts.cairo(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Cashier Badge
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(
                    child: BlocBuilder<AuthCubit, AuthState>(
                      builder: (context, authState) {
                        final cashierName = authState is AuthAuthenticated
                            ? authState.user.name
                            : 'كاشير';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_rounded, size: 16, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                cashierName,
                                style: GoogleFonts.cairo(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            body: Row(
              children: [
                // Right Panel in RTL: Products Catalog
                Expanded(
                  child: Builder(
                    builder: (ctx) {
                      try {
                        return _ProductPanel(searchFocusNode: _searchFocusNode);
                      } catch (e, st) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Text('ProductPanel error: $e\n$st', style: const TextStyle(color: Colors.red, fontSize: 12)),
                        );
                      }
                    },
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1, color: AppColors.outlineVariant),
                // Left Panel in RTL: Cart (Fixed 440px)
                SizedBox(
                  width: 440,
                  child: Builder(
                    builder: (ctx) {
                      try {
                        return const _CartPanel();
                      } catch (e, st) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Text('CartPanel error: $e\n$st', style: const TextStyle(color: Colors.red, fontSize: 12)),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShiftRequiredScaffold(
    BuildContext context, {
    required bool isAdmin,
    required String cashierId,
    required String cashierName,
    required ShiftState shiftState,
  }) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'نقطة البيع (POS)',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 550),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isAdmin ? Colors.blue.shade50 : Colors.red.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isAdmin ? Icons.storefront_rounded : Icons.lock_clock_rounded,
                        size: 48,
                        color: isAdmin ? AppColors.primary : Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isAdmin ? 'تنبيه: لا توجد وردية مفتوحة' : 'الوردية مغلقة - الرجاء فتح وردية',
                      style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isAdmin
                          ? 'أهلاً بك يا مدير! يمكنك فتح وردية فورية بضغطة زر لبدء البيع السريع، أو فتح وردية جديدة وتحديد رصيد الفكة.'
                          : 'لا يمكنك إصدار فواتير بيع في نقطة البيع قبل فتح وردية وتحديد عهدة الفكة في الدرج.',
                      style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey.shade600, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (isAdmin) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: shiftState.isOperating
                              ? null
                              : () async {
                                  final cubit = context.read<ShiftCubit>();
                                  final ok = await cubit.openShift(
                                    openingBalance: 0,
                                    cashierId: cashierId,
                                    cashierName: cashierName,
                                  );
                                  if (!ok && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(cubit.state.errorMessage ?? 'تعذر بدء الوردية السريعة'),
                                        backgroundColor: AppColors.error,
                                      ),
                                    );
                                  }
                                },
                          icon: shiftState.isOperating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.flash_on_rounded, color: Colors.white, size: 22),
                          label: Text(
                            'بدء البيع السريع فوراً (فكة 0 ج.م)',
                            style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            side: const BorderSide(color: AppColors.primary, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => OpenShiftDialog(
                                cashierName: cashierName,
                                onOpen: (openingPiasters) async {
                                  final cubit = context.read<ShiftCubit>();
                                  final ok = await cubit.openShift(
                                    openingBalance: openingPiasters,
                                    cashierId: cashierId,
                                    cashierName: cashierName,
                                  );
                                  if (!ok) {
                                    return cubit.state.errorMessage ?? 'تعذر بدء الوردية. يرجى المحاولة مرة أخرى.';
                                  }
                                  return null;
                                },
                              ),
                            );
                          },
                          icon: const Icon(Icons.lock_open_rounded, color: AppColors.primary, size: 20),
                          label: Text(
                            'فتح وردية وتحديد رصيد الفكة',
                            style: GoogleFonts.cairo(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => OpenShiftDialog(
                                cashierName: cashierName,
                                onOpen: (openingPiasters) async {
                                  final cubit = context.read<ShiftCubit>();
                                  final ok = await cubit.openShift(
                                    openingBalance: openingPiasters,
                                    cashierId: cashierId,
                                    cashierName: cashierName,
                                  );
                                  if (!ok) {
                                    return cubit.state.errorMessage ?? 'تعذر بدء الوردية. يرجى المحاولة مرة أخرى.';
                                  }
                                  return null;
                                },
                              ),
                            );
                          },
                          icon: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
                          label: Text(
                            'فتح وردية جديدة',
                            style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// RIGHT PANEL: PRODUCTS
// ---------------------------------------------------------------------------
class _ProductPanel extends StatefulWidget {
  final FocusNode searchFocusNode;
  const _ProductPanel({required this.searchFocusNode});

  @override
  State<_ProductPanel> createState() => _ProductPanelState();
}

class _ProductPanelState extends State<_ProductPanel> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildContent(context);
    } catch (e, st) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text('ProductPanel build error:\n$e\n$st',
            style: const TextStyle(color: Colors.red, fontSize: 11)),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      children: [
        // Search Bar: clean search input with F2 shortcut
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              focusNode: widget.searchFocusNode,
              style: GoogleFonts.cairo(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو كود الصنف أو المقاس... [F2]',
                hintStyle: GoogleFonts.cairo(color: Colors.grey.shade500, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          context.read<PosCubit>().searchProducts('');
                          setState(() {});
                        },
                      ),
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Text(
                        'F2',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (val) {
                context.read<PosCubit>().searchProducts(val);
                setState(() {});
              },
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  final added = context.read<PosCubit>().addByBarcode(val.trim());
                  if (added) {
                    _searchCtrl.clear();
                    context.read<PosCubit>().searchProducts('');
                    setState(() {});
                  }
                }
              },
            ),
          ),
        ),

        // Category Chips: Horizontal scrollable row
        BlocBuilder<PosCubit, PosState>(
          builder: (context, state) {
            try {
              final allSelected = state.selectedCategory == 'All';
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _categoryChip(
                      label: 'الكل',
                      isSelected: allSelected,
                      onTap: () => context.read<PosCubit>().filterByCategory('All'),
                    ),
                    const SizedBox(width: 8),
                    ...state.categories.map((cat) {
                      final isSelected = state.selectedCategory == cat.id;
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _categoryChip(
                          label: cat.name,
                          isSelected: isSelected,
                          onTap: () => context.read<PosCubit>().filterByCategory(cat.id),
                        ),
                      );
                    }),
                  ],
                ),
              );
            } catch (e, st) {
              return Container(
                height: 44,
                color: Colors.red.shade50,
                padding: const EdgeInsets.all(8),
                child: Text('CatChip error: $e', style: const TextStyle(color: Colors.red, fontSize: 10)),
              );
            }
          },
        ),

        const SizedBox(height: 10),

        // Products Grid
        Expanded(
          child: BlocBuilder<PosCubit, PosState>(
            builder: (context, state) {
              try {
                if (state is PosLoading) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                }
                if (state is PosError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 64, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(
                          state.message,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            color: AppColors.error,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => context.read<PosCubit>().init(),
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text('إعادة المحاولة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                if (state.filteredVariants.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد منتجات مطابقة للبحث',
                          style: GoogleFonts.cairo(color: Colors.grey.shade600, fontSize: 15),
                        ),
                      ],
                    ),
                  );
                }
                final posCubit = context.read<PosCubit>();
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.84,
                  ),
                  itemCount: state.filteredVariants.length,
                  itemBuilder: (context, index) {
                    final variant = state.filteredVariants[index];
                    final catId = posCubit.getProductCategoryId(variant.productId);
                    return _ProductCard(variant: variant, categoryId: catId);
                  },
                );
              } catch (e, st) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text('Grid error: $e\n$st', style: const TextStyle(color: Colors.red, fontSize: 11)),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _categoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outlineVariant,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.cairo(
              color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PRODUCT CARD: INSTANT IN-CARD QUANTITY CONTROLS + VARIANT PICKER
// ---------------------------------------------------------------------------
class _ProductCard extends StatelessWidget {
  final VariantEntity variant;
  final String? categoryId;

  const _ProductCard({required this.variant, this.categoryId});

  @override
  Widget build(BuildContext context) {
    try {
      return _buildContent(context);
    } catch (e, st) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: Colors.red.shade50,
        child: SingleChildScrollView(
          child: Text('ProductCard error:\n$e\n$st',
              style: const TextStyle(color: Colors.red, fontSize: 10)),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    final isOut = variant.quantity <= 0;
    final isLow = variant.quantity > 0 && variant.quantity <= 10;
    final categoryColor = _getCategoryColor(categoryId);
    final posCubit = context.read<PosCubit>();
    final productName = posCubit.getProductName(variant.productId);
    final displayName = productName.isNotEmpty ? productName : variant.productCode;
    final initialLetter = displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : 'P';

    return BlocBuilder<PosCubit, PosState>(
      buildWhen: (prev, curr) => prev.cart != curr.cart,
      builder: (context, state) {
        SaleItemEntity? cartItem;
        try {
          cartItem = state.cart.firstWhere((item) => item.variantId == variant.id);
        } catch (_) {
          cartItem = null;
        }
        final int inCartQty = cartItem?.quantity ?? 0;

        return Opacity(
          opacity: isOut ? 0.55 : 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: isOut ? Colors.grey.shade100 : AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: inCartQty > 0
                    ? AppColors.primary
                    : (isOut ? Colors.grey.shade300 : AppColors.outlineVariant.withValues(alpha: 0.6)),
                width: inCartQty > 0 ? 2.0 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: inCartQty > 0
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: inCartQty > 0 ? 10 : 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Avatar + Stock Pill + Variant Selector Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: categoryColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: categoryColor.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initialLetter,
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildStockPill(isOut, isLow, variant.quantity),
                          const SizedBox(height: 4),
                          // Optional Button to explore other sizes/colors
                          InkWell(
                            onTap: isOut ? null : () => _showVariantModal(context, variant),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.tune_rounded, size: 12, color: AppColors.primary),
                                  const SizedBox(width: 3),
                                  Text(
                                    'المقاسات',
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Product Title
                  Text(
                    displayName,
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 2),

                  // Variant Badges: Color + Size
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${variant.color} • ${variant.size}',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        variant.sku,
                        style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey.shade500),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Price
                  Text(
                    '${Money(variant.salePrice).toDisplay()} ج.م',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: AppColors.primary,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Dynamic In-Card Action:
                  // If not in cart -> Large "إضافة" button
                  // If in cart -> Interactive Stepper [-] [X في السلة] [+]
                  if (inCartQty == 0)
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: ElevatedButton.icon(
                        onPressed: isOut
                            ? null
                            : () => posCubit.addToCart(variant, 1),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                        label: Text(
                          'إضافة للسلة',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_rounded, color: Colors.white, size: 16),
                            onPressed: () => posCubit.decreaseQty(variant.id),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 38),
                          ),
                          Expanded(
                            child: Text(
                              '$inCartQty في السلة',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                            onPressed: inCartQty >= variant.quantity
                                ? null
                                : () => posCubit.addToCart(variant, 1),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 38),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStockPill(bool isOut, bool isLow, int qty) {
    Color bg;
    Color text;
    String label;
    if (isOut) {
      bg = AppColors.errorContainer;
      text = AppColors.error;
      label = 'نفذت الكمية';
    } else if (isLow) {
      bg = AppColors.warningContainer;
      text = AppColors.warning;
      label = 'متبقي $qty';
    } else {
      bg = AppColors.successContainer;
      text = AppColors.success;
      label = 'متوفر ($qty)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: GoogleFonts.cairo(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: text,
        ),
      ),
    );
  }

  void _showVariantModal(BuildContext context, VariantEntity variant) {
    final posCubit = context.read<PosCubit>();
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: posCubit,
        child: _VariantModal(initialVariant: variant),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// UPGRADED VARIANT MODAL: SELECT COLOR, SIZE & BULK QUANTITY EASILY
// ---------------------------------------------------------------------------
class _VariantModal extends StatefulWidget {
  final VariantEntity initialVariant;
  const _VariantModal({required this.initialVariant});

  @override
  State<_VariantModal> createState() => _VariantModalState();
}

class _VariantModalState extends State<_VariantModal> {
  late List<VariantEntity> _productVariants;
  late String _selectedColor;
  late String _selectedSize;
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialVariant.color;
    _selectedSize = widget.initialVariant.size;
    _productVariants = [widget.initialVariant];
  }

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    try {
      final posCubit = context.read<PosCubit>();
      final allProductVariants = posCubit.getVariantsForProduct(widget.initialVariant.productId);
      setState(() {
        _productVariants = allProductVariants.isNotEmpty
            ? allProductVariants
            : [widget.initialVariant];
      });
    } catch (_) {
      _productVariants = [widget.initialVariant];
    }
  }

  VariantEntity get _currentVariant {
    try {
      return _productVariants.firstWhere(
        (v) => v.color == _selectedColor && v.size == _selectedSize,
      );
    } catch (_) {
      try {
        return _productVariants.firstWhere((v) => v.color == _selectedColor);
      } catch (_) {
        return _productVariants.first;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _currentVariant;
    final maxStock = v.quantity;
    final availableColors = _productVariants.map((item) => item.color).toSet().toList();
    final sizesForColor = _productVariants.where((item) => item.color == _selectedColor).toList();
    final posCubit = context.read<PosCubit>();
    final productName = posCubit.getProductName(v.productId);
    final displayName = productName.isNotEmpty ? productName : v.productCode;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 8,
      backgroundColor: AppColors.surfaceContainerLowest,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Header
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : 'P',
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.cairo(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          'كود الصنف: ${v.sku} • السعر: ${Money(v.salePrice).toDisplay()} ج.م',
                          style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Color Selection
              Text(
                'اللون المختار: $_selectedColor',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: availableColors.map((colorName) {
                  final isSelected = colorName == _selectedColor;
                  final colorVal = _mapColorNameToColor(colorName);
                  final isWhite = colorVal == Colors.white;

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedColor = colorName;
                        final newSizes = _productVariants
                            .where((item) => item.color == colorName)
                            .toList();
                        if (newSizes.isNotEmpty &&
                            !newSizes.any((item) => item.size == _selectedSize)) {
                          _selectedSize = newSizes.first.size;
                        }
                        if (_qty > _currentVariant.quantity) {
                          _qty = _currentVariant.quantity > 0 ? _currentVariant.quantity : 1;
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.surfaceContainer : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                          width: isSelected ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: colorVal,
                              shape: BoxShape.circle,
                              border: isWhite ? Border.all(color: Colors.grey.shade400) : null,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            colorName,
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppColors.primary : AppColors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Size Selection (Grid of buttons showing size and remaining stock)
              Text(
                'المقاس: $_selectedSize',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: sizesForColor.map((variantItem) {
                  final sizeLabel = variantItem.size;
                  final isSelected = sizeLabel == _selectedSize;
                  final stock = variantItem.quantity;
                  final isOutOfStock = stock <= 0;

                  return InkWell(
                    onTap: isOutOfStock
                        ? null
                        : () {
                            setState(() {
                              _selectedSize = sizeLabel;
                              if (_qty > stock) _qty = stock > 0 ? stock : 1;
                            });
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isOutOfStock
                                ? Colors.grey.shade100
                                : AppColors.surfaceContainerLowest),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : (isOutOfStock
                                  ? Colors.grey.shade300
                                  : AppColors.outlineVariant),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sizeLabel,
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isSelected
                                  ? Colors.white
                                  : (isOutOfStock ? Colors.grey : AppColors.onSurface),
                            ),
                          ),
                          Text(
                            isOutOfStock ? 'نفذ' : '$stock متبقي',
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : (isOutOfStock ? Colors.red : Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Quantity Stepper with Quick Presets
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الكمية المطلوبة:',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          IconButton(
                            onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                            color: AppColors.primary,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.outlineVariant),
                            ),
                            child: Text(
                              '$_qty',
                              style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            onPressed: (_qty < maxStock && maxStock > 0)
                                ? () => setState(() => _qty++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          // Quick preset chips
                          ...[1, 2, 5, 10].map((preset) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2.0),
                              child: InkWell(
                                onTap: maxStock >= preset
                                    ? () => setState(() => _qty = preset)
                                    : null,
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _qty == preset ? AppColors.primary : AppColors.surfaceContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$preset',
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _qty == preset ? Colors.white : AppColors.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'إجمالي الصنف:',
                        style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      Text(
                        '${Money(v.salePrice * _qty).toDisplay()} ج.م',
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Add to Cart Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: maxStock <= 0
                      ? null
                      : () {
                          context.read<PosCubit>().addToCart(v, _qty);
                          Navigator.of(context).pop();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.white, size: 18),
                  label: Text(
                    maxStock <= 0 ? 'المنتج غير متوفر' : 'إضافة إلى السلة ($_qty قطعة - ${Money(v.salePrice * _qty).toDisplay()} ج.م)',
                    style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LEFT PANEL: CART (440px)
// ---------------------------------------------------------------------------
class _CartPanel extends StatefulWidget {
  const _CartPanel();

  @override
  State<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<_CartPanel> {
  final _discountCtrl = TextEditingController();
  final _receivedCtrl = TextEditingController();
  bool _isPercentageDiscount = false;
  String _paymentMethod = 'cash'; // 'cash' or 'card'
  bool _isWholesaleMode = false;

  @override
  void dispose() {
    _discountCtrl.dispose();
    _receivedCtrl.dispose();
    super.dispose();
  }

  void _recalculateDiscount(int subtotal) {
    final text = _discountCtrl.text.trim();
    if (text.isEmpty) {
      context.read<PosCubit>().applyDiscount(0);
      return;
    }

    if (_isPercentageDiscount) {
      final percent = double.tryParse(text) ?? 0.0;
      final discountPiasters = (subtotal * (percent / 100.0)).round();
      context.read<PosCubit>().applyDiscount(discountPiasters);
    } else {
      final money = Money.fromString(text);
      context.read<PosCubit>().applyDiscount(money.piasters);
    }
  }

  void _toggleWholesalePrices(bool wholesale) {
    final posCubit = context.read<PosCubit>();
    for (final item in posCubit.state.cart) {
      final v = posCubit.getVariantById(item.variantId);
      if (wholesale && v != null && v.wholesalePrice > 0) {
        posCubit.updateUnitPrice(item.variantId, v.wholesalePrice);
      } else if (!wholesale && v != null) {
        posCubit.updateUnitPrice(item.variantId, v.salePrice);
      }
    }
  }

  void _onCustomerSelected(CustomerEntity cust) {
    final posCubit = context.read<PosCubit>();
    posCubit.assignCustomer(cust);

    if (cust.isWholesale) {
      setState(() => _isWholesaleMode = true);
      _toggleWholesalePrices(true);
    }

    if (cust.discountPercent > 0) {
      _discountCtrl.text = '${cust.discountPercent}';
      _isPercentageDiscount = true;
      _recalculateDiscount(posCubit.state.subtotal);
      setState(() {});
    }
  }

  Future<void> _handleCheckout(PosState state) async {
    if (state.cart.isEmpty || state.isProcessing) return;

    String? cashierId;
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        cashierId = authState.user.id;
      }
    } catch (_) {}

    final messenger = ScaffoldMessenger.of(context);
    final posCubit = context.read<PosCubit>();
    final ok = await posCubit.checkout(
      cashierId: cashierId,
      paymentMethod: _paymentMethod,
    );
    if (ok && mounted) {
      _receivedCtrl.clear();
      _discountCtrl.clear();
      setState(() => _isWholesaleMode = false);

      final invoicesRepo = getIt<InvoicesRepository>();
      final res = await invoicesRepo.getInvoices(limit: 1);
      InvoiceDetailsEntity? latestInvoice;
      res.fold((_) {}, (list) => latestInvoice = list.isNotEmpty ? list.first : null);

      if (latestInvoice != null && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => SaleSuccessDialog(invoice: latestInvoice!),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'تم إتمام عملية البيع بنجاح!',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildContent(context);
    } catch (e, st) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text('CartPanel build error:\n$e\n$st',
            style: const TextStyle(color: Colors.red, fontSize: 11)),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    return BlocBuilder<PosCubit, PosState>(
      builder: (context, state) {
        final totalPieces = state.cart.fold<int>(0, (sum, item) => sum + item.quantity);
        final receivedPiasters = Money.fromString(_receivedCtrl.text).piasters;
        final int changePiasters = receivedPiasters > state.total
            ? (receivedPiasters - state.total).toInt()
            : 0;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f12): () => _handleCheckout(state),
          },
          child: Container(
            color: AppColors.surfaceContainerLowest,
            child: Column(
              children: [
                // Cart Header: Title + Items/Pieces count + Wholesale toggle + Clear [Esc]
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'سلة المشتريات',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Badge showing items & pieces
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${state.cart.length} أصناف • $totalPieces قطع',
                              style: GoogleFonts.cairo(
                                color: AppColors.onPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Wholesale / Retail Toggle Button
                      Container(
                        height: 28,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: _isWholesaleMode ? Colors.purple.shade50 : AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isWholesaleMode ? Colors.purple.shade300 : AppColors.outlineVariant,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                if (!_isWholesaleMode) return;
                                setState(() => _isWholesaleMode = false);
                                _toggleWholesalePrices(false);
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: !_isWholesaleMode ? AppColors.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'قطاعي',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: !_isWholesaleMode ? Colors.white : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                if (_isWholesaleMode) return;
                                setState(() => _isWholesaleMode = true);
                                _toggleWholesalePrices(true);
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _isWholesaleMode ? Colors.purple.shade700 : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.storefront_rounded,
                                      size: 12,
                                      color: _isWholesaleMode ? Colors.white : Colors.purple.shade700,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      'بيع جملة',
                                      style: GoogleFonts.cairo(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: _isWholesaleMode ? Colors.white : Colors.purple.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        onPressed: state.cart.isEmpty
                            ? null
                            : () {
                                _receivedCtrl.clear();
                                _discountCtrl.clear();
                                context.read<PosCubit>().clearCart();
                              },
                        icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                        label: Text(
                          'مسح',
                          style: GoogleFonts.cairo(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),

                // Customer Section (Two buttons when guest, full perks when assigned)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: state.customer != null ? AppColors.surfaceContainer : AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: state.customer != null ? AppColors.primary.withValues(alpha: 0.3) : AppColors.outlineVariant,
                    ),
                  ),
                  child: state.customer != null
                      ? Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: state.customer!.isWholesale ? Colors.purple.shade100 : AppColors.primary,
                              child: Icon(
                                state.customer!.isWholesale ? Icons.storefront_rounded : Icons.person_rounded,
                                size: 18,
                                color: state.customer!.isWholesale ? Colors.purple.shade900 : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          state.customer!.name,
                                          style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (state.customer!.isWholesale) ...[
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.purple.shade200),
                                          ),
                                          child: Text(
                                            'تاجر جملة',
                                            style: GoogleFonts.cairo(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.purple.shade800,
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (state.customer!.discountPercent > 0) ...[
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.green.shade300),
                                          ),
                                          child: Text(
                                            'خصم ${state.customer!.discountPercent}%',
                                            style: GoogleFonts.cairo(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green.shade800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        state.customer!.phone,
                                        style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.stars_rounded, size: 10, color: Colors.amber),
                                            const SizedBox(width: 2),
                                            Text(
                                              '${state.customer!.loyaltyPoints} نقطة',
                                              style: GoogleFonts.cairo(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.brown,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: AppColors.primary),
                              tooltip: 'تغيير العميل',
                              onPressed: () async {
                                final selected = await showDialog<CustomerEntity>(
                                  context: context,
                                  builder: (_) => const _AssignCustomerDialog(),
                                );
                                if (selected != null && context.mounted) {
                                  _onCustomerSelected(selected);
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                              tooltip: 'إزالة العميل والعودة لنقدي',
                              onPressed: () {
                                context.read<PosCubit>().assignCustomer(null);
                              },
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.grey.shade400,
                              child: const Icon(Icons.person_outline, size: 16, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'عميل نقدي',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: AppColors.onSurface,
                                ),
                              ),
                            ),
                            // Single Clean Button: Assign Customer
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6), width: 1.2),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.person_search_rounded, size: 15),
                              label: Text(
                                'تعيين عميل',
                                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              onPressed: () async {
                                final selected = await showDialog<CustomerEntity>(
                                  context: context,
                                  builder: (_) => const _AssignCustomerDialog(),
                                );
                                if (selected != null && context.mounted) {
                                  _onCustomerSelected(selected);
                                }
                              },
                            ),
                          ],
                        ),
                ),

                const Divider(height: 8),

                // Cart Items List
                Expanded(
                  child: state.cart.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                'سلة المشتريات فارغة',
                                style: GoogleFonts.cairo(
                                  color: Colors.grey.shade500,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'انقر على أي منتج لإضافته فوراً إلى الفاتورة',
                                style: GoogleFonts.cairo(
                                  color: Colors.grey.shade400,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: state.cart.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = state.cart[index];
                            final posCubit = context.read<PosCubit>();
                            final v = posCubit.getVariantById(item.variantId);
                            final maxStock = v?.quantity ?? 999;
                            return _CartItemTile(
                              key: ValueKey(item.variantId),
                              item: item,
                              maxStock: maxStock,
                            );
                          },
                        ),
                ),

                const Divider(height: 1),

                // Checkout Footer
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(top: BorderSide(color: AppColors.outlineVariant.withValues(alpha: 0.5))),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Subtotal
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'المجموع الفرعي',
                            style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          Text(
                            '${Money(state.subtotal).toDisplay()} ج.م',
                            style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Discount with % and ج.م toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الخصم',
                            style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.outlineVariant),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _toggleBtn(
                                      label: '%',
                                      isSelected: _isPercentageDiscount,
                                      onTap: () {
                                        setState(() => _isPercentageDiscount = true);
                                        _recalculateDiscount(state.subtotal);
                                      },
                                    ),
                                    _toggleBtn(
                                      label: 'ج.م',
                                      isSelected: !_isPercentageDiscount,
                                      onTap: () {
                                        setState(() => _isPercentageDiscount = false);
                                        _recalculateDiscount(state.subtotal);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 85,
                                height: 34,
                                child: TextField(
                                  controller: _discountCtrl,
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    hintText: '0',
                                    isDense: true,
                                    filled: true,
                                    fillColor: AppColors.surfaceContainerLowest,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: AppColors.outlineVariant),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  ),
                                  onChanged: (_) => _recalculateDiscount(state.subtotal),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Grand Total: Big, bold, Primary color
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'الإجمالي النهائي',
                              style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${Money(state.total).toDisplay()} ج.م',
                              style: GoogleFonts.cairo(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Payment Method Buttons: "نقدي (كاش)" and "بطاقة / فيزا"
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => setState(() => _paymentMethod = 'cash'),
                              style: ElevatedButton.styleFrom(
                                elevation: _paymentMethod == 'cash' ? 2 : 0,
                                backgroundColor: _paymentMethod == 'cash'
                                    ? AppColors.primary
                                    : AppColors.surfaceContainerLowest,
                                foregroundColor: _paymentMethod == 'cash'
                                    ? Colors.white
                                    : AppColors.onSurface,
                                side: BorderSide(
                                  color: _paymentMethod == 'cash'
                                      ? AppColors.primary
                                      : AppColors.outlineVariant,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              icon: const Icon(Icons.payments_outlined, size: 18),
                              label: Text(
                                'نقدي (كاش)',
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => setState(() => _paymentMethod = 'card'),
                              style: ElevatedButton.styleFrom(
                                elevation: _paymentMethod == 'card' ? 2 : 0,
                                backgroundColor: _paymentMethod == 'card'
                                    ? AppColors.primary
                                    : AppColors.surfaceContainerLowest,
                                foregroundColor: _paymentMethod == 'card'
                                    ? Colors.white
                                    : AppColors.onSurface,
                                side: BorderSide(
                                  color: _paymentMethod == 'card'
                                      ? AppColors.primary
                                      : AppColors.outlineVariant,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              icon: const Icon(Icons.credit_card_rounded, size: 18),
                              label: Text(
                                'بطاقة / فيزا',
                                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Fast Cash Banknote Presets (when cash mode is active)
                      if (_paymentMethod == 'cash') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'الدفع السريع:',
                              style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            const SizedBox(width: 6),
                            // Exact Amount Preset
                            InkWell(
                              onTap: () {
                                _receivedCtrl.text = Money(state.total).toDisplay();
                                setState(() {});
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.outlineVariant),
                                ),
                                child: Text(
                                  'المبلغ بالضبط',
                                  style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // 50, 100, 200, 500 EGP chips
                            ...[50, 100, 200, 500].map((preset) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                                child: InkWell(
                                  onTap: () {
                                    _receivedCtrl.text = '$preset.00';
                                    setState(() {});
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.outlineVariant),
                                    ),
                                    child: Text(
                                      '$preset',
                                      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              'المستلم:',
                              style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: 34,
                                child: TextField(
                                  controller: _receivedCtrl,
                                  keyboardType: TextInputType.number,
                                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold),
                                  decoration: InputDecoration(
                                    hintText: 'المبلغ المدفوع',
                                    isDense: true,
                                    filled: true,
                                    fillColor: AppColors.surfaceContainerLowest,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: AppColors.outlineVariant),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'الباقي: ',
                              style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            Text(
                              '${Money(changePiasters).toDisplay()} ج.م',
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: changePiasters > 0 ? AppColors.success : AppColors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 10),

                      // Massive Checkout [F12] Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: state.cart.isEmpty || state.isProcessing
                              ? null
                              : () => _handleCheckout(state),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 3,
                          ),
                          icon: state.isProcessing
                              ? const SizedBox.shrink()
                              : const Icon(Icons.check_circle_rounded, size: 22, color: Colors.white),
                          label: state.isProcessing
                              ? const CircularProgressIndicator(color: Colors.white)
                              : Text(
                                  'إتمام عملية البيع [F12]',
                                  style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _toggleBtn({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppColors.onSurface,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CART ITEM TILE: DIRECT INLINE QUANTITY CONTROLLER (FAST & RESPONSIVE)
// ---------------------------------------------------------------------------
class _CartItemTile extends StatefulWidget {
  final SaleItemEntity item;
  final int maxStock;

  const _CartItemTile({super.key, required this.item, required this.maxStock});

  @override
  State<_CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends State<_CartItemTile> {
  late TextEditingController _qtyCtrl;
  final FocusNode _qtyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: '${widget.item.quantity}');
  }

  @override
  void didUpdateWidget(covariant _CartItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.quantity != widget.item.quantity && !_qtyFocus.hasFocus) {
      _qtyCtrl.text = '${widget.item.quantity}';
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  void _onQtyChanged(String val) {
    final parsed = int.tryParse(val.trim());
    if (parsed == null || parsed <= 0) return;
    final valid = (widget.maxStock > 0 && parsed > widget.maxStock)
        ? widget.maxStock
        : parsed;
    context.read<PosCubit>().updateQuantity(widget.item.variantId, valid);
  }

  void _openPriceEditDialog(BuildContext context) {
    final item = widget.item;
    final priceCtrl = TextEditingController(text: (item.price / 100).toStringAsFixed(2));
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.price_change_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'تعديل سعر الصنف (سعر خاص / جملة)',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.productName} (${item.color} - ${item.size})',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: GoogleFonts.cairo(fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'سعر بيع الوحدة بالج.م *',
                  suffixText: 'ج.م',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'يرجى إدخال السعر';
                  final num = double.tryParse(val.trim());
                  if (num == null || num < 0) return 'السعر غير صالح';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              final pounds = double.parse(priceCtrl.text.trim());
              final piasters = (pounds * 100).toInt();
              context.read<PosCubit>().updateUnitPrice(item.variantId, piasters);
              Navigator.pop(ctx);
            },
            child: Text(
              'حفظ السعر',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildContent(context);
    } catch (e, st) {
      return Container(
        padding: const EdgeInsets.all(8),
        color: Colors.red.shade50,
        child: SingleChildScrollView(
          child: Text('CartItemTile error:\n$e\n$st',
              style: const TextStyle(color: Colors.red, fontSize: 10)),
        ),
      );
    }
  }

  Widget _buildContent(BuildContext context) {
    final item = widget.item;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${item.color} • ${item.size}',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _openPriceEditDialog(context),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${Money(item.price).toDisplay()} ج.م',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.edit_outlined, size: 12, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Stepper + Direct Editable Quantity Input Box
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => context.read<PosCubit>().decreaseQty(item.variantId),
                ),
                // Inline Direct Text Input for Quantity
                Container(
                  width: 38,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  child: TextField(
                    controller: _qtyCtrl,
                    focusNode: _qtyFocus,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onSubmitted: _onQtyChanged,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: item.quantity >= widget.maxStock
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('الرصيد المتاح هو ${widget.maxStock} فقط'),
                              backgroundColor: AppColors.warning,
                              duration: const Duration(milliseconds: 700),
                            ),
                          );
                        }
                      : () => context.read<PosCubit>().increaseQty(item.variantId),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Line Total
          Text(
            '${Money(item.total).toDisplay()} ج.م',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.primary,
            ),
          ),

          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => context.read<PosCubit>().removeFromCart(item.variantId),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ALL-IN-ONE ASSIGN & ADD CUSTOMER DIALOG
// ---------------------------------------------------------------------------
class _AssignCustomerDialog extends StatefulWidget {
  const _AssignCustomerDialog();

  @override
  State<_AssignCustomerDialog> createState() => _AssignCustomerDialogState();
}

class _AssignCustomerDialogState extends State<_AssignCustomerDialog> {
  final _searchCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _discountCtrl;
  String _customerType = 'retail';

  List<CustomerEntity> _allCustomers = [];
  List<CustomerEntity> _filteredCustomers = [];
  bool _isLoading = true;
  bool _isCreatingNew = false;
  bool _isSavingNew = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _discountCtrl = TextEditingController();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final result = await getIt<CustomerRepository>().getCustomers();
    if (mounted) {
      result.fold(
        (_) => setState(() => _isLoading = false),
        (customers) {
          setState(() {
            _allCustomers = customers;
            _filteredCustomers = customers;
            _isLoading = false;
          });
        },
      );
    }
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredCustomers = _allCustomers;
      } else {
        _filteredCustomers = _allCustomers
            .where((c) =>
                c.name.toLowerCase().contains(q) || c.phone.contains(q))
            .toList();
      }
    });
  }

  void _switchToCreateMode([String initialText = '']) {
    final text = initialText.trim();
    final isPhone = RegExp(r'^[0-9+]+$').hasMatch(text);
    setState(() {
      _nameCtrl.text = isPhone ? '' : text;
      _phoneCtrl.text = isPhone ? text : '';
      _customerType = 'retail';
      _discountCtrl.text = '';
      _isCreatingNew = true;
    });
  }

  Future<void> _submitNewCustomer() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _isSavingNew = true);

    final discount = int.tryParse(_discountCtrl.text.trim()) ?? 0;
    final cust = CustomerEntity(
      id: '',
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      loyaltyPoints: 0,
      discountPercent: discount,
      customerType: _customerType,
      createdAt: DateTime.now(),
    );

    final res = await getIt<CustomerRepository>().addCustomer(cust);
    res.fold(
      (failure) {
        if (mounted) {
          setState(() => _isSavingNew = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ: ${failure.message}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      },
      (_) async {
        final listRes = await getIt<CustomerRepository>().getCustomers(search: cust.phone);
        CustomerEntity? createdCust;
        listRes.fold((_) => null, (list) {
          if (list.isNotEmpty) createdCust = list.first;
        });
        createdCust ??= cust;
        if (mounted) {
          Navigator.pop(context, createdCust);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                _isCreatingNew ? Icons.person_add_rounded : Icons.person_search_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                _isCreatingNew ? 'إضافة عميل جديد' : 'تعيين عميل للفاتورة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          if (!_isCreatingNew)
            TextButton.icon(
              onPressed: () => _switchToCreateMode(_searchCtrl.text),
              icon: const Icon(Icons.add, size: 16),
              label: Text(
                'عميل جديد',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            )
          else
            TextButton.icon(
              onPressed: () => setState(() => _isCreatingNew = false),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text(
                'رجوع للبحث',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _isCreatingNew ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: SizedBox(
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.cairo(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو رقم الهاتف...',
                    hintStyle: GoogleFonts.cairo(fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _filter('');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: _filter,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _filteredCustomers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_off_outlined, size: 44, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text(
                                    'لا توجد نتائج مطابقة',
                                    style: GoogleFonts.cairo(
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => _switchToCreateMode(_searchCtrl.text),
                                    icon: const Icon(Icons.add, color: Colors.white, size: 16),
                                    label: Text(
                                      _searchCtrl.text.trim().isNotEmpty
                                          ? 'تسجيل "${_searchCtrl.text.trim()}" كعميل جديد'
                                          : 'إضافة عميل جديد',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _filteredCustomers.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final customer = _filteredCustomers[index];
                                final isWholesale = customer.isWholesale;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: isWholesale ? Colors.purple.shade50 : AppColors.surfaceContainer,
                                    child: Icon(
                                      isWholesale ? Icons.storefront_rounded : Icons.person_rounded,
                                      size: 18,
                                      color: isWholesale ? Colors.purple.shade700 : AppColors.primary,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          customer.name,
                                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isWholesale)
                                        Container(
                                          margin: const EdgeInsets.only(right: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.purple.shade200),
                                          ),
                                          child: Text(
                                            'جملة',
                                            style: GoogleFonts.cairo(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.purple.shade800,
                                            ),
                                          ),
                                        ),
                                      if (customer.discountPercent > 0)
                                        Container(
                                          margin: const EdgeInsets.only(right: 4),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.green.shade200),
                                          ),
                                          child: Text(
                                            '${customer.discountPercent}% خصم',
                                            style: GoogleFonts.cairo(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green.shade800,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    customer.phone,
                                    style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${customer.loyaltyPoints} نقطة',
                                      style: GoogleFonts.cairo(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.brown.shade800,
                                      ),
                                    ),
                                  ),
                                  onTap: () => Navigator.pop(context, customer),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          secondChild: SizedBox(
            height: 400,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _nameCtrl,
                      style: GoogleFonts.cairo(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'اسم العميل *',
                        hintText: 'مثال: محمد أحمد',
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'يرجى إدخال اسم العميل' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.cairo(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف *',
                        hintText: 'مثال: 01012345678',
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      validator: (val) => val == null || val.trim().isEmpty ? 'يرجى إدخال رقم الهاتف' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _customerType,
                      style: GoogleFonts.cairo(fontSize: 13, color: AppColors.onSurface),
                      decoration: InputDecoration(
                        labelText: 'تصنيف العميل',
                        prefixIcon: const Icon(Icons.category_outlined, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: [
                        DropdownMenuItem(value: 'retail', child: Text('عميل عادي (قطاعي)', style: GoogleFonts.cairo())),
                        DropdownMenuItem(value: 'wholesale', child: Text('تاجر جملة (Wholesale)', style: GoogleFonts.cairo())),
                        DropdownMenuItem(value: 'vip', child: Text('عميل مميز (VIP)', style: GoogleFonts.cairo())),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _customerType = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _discountCtrl,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.cairo(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'نسبة الخصم الدائم للعميل (%) [اختياري]',
                        hintText: 'مثال: 5 أو 10',
                        suffixText: '%',
                        prefixIcon: const Icon(Icons.percent_rounded, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (!_isCreatingNew)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade700)),
          )
        else ...[
          TextButton(
            onPressed: () => setState(() => _isCreatingNew = false),
            child: Text('رجوع', style: GoogleFonts.cairo(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: _isSavingNew ? null : _submitNewCustomer,
            child: _isSavingNew
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('حفظ وتعيين للفاتورة', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ],
    );
  }
}
