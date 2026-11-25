import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/utils/money.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../auth/presentation/widgets/manager_auth_dialog.dart';
import '../../../pos/domain/entities/sale_entity.dart';
import '../../domain/entities/return_entity.dart';
import '../../domain/entities/return_item_entity.dart';
import '../cubits/returns_cubit.dart';
import '../cubits/returns_state.dart';

class ReturnScreen extends StatefulWidget {
  final String? initialInvoiceRef;

  const ReturnScreen({super.key, this.initialInvoiceRef});

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final _searchCtrl = TextEditingController();
  final _historySearchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _imeiVerifyCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
  String _historyQuery = '';
  String _activeDateFilter = 'all';
  Timer? _searchDebounce;
  bool _mobileImeiEnabled = false;
  int _activeTab = 0;
  bool _isDialogOpen = false;
  String? _lastOpenedSaleId;

  static const _quickReasons = [
    'عيب صناعة',
    'مقاس/نوع غير مناسب',
    'رغبة العميل',
  ];

  @override
  void initState() {
    super.initState();
    _loadFeatureFlags();
    if (widget.initialInvoiceRef != null &&
        widget.initialInvoiceRef!.trim().isNotEmpty) {
      _searchCtrl.text = widget.initialInvoiceRef!.trim();
    }
  }

  Future<void> _loadFeatureFlags() async {
    if (!getIt.isRegistered<FeatureGate>()) return;
    final enabled =
        await getIt<FeatureGate>().isEnabled(FeatureKeys.mobileImeiUsed);
    if (mounted && enabled != _mobileImeiEnabled) {
      setState(() => _mobileImeiEnabled = enabled);
    }
  }

  Future<bool> _verifyReturnedImeisIfNeeded(
    SaleEntity sale,
    List<ReturnItemEntity> returnItems,
  ) async {
    if (!_mobileImeiEnabled && getIt.isRegistered<FeatureGate>()) {
      final enabled =
          await getIt<FeatureGate>().isEnabled(FeatureKeys.mobileImeiUsed);
      if (!enabled) return true;
    } else if (!_mobileImeiEnabled) {
      return true;
    }
    if (!getIt.isRegistered<AppDatabase>()) return true;

    final selectedSaleItemIds = returnItems
        .where((i) => i.qty > 0 && i.saleItemId != null)
        .map((i) => i.saleItemId!)
        .toSet();
    if (selectedSaleItemIds.isEmpty) return true;

    final db = getIt<AppDatabase>();
    final saleItems = await (db.select(db.saleItems)
          ..where((t) => t.saleId.equals(sale.id)))
        .get();
    final soldImeis = saleItems
        .where((si) =>
            selectedSaleItemIds.contains(si.id) &&
            si.imei != null &&
            si.imei!.trim().isNotEmpty)
        .map((si) => si.imei!.trim())
        .toSet();
    if (soldImeis.isEmpty) return true;

    final enteredImei = _imeiVerifyCtrl.text.trim();
    if (enteredImei.isEmpty || !soldImeis.contains(enteredImei)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'يرجى مسح أو إدخال رقم IMEI المطابق للجهاز المباع في الفاتورة',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _historySearchCtrl.dispose();
    _reasonCtrl.dispose();
    _imeiVerifyCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _submitReturn(BuildContext context, ReturnsState state) async {
    final sale = state.selectedSale;
    if (sale == null || state.isProcessing || state.totalRefund == 0) return;

    String cashierId = 'cashier';
    bool isCashier = false;
    try {
      final authState = this.context.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        cashierId = authState.user.id;
        isCashier = authState.user.role.toLowerCase() == 'cashier';
      }
    } catch (_) {}

    final imeiValid = await _verifyReturnedImeisIfNeeded(
      sale,
      state.returnItems,
    );
    if (!imeiValid || !context.mounted) return;

    if (isCashier && getIt.isRegistered<FeatureGate>()) {
      final pinProtected = await getIt<FeatureGate>()
          .isEnabled(FeatureKeys.managerPinProtection);
      if (pinProtected) {
        if (!context.mounted) return;
        final approved = await ManagerAuthHelper.requestManagerApproval(
          context,
          title: 'اعتماد المرتجع النقدي (صلاحية مدير)',
          message:
              'يتطلب تنفيذ المرتجع واسترداد النقدية موافقة المدير أو المشرف.',
        );
        if (!approved || !context.mounted) return;
      }
    }

    if (!context.mounted) return;
    context.read<ReturnsCubit>().processReturn(
          reason: _reasonCtrl.text,
          userId: cashierId,
          paymentMethod: sale.paymentMethod,
        );
  }

  void _openReturnDetailsDialog(BuildContext screenContext) {
    if (_isDialogOpen || !mounted) return;
    final cubit = screenContext.read<ReturnsCubit>();
    if (cubit.state.selectedSale == null) return;

    _isDialogOpen = true;
    _lastOpenedSaleId = cubit.state.selectedSale!.id;

    showDialog<void>(
      context: screenContext,
      barrierDismissible: true,
      builder: (dialogContext) {
        return BlocProvider<ReturnsCubit>.value(
          value: cubit,
          child: _ReturnDetailsDialog(
            reasonCtrl: _reasonCtrl,
            imeiVerifyCtrl: _imeiVerifyCtrl,
            mobileImeiEnabled: _mobileImeiEnabled,
            quickReasons: _quickReasons,
            dateFormat: _dateFormat,
            formatPayment: _formatPayment,
            formatVariantSubtitle: _formatVariantSubtitle,
            onSubmit: (ctx, st) => _submitReturn(ctx, st),
          ),
        );
      },
    ).whenComplete(() {
      _isDialogOpen = false;
      _lastOpenedSaleId = null;
      if (mounted) {
        cubit.clearSelection();
      }
    });
  }

  String _formatPayment(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'cash':
        return 'نقدي';
      case 'card':
      case 'visa':
        return 'بطاقة';
      case 'installment':
        return 'تقسيط';
      case 'mixed':
        return 'مختلط';
      default:
        return raw;
    }
  }

  String _formatVariantSubtitle(String color, String size, int unitPrice) {
    final parts = <String>[];
    final cleanColor = color.trim();
    final cleanSize = size.trim();
    if (cleanColor.isNotEmpty && cleanColor != '-') {
      parts.add(cleanColor);
    }
    if (cleanSize.isNotEmpty && cleanSize != '-') {
      parts.add('مقاس $cleanSize');
    }
    parts.add('سعر القطعة: ${Money(unitPrice).toDisplay()} ج.م');
    return parts.join(' • ');
  }

  String _formatHistoryVariantMeta(String color, String size) {
    final parts = <String>[];
    final cleanColor = color.trim();
    final cleanSize = size.trim();
    if (cleanColor.isNotEmpty && cleanColor != '-') {
      parts.add(cleanColor);
    }
    if (cleanSize.isNotEmpty && cleanSize != '-') {
      parts.add('مقاس $cleanSize');
    }
    if (parts.isEmpty) return '';
    return ' (${parts.join(' - ')})';
  }

  List<SaleEntity> _applyDateFilter(List<SaleEntity> sales) {
    if (_activeDateFilter == 'all') return sales;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    if (_activeDateFilter == 'today') {
      return sales.where((s) => !s.date.isBefore(todayStart)).toList();
    }
    if (_activeDateFilter == 'week') {
      final weekStart = todayStart.subtract(const Duration(days: 6));
      return sales.where((s) => !s.date.isBefore(weekStart)).toList();
    }
    if (_activeDateFilter == 'month') {
      final monthStart = DateTime(now.year, now.month, 1);
      return sales.where((s) => !s.date.isBefore(monthStart)).toList();
    }
    return sales;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final cubit = getIt<ReturnsCubit>()..init();
        if (widget.initialInvoiceRef != null &&
            widget.initialInvoiceRef!.trim().isNotEmpty) {
          cubit.searchSale(widget.initialInvoiceRef!.trim());
        }
        return cubit;
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: BlocConsumer<ReturnsCubit, ReturnsState>(
          listener: (context, state) {
            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage!),
                  backgroundColor: AppColors.error,
                ),
              );
            }
            if (state.successMessage != null) {
              _reasonCtrl.clear();
              _searchCtrl.clear();
              _imeiVerifyCtrl.clear();
              if (_isDialogOpen && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.success,
                  content: Text(state.successMessage!),
                ),
              );
            }
            if (state.selectedSale != null &&
                !_isDialogOpen &&
                _lastOpenedSaleId != state.selectedSale!.id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _openReturnDetailsDialog(context);
                }
              });
            }
          },
          builder: (context, state) {
            if (state.selectedSale != null &&
                !_isDialogOpen &&
                _lastOpenedSaleId != state.selectedSale!.id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _openReturnDetailsDialog(context);
                }
              });
            }

            return Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.f2) {
                  _searchFocus.requestFocus();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  if (_searchCtrl.text.isNotEmpty) {
                    _searchDebounce?.cancel();
                    _searchCtrl.clear();
                    setState(() {});
                    context.read<ReturnsCubit>().loadRecentSales();
                    return KeyEventResult.handled;
                  }
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: _activeTab == 0
                        ? _buildNewReturnTab(context, state)
                        : _buildReturnsHistoryTab(context, state),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final canPop = Navigator.canPop(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          if (canPop) ...[
            IconButton(
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.onSurface,
              ),
              tooltip: 'رجوع',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 4),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'إدارة مرتجعات المبيعات',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'إرجاع الأصناف، استرداد المبالغ للدرج، ومتابعة سجل الفواتير المرتجعة',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSegmentPill(
                  index: 0,
                  icon: Icons.assignment_return_rounded,
                  label: 'إجراء مرتجع جديد',
                ),
                const SizedBox(width: 4),
                _buildSegmentPill(
                  index: 1,
                  icon: Icons.receipt_long_rounded,
                  label: 'سجل فواتير المرتجعات',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentPill({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _activeTab == index;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        if (_activeTab != index) {
          setState(() => _activeTab = index);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: NEW RETURN (INVOICES-SCREEN STYLE FULL-WIDTH LIST)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNewReturnTab(BuildContext context, ReturnsState state) {
    final filteredSales = _applyDateFilter(state.recentSales);
    final now = DateTime.now();
    final todayRefundTotal = state.returnsHistory
        .where((r) =>
            r.date.year == now.year &&
            r.date.month == now.month &&
            r.date.day == now.day)
        .fold<int>(0, (sum, r) => sum + r.refundAmount);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Search & Date Filter Bar (Matching InvoicesScreen)
          LayoutBuilder(
            builder: (context, constraints) {
              final searchField = TextField(
                key: const Key('return_search_field'),
                controller: _searchCtrl,
                focusNode: _searchFocus,
                decoration: InputDecoration(
                  hintText:
                      'ابحث برقم الفاتورة (#S...) أو اسم العميل أو الموبايل... [F2]',
                  hintStyle: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.primary,
                  ),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchDebounce?.cancel();
                            _searchCtrl.clear();
                            setState(() {});
                            context.read<ReturnsCubit>().loadRecentSales();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                onChanged: (val) {
                  setState(() {});
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 250),
                    () {
                      if (mounted) {
                        context.read<ReturnsCubit>().searchSale(val);
                      }
                    },
                  );
                },
                onSubmitted: (val) {
                  _searchDebounce?.cancel();
                  context.read<ReturnsCubit>().searchSale(val);
                },
              );

              final dateChips = Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _dateFilterChip('الكل', 'all'),
                  _dateFilterChip('اليوم', 'today'),
                  _dateFilterChip('آخر 7 أيام', 'week'),
                  _dateFilterChip('هذا الشهر', 'month'),
                ],
              );

              if (constraints.maxWidth >= 880) {
                return Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 12),
                    dateChips,
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchField,
                  const SizedBox(height: 10),
                  dateChips,
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // Summary Stats Row (Matching InvoicesScreen)
          Row(
            key: const Key('returns_summary_cards'),
            children: [
              Expanded(
                child: _buildStatsCard(
                  'الفواتير المتاحة للمرتجع',
                  '${filteredSales.length} فاتورة',
                  Icons.receipt_long_rounded,
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildStatsCard(
                  'إجمالي المسترد اليوم',
                  '${Money(todayRefundTotal).toDisplay()} ج.م',
                  Icons.payments_outlined,
                  AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Full-Width Sales List
          Expanded(
            key: const Key('returns_full_width_list'),
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildSalesList(context, state, filteredSales),
          ),
        ],
      ),
    );
  }

  Widget _dateFilterChip(String label, String value) {
    final active = _activeDateFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: active ? FontWeight.bold : FontWeight.w500,
          color: active ? Colors.white : AppColors.onSurface,
        ),
      ),
      selected: active,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceContainerLowest,
      side: BorderSide(
        color: active ? AppColors.primary : AppColors.outlineVariant,
      ),
      onSelected: (_) => setState(() => _activeDateFilter = value),
    );
  }

  Widget _buildStatsCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesList(
    BuildContext context,
    ReturnsState state,
    List<SaleEntity> sales,
  ) {
    if (state.errorMessage != null && state.recentSales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 54, color: AppColors.error),
            const SizedBox(height: 10),
            Text(
              state.errorMessage!,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () => context.read<ReturnsCubit>().loadRecentSales(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (sales.isEmpty) {
      final hasQuery = _searchCtrl.text.trim().isNotEmpty;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasQuery
                  ? Icons.search_off_rounded
                  : Icons.receipt_long_outlined,
              size: 54,
              color: AppColors.outline,
            ),
            const SizedBox(height: 12),
            Text(
              hasQuery
                  ? 'لا توجد فواتير قابلة للإرجاع مطابقة لـ "${_searchCtrl.text.trim()}"'
                  : 'لا توجد فواتير بيع قابلة للإرجاع في هذه الفترة',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 15.5,
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'الفواتير المرتجعة بالكامل لا تظهر هنا منعاً للتكرار، ويمكنك مراجعتها في سجل المرتجعات.',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (hasQuery || _activeDateFilter != 'all') ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {
                  _searchDebounce?.cancel();
                  _searchCtrl.clear();
                  setState(() => _activeDateFilter = 'all');
                  context.read<ReturnsCubit>().loadRecentSales();
                },
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('مسح التصفية وعرض جميع الفواتير'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: sales.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final sale = sales[index];
        return _buildSaleRowCard(context, sale);
      },
    );
  }

  Widget _buildSaleRowCard(BuildContext context, SaleEntity sale) {
    final dateStr = _dateFormat.format(sale.date);
    final refDisplay = (sale.shortRef != null && sale.shortRef!.isNotEmpty)
        ? sale.shortRef!
        : (sale.id.length > 8 ? sale.id.substring(0, 8) : sale.id);
    final custLabel = (sale.customerName != null &&
            sale.customerName!.isNotEmpty)
        ? '${sale.customerName}${sale.customerPhone != null && sale.customerPhone!.isNotEmpty ? ' (${sale.customerPhone})' : ''}'
        : 'عميل نقدي';

    return Card(
      elevation: 0,
      color: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.outlineVariant),
      ),
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.read<ReturnsCubit>().selectSale(sale),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'فاتورة #$refDisplay',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            custLabel,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _formatPayment(sale.paymentMethod),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'التاريخ: $dateStr',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${Money(sale.total).toDisplay()} ج.م',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => context.read<ReturnsCubit>().selectSale(sale),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.assignment_return_rounded, size: 16),
                label: const Text(
                  'استرجاع سريع',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: RETURNS HISTORY
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildReturnsHistoryTab(BuildContext context, ReturnsState state) {
    final q = _historyQuery.trim().toLowerCase().replaceFirst(RegExp(r'^#'), '');
    final numVal = double.tryParse(q.replaceAll(',', ''));
    final filtered = q.isEmpty
        ? state.returnsHistory
        : state.returnsHistory.where((ret) {
            final matchAmount = numVal != null &&
                ((ret.refundAmount == (numVal * 100).round()) ||
                    (ret.refundAmount.toString() == q) ||
                    ((ret.refundAmount / 100).toStringAsFixed(2).contains(q)) ||
                    ((ret.refundAmount / 100).toString().contains(q)));
            return ret.id.toLowerCase().contains(q) ||
                (ret.saleShortRef?.toLowerCase().contains(q) ?? false) ||
                (ret.customerName?.toLowerCase().contains(q) ?? false) ||
                (ret.customerPhone?.toLowerCase().contains(q) ?? false) ||
                ret.reason.toLowerCase().contains(q) ||
                matchAmount;
          }).toList();

    final now = DateTime.now();
    final todayReturns = state.returnsHistory
        .where((r) =>
            r.date.year == now.year &&
            r.date.month == now.month &&
            r.date.day == now.day)
        .toList();
    final todayRefundTotal =
        todayReturns.fold<int>(0, (sum, r) => sum + r.refundAmount);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            key: const Key('returns_history_summary_cards'),
            children: [
              Expanded(
                child: _buildStatsCard(
                  'مرتجعات اليوم',
                  '${todayReturns.length}',
                  Icons.assignment_return_rounded,
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildStatsCard(
                  'إجمالي المسترد اليوم',
                  '${Money(todayRefundTotal).toDisplay()} ج.م',
                  Icons.payments_outlined,
                  AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _historySearchCtrl,
            decoration: InputDecoration(
              hintText:
                  'ابحث في سجل المرتجعات برقم الفاتورة، المبلغ، اسم العميل، الهاتف، أو السبب...',
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary),
              suffixIcon: _historyQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _historySearchCtrl.clear();
                        setState(() => _historyQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surfaceContainerLowest,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.outlineVariant),
              ),
            ),
            onChanged: (val) => setState(() => _historyQuery = val),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: filtered.isEmpty
                ? RefreshIndicator(
                    onRefresh: () =>
                        context.read<ReturnsCubit>().loadReturnsHistory(),
                    child: ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.4,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.assignment_return_outlined,
                                  size: 56,
                                  color: AppColors.outline,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  q.isNotEmpty
                                      ? 'لا توجد مرتجعات مطابقة للبحث "$_historyQuery"'
                                      : 'لا توجد فواتير مرتجعات مسجلة حتى الآن',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                if (q.isEmpty) ...[
                                  const SizedBox(height: 6),
                                  const Text(
                                    'عند تنفيذ أي عملية إرجاع ستظهر تفاصيلها وسجلها هنا تلقائياً',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: AppColors.onSurfaceVariant,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () =>
                        context.read<ReturnsCubit>().loadReturnsHistory(),
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        return _buildReturnHistoryCard(filtered[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnHistoryCard(ReturnEntity ret) {
    final dateStr = _dateFormat.format(ret.date);
    final isCash = ret.paymentMethod.toLowerCase().contains('cash') ||
        ret.paymentMethod.contains('كاش');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: ExpansionTile(
        shape: const Border(),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.assignment_return_rounded,
            color: AppColors.error,
          ),
        ),
        title: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'مرتجع #${ret.id.length > 8 ? ret.id.substring(0, 8) : ret.id}',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
                color: AppColors.onSurface,
              ),
            ),
            if (ret.saleShortRef != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'فاتورة الأصل: #${ret.saleShortRef}',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (ret.customerName != null && ret.customerName!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${ret.customerName}${ret.customerPhone != null && ret.customerPhone!.isNotEmpty ? ' • ${ret.customerPhone}' : ''}',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: AppColors.onSurface,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text(
              '-${Money(ret.refundAmount).toDisplay()} ج.م',
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                dateStr,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              Text(
                'بواسطة: ${ret.cashierName ?? ret.cashierId}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  color: AppColors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: (isCash ? AppColors.success : AppColors.primary)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isCash ? 'مسترد نقداً (خصم من الدرج)' : 'مسترد إلكتروني',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isCash ? AppColors.success : AppColors.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'سبب المرتجع: ${ret.reason}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'الأصناف المرتجعة للمخزن:',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                ...ret.items.map((it) {
                  final meta = _formatHistoryVariantMeta(it.color, it.size);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '• ${it.productName}$meta × ${it.qty} قطعة',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: AppColors.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '${Money(it.refundUnitPrice * it.qty).toDisplay()} ج.م',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReturnDetailsDialog extends StatefulWidget {
  final TextEditingController reasonCtrl;
  final TextEditingController imeiVerifyCtrl;
  final bool mobileImeiEnabled;
  final List<String> quickReasons;
  final DateFormat dateFormat;
  final String Function(String) formatPayment;
  final String Function(String, String, int) formatVariantSubtitle;
  final Future<void> Function(BuildContext, ReturnsState) onSubmit;

  const _ReturnDetailsDialog({
    required this.reasonCtrl,
    required this.imeiVerifyCtrl,
    required this.mobileImeiEnabled,
    required this.quickReasons,
    required this.dateFormat,
    required this.formatPayment,
    required this.formatVariantSubtitle,
    required this.onSubmit,
  });

  @override
  State<_ReturnDetailsDialog> createState() => _ReturnDetailsDialogState();
}

class _ReturnDetailsDialogState extends State<_ReturnDetailsDialog> {
  void _returnFullInvoice(BuildContext context, ReturnsState state) {
    final cubit = context.read<ReturnsCubit>();
    for (final item in state.returnItems) {
      if (item.maxQty > 0 && item.qty < item.maxQty) {
        cubit.updateItemQty(item.variantId, item.maxQty);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReturnsCubit, ReturnsState>(
      builder: (context, state) {
        final sale = state.selectedSale;
        if (sale == null) {
          return const SizedBox.shrink();
        }
        final dateStr = widget.dateFormat.format(sale.date);
        final refDisplay =
            (sale.shortRef != null && sale.shortRef!.isNotEmpty)
                ? sale.shortRef!
                : (sale.id.length > 8 ? sale.id.substring(0, 8) : sale.id);
        final custDisplay = (sale.customerName != null &&
                sale.customerName!.isNotEmpty)
            ? '${sale.customerName}${sale.customerPhone != null && sale.customerPhone!.isNotEmpty ? ' (${sale.customerPhone})' : ''}'
            : 'عميل نقدي';

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f12): () {
              if (!state.isProcessing && state.totalRefund > 0) {
                widget.onSubmit(context, state);
              }
            },
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: Dialog(
            key: const Key('return_details_dialog'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dialog Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      border: Border(
                        bottom: BorderSide(color: AppColors.outlineVariant),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.assignment_return_rounded,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تفاصيل المرتجع — فاتورة #$refDisplay',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15.5,
                                  color: AppColors.onSurface,
                                ),
                              ),
                              Text(
                                '$custDisplay • $dateStr • ${widget.formatPayment(sale.paymentMethod)} • الإجمالي: ${Money(sale.total).toDisplay()} ج.م',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11.5,
                                  color: AppColors.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _returnFullInvoice(context, state),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                          child: Text(
                            'استرجاع الفاتورة بالكامل',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'إغلاق [Esc]',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),

                  // Scrollable Items
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: state.returnItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = state.returnItems[index];
                        final isFullyReturned = item.maxQty == 0;
                        final subtitleText = widget.formatVariantSubtitle(
                          item.color,
                          item.size,
                          item.refundUnitPrice,
                        );

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isFullyReturned
                                ? AppColors.surfaceContainer
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: isFullyReturned
                                  ? AppColors.error.withValues(alpha: 0.35)
                                  : (item.qty > 0
                                      ? AppColors.primary
                                          .withValues(alpha: 0.45)
                                      : AppColors.outlineVariant),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName.isNotEmpty
                                          ? item.productName
                                          : item.variantId,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                        color: isFullyReturned
                                            ? AppColors.onSurfaceVariant
                                            : AppColors.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitleText,
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (isFullyReturned)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.error
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'تم إرجاع هذا الصنف بالكامل سابقاً',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 11,
                                            color: AppColors.error,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      )
                                    else
                                      Text(
                                        'الكمية المتاحة للإرجاع: ${item.maxQty}',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (!isFullyReturned) ...[
                                const SizedBox(width: 12),
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.outlineVariant,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        constraints: const BoxConstraints(
                                          minWidth: 34,
                                          minHeight: 34,
                                        ),
                                        padding: EdgeInsets.zero,
                                        icon: Icon(
                                          Icons.remove_rounded,
                                          size: 18,
                                          color: item.qty > 0
                                              ? AppColors.primary
                                              : AppColors.outline,
                                        ),
                                        onPressed: item.qty > 0
                                            ? () => context
                                                .read<ReturnsCubit>()
                                                .updateItemQty(
                                                    item.variantId, item.qty - 1)
                                            : null,
                                      ),
                                      SizedBox(
                                        width: 30,
                                        child: Text(
                                          '${item.qty}',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.onSurface,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        constraints: const BoxConstraints(
                                          minWidth: 34,
                                          minHeight: 34,
                                        ),
                                        padding: EdgeInsets.zero,
                                        icon: Icon(
                                          Icons.add_rounded,
                                          size: 18,
                                          color: item.qty < item.maxQty
                                              ? AppColors.primary
                                              : AppColors.outline,
                                        ),
                                        onPressed: item.qty < item.maxQty
                                            ? () => context
                                                .read<ReturnsCubit>()
                                                .updateItemQty(
                                                    item.variantId, item.qty + 1)
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 92,
                                  child: Text(
                                    '${Money(item.lineTotal).toDisplay()} ج.م',
                                    textAlign: TextAlign.left,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                      color: item.qty > 0
                                          ? AppColors.primary
                                          : AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Footer
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainer,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(16),
                      ),
                      border: Border(
                        top: BorderSide(color: AppColors.outlineVariant),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.mobileImeiEnabled) ...[
                          TextField(
                            key: const Key('return_imei_verify_field'),
                            controller: widget.imeiVerifyCtrl,
                            decoration: InputDecoration(
                              labelText:
                                  'تأكيد رقم IMEI للجهاز المرتجع (للأجهزة المتسلسلة)',
                              prefixIcon:
                                  const Icon(Icons.qr_code_scanner_rounded),
                              filled: true,
                              fillColor: AppColors.surfaceContainerLowest,
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              hintText:
                                  'امسح أو أدخل رقم الـ IMEI لمطابقة الجهاز المباع',
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'سبب سريع:',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            for (final reason in widget.quickReasons)
                              ActionChip(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    AppColors.surfaceContainerLowest,
                                side:
                                    BorderSide(color: AppColors.outlineVariant),
                                label: Text(
                                  reason,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11.5,
                                    color: AppColors.onSurface,
                                  ),
                                ),
                                onPressed: () {
                                  setState(() {
                                    widget.reasonCtrl.text = reason;
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: widget.reasonCtrl,
                          decoration: InputDecoration(
                            labelText: 'سبب الإرجاع (مطلوب) *',
                            filled: true,
                            fillColor: AppColors.surfaceContainerLowest,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            hintText:
                                'مثال: عيب صناعة، مقاس/نوع غير مناسب، رغبة العميل',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Flexible(
                                      child: Text(
                                        'إجمالي المسترد:',
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppColors.onSurface,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${Money(state.totalRefund).toDisplay()} ج.م',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'إلغاء [Esc]',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 46,
                              child: ElevatedButton.icon(
                                key: const Key('return_confirm_btn'),
                                onPressed: state.isProcessing ||
                                        state.totalRefund == 0
                                    ? null
                                    : () => widget.onSubmit(context, state),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: state.isProcessing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.assignment_return_rounded,
                                        size: 18,
                                      ),
                                label: Text(
                                  state.isProcessing
                                      ? 'جارِ المعالجة...'
                                      : 'تأكيد وإتمام المرتجع [F12]',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
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
}
