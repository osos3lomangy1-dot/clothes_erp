import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../auth/presentation/widgets/manager_auth_dialog.dart';
import '../../../employees/presentation/screens/employee_list_screen.dart';
import '../../../expenses/presentation/screens/expenses_screen.dart';
import '../../../installments/presentation/screens/installments_list_screen.dart';
import '../../../invoices/presentation/screens/receipt_customizer_screen.dart';
import '../../../partners/presentation/screens/partners_screen.dart';
import '../../../products/presentation/screens/product_list_screen.dart';
import '../../../purchases/presentation/screens/purchases_screen.dart';
import '../../../reports/presentation/screens/reports_screen.dart';
import '../../../returns/presentation/screens/return_screen.dart';
import '../../../settings/presentation/screens/excel_migration_screen.dart';
import '../../../settings/presentation/screens/system_settings_screen.dart';
import '../../../shifts/presentation/screens/shift_screen.dart';
import '../../data/services/offline_smart_assistant_service.dart';

class _AssistantChatEntry {
  final String? userPrompt;
  final String? headerLabel;
  final List<AssistantInsight> insights;

  const _AssistantChatEntry({
    this.userPrompt,
    this.headerLabel,
    required this.insights,
  });
}

class OfflineSmartAssistantDialog extends StatefulWidget {
  final bool isBottomSheet;
  final String? currentScreenTitle;

  const OfflineSmartAssistantDialog({
    super.key,
    this.isBottomSheet = false,
    this.currentScreenTitle,
  });

  static Future<void> show(
    BuildContext context, {
    String? currentScreenTitle,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth < 600) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.88,
          child: OfflineSmartAssistantDialog(
            isBottomSheet: true,
            currentScreenTitle: currentScreenTitle,
          ),
        ),
      );
    }

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'إغلاق المساعد الذكي',
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) {
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 68, right: 20),
              child: Material(
                color: Colors.transparent,
                child: OfflineSmartAssistantDialog(
                  currentScreenTitle: currentScreenTitle,
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<OfflineSmartAssistantDialog> createState() =>
      _OfflineSmartAssistantDialogState();
}

class _OfflineSmartAssistantDialogState
    extends State<OfflineSmartAssistantDialog> {
  final _queryCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_AssistantChatEntry> _history = [];
  final Set<AssistantInsight> _resolvedCommands =
      Set<AssistantInsight>.identity();
  Map<String, bool> _enabledFeatures = const {};
  bool _isLoading = true;
  String _selectedCategory = 'all';
  AssistantActionDraft? _activeDraft;
  bool _instantAdminMode = false;
  String? _lastBarcodeProductName;

  bool _isCurrentUserAdmin() {
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        return authState.user.role.toLowerCase() == 'admin';
      }
    } catch (_) {}
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadInitialBriefing();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(0);
      }
    });
  }

  OfflineSmartAssistantService _resolveService() {
    if (getIt.isRegistered<OfflineSmartAssistantService>()) {
      return getIt<OfflineSmartAssistantService>();
    }
    return OfflineSmartAssistantService(getIt<AppDatabase>());
  }

  Future<void> _loadInitialBriefing() async {
    try {
      if (getIt.isRegistered<FeatureGate>()) {
        _enabledFeatures = await getIt<FeatureGate>().getFeatures();
      }
    } catch (_) {}

    try {
      final briefing = await _resolveService().getDailyBriefing();
      if (!mounted) return;
      setState(() {
        _history.add(
          _AssistantChatEntry(
            headerLabel: 'الملخص التنفيذي اليومي التلقائي (Daily Smart Briefing)',
            insights: briefing,
          ),
        );
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final turn = await _resolveService().askWithDraft(
        trimmed,
        activeDraft: _activeDraft,
      );
      if (!mounted) return;
      setState(() {
        _activeDraft = turn.activeDraft;
        for (final ins in turn.insights) {
          if (ins.id == 'barcode_lookup') {
            _lastBarcodeProductName = ins.summary.split(' — ').first.trim();
          }
        }
        _history.add(
          _AssistantChatEntry(userPrompt: trimmed, insights: turn.insights),
        );
        _queryCtrl.clear();
        _isLoading = false;
      });
      _scrollToLatest();

      if (_instantAdminMode &&
          _isCurrentUserAdmin() &&
          turn.insights.length == 1 &&
          turn.insights.first.pendingCommand != null) {
        await _confirmCommand(turn.insights.first);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmCommand(AssistantInsight item) async {
    final cmd = item.pendingCommand;
    if (cmd == null) return;

    String userId = 'admin';
    String userRole = 'admin';
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        userId = authState.user.id;
        userRole = authState.user.role;
      }
    } catch (_) {}

    if (userRole.toLowerCase() != 'admin') {
      setState(() {
        _resolvedCommands.add(item);
        _history.add(
          const _AssistantChatEntry(
            insights: [
              AssistantInsight(
                id: 'cmd_denied',
                title: 'تنفيذ مرفوض (صلاحيات)',
                summary:
                    'غير مصرح: تنفيذ تعديلات الإعدادات متاح لحساب المدير (admin) فقط.',
                isAlert: true,
              ),
            ],
          ),
        );
      });
      _scrollToLatest();
      return;
    }

    if (!getIt.isRegistered<FeatureGate>()) return;
    final gate = getIt<FeatureGate>();

    if (cmd.touchesFeatureGate) {
      final unlocked = await ManagerAuthHelper.ensureSuperAdminUnlocked(
        context,
        gate: gate,
        actionLabel: cmd.title,
      );
      if (!unlocked || !mounted) return;
    }

    try {
      final msg = await _resolveService().executeCommand(
        cmd,
        userId: userId,
        userRole: userRole,
        gate: gate,
      );
      if (!mounted) return;
      setState(() {
        _resolvedCommands.add(item);
        _history.add(
          _AssistantChatEntry(
            insights: [
              AssistantInsight(
                id: 'cmd_success',
                title: 'تم تنفيذ التعديل بنجاح',
                summary: msg,
              ),
            ],
          ),
        );
      });
      _scrollToLatest();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolvedCommands.add(item);
        _history.add(
          _AssistantChatEntry(
            insights: [
              AssistantInsight(
                id: 'cmd_error',
                title: 'تعذر تنفيذ التعديل',
                summary: e.toString().replaceFirst('Exception: ', ''),
                isAlert: true,
              ),
            ],
          ),
        );
      });
      _scrollToLatest();
    }
  }

  void _cancelCommand(AssistantInsight item) {
    setState(() {
      _resolvedCommands.add(item);
      _history.add(
        const _AssistantChatEntry(
          insights: [
            AssistantInsight(
              id: 'cmd_cancelled',
              title: 'تم إلغاء التعديل',
              summary: 'لم يتم إجراء أي تغيير على إعدادات النظام.',
            ),
          ],
        ),
      );
    });
    _scrollToLatest();
  }

  bool _canNavigate(AssistantInsight item) {
    if (item.actionRoute == null) return false;
    final key = item.requiredFeatureKey;
    if (key == null) return true;
    if (!getIt.isRegistered<FeatureGate>()) return true;
    return _enabledFeatures[key] ?? false;
  }

  void _navigateToRoute(AssistantActionRoute route) {
    final Widget screen;
    switch (route) {
      case AssistantActionRoute.reports:
        screen = const ReportsScreen();
        break;
      case AssistantActionRoute.products:
        screen = const ProductListScreen();
        break;
      case AssistantActionRoute.purchases:
        screen = const PurchasesScreen();
        break;
      case AssistantActionRoute.installments:
        screen = const InstallmentsListScreen();
        break;
      case AssistantActionRoute.expenses:
        screen = const ExpensesScreen();
        break;
      case AssistantActionRoute.settings:
        screen = const SystemSettingsScreen();
        break;
      case AssistantActionRoute.employees:
        screen = const EmployeeListScreen();
        break;
      case AssistantActionRoute.shifts:
        screen = const ShiftScreen();
        break;
      case AssistantActionRoute.partners:
        screen = const PartnersScreen();
        break;
      case AssistantActionRoute.excelMigration:
        screen = const ExcelMigrationScreen(userId: 'admin');
        break;
      case AssistantActionRoute.receiptCustomizer:
        screen = const ReceiptCustomizerScreen();
        break;
      case AssistantActionRoute.returns:
        screen = const ReturnScreen();
        break;
    }
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _resetChat() {
    setState(() {
      _history.clear();
      _resolvedCommands.clear();
      _isLoading = true;
    });
    _loadInitialBriefing();
  }

  List<String> _contextPromptsFor(String? title) {
    if (title == null || title.trim().isEmpty) return const [];
    final t = OfflineSmartAssistantService.normalizeArabic(title);
    if (t.contains('منتجات') || t.contains('مخزون') || t.contains('اصناف')) {
      return const [
        'الأصناف قاربت تخلص',
        'عدل سعر ',
        'اكتر مقاس ولون بيتباع في ',
        'ارخص مورد جبت منه ',
      ];
    }
    if (t.contains('تقسيط') || t.contains('اقساط')) {
      return const [
        'الأقساط المتأخرة',
        'تحصيل قسط ',
        'اكتب رسالة تذكير قسط لـ ',
      ];
    }
    if (t.contains('مشتريات')) {
      return const [
        'ارخص مورد جبت منه ',
        'مستحقات الموردين',
        'دفعت للمورد ',
      ];
    }
    if (t.contains('مبيعات') || t.contains('فواتير') || t.contains('كاشير')) {
      return const [
        'تقرير قفلة اليوم',
        'اكتر يوم وساعة زحمة',
        'ايه اللي اتعدل النهارده',
      ];
    }
    if (t.contains('مرتجع')) {
      return const [
        'ايه اللي اتعدل النهارده',
        'المبيعات قليلة ليه؟',
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    const categorizedPrompts = <String, List<String>>{
      'analytics': [
        'وضع المحل دلوقتي؟',
        'الأقساط المتأخرة',
        'استشارة بزنس مان',
        'تقييم صحة المحل',
        'جهز طلبية الشراء',
        'صافي ربح اليوم ومقارنته بأمس',
        'نقطة التعادل اليومية',
        'كاشف تسرب الأرباح',
        'أداء الكاشيرات',
        'المبيعات قليلة ليه؟',
        'الأصناف الراكدة',
        'أعلى 5 أصناف ربحاً',
        'مستحقات الموردين',
      ],
      'marketing': [
        'العميل بيقول غالي',
        'اكتب بوست واتساب',
        'اكتب بوست باقة فيسبوك',
        'اكتب بوست كولكشن جديد انستا',
        'استرجع العملاء الغائبين',
        'خطة تسويق لزيادة المبيعات',
        'أعمل عروض على إيه؟',
        'ترتيب المحل وعرض البضاعة',
      ],
      'pricing': [
        'عايز اكسب 30000',
        'حاسبة الزكاة',
        'لو عملت خصم 15% أحتاج أبيع كام؟',
        'حاسبة التضخم 20%',
        'توزيع السيولة 50/30/20',
        'الخصم أم الباقة والهدية؟',
      ],
    };

    final quickPrompts = _selectedCategory == 'all'
        ? [
            ...categorizedPrompts['analytics']!,
            ...categorizedPrompts['marketing']!,
            ...categorizedPrompts['pricing']!,
          ]
        : categorizedPrompts[_selectedCategory]!;

    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final containerWidth = widget.isBottomSheet ? double.infinity : 390.0;
    final containerHeight =
        widget.isBottomSheet ? maxHeight : (maxHeight < 560 ? maxHeight : 560.0);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Container(
        key: const Key('smart_assistant_popover'),
        width: containerWidth,
        height: containerHeight,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: widget.isBottomSheet
              ? const BorderRadius.vertical(top: Radius.circular(20))
              : BorderRadius.circular(18),
          border: Border.all(color: AppColors.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Gradient Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'المساعد التحليلي الذكي (أوفلاين)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'أوفلاين 100%',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (_isCurrentUserAdmin()) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'تنفيذ فوري للمدير بدون ضغط زر التأكيد',
                      child: InkWell(
                        key: const Key('assistant_instant_mode_toggle'),
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => setState(
                          () => _instantAdminMode = !_instantAdminMode,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _instantAdminMode
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'تنفيذ فوري',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: _instantAdminMode
                                  ? AppColors.primary
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 2),
                  IconButton(
                    key: const Key('smart_assistant_reset_btn'),
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: 'بدء محادثة جديدة',
                    onPressed: _resetChat,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ],
              ),
            ),

            // Context-Aware Screen Prompts (Batch 3)
            if (_contextPromptsFor(widget.currentScreenTitle).isNotEmpty)
              Container(
                key: const Key('assistant_context_prompts'),
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  border: Border(
                    bottom: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        '${widget.currentScreenTitle}:',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      for (final cp
                          in _contextPromptsFor(widget.currentScreenTitle)) ...[
                        ActionChip(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: AppColors.surfaceContainerLowest,
                          side: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.35),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          label: Text(
                            cp.trim(),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          onPressed: () {
                            if (cp.endsWith(' ')) {
                              _queryCtrl.text = cp;
                              _queryCtrl.selection = TextSelection.fromPosition(
                                TextPosition(offset: cp.length),
                              );
                            } else {
                              _runQuery(cp);
                            }
                          },
                        ),
                        const SizedBox(width: 5),
                      ],
                    ],
                  ),
                ),
              ),

            // Category Filter Tabs + Quick Prompt Chips
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final cat in const [
                          ('all', 'الكل'),
                          ('analytics', 'تحليل المحل'),
                          ('marketing', 'تسويق وبوستات'),
                          ('pricing', 'تسعير وموسوعة'),
                        ]) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                cat.$2,
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10.5,
                                  fontWeight: _selectedCategory == cat.$1
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _selectedCategory == cat.$1
                                      ? Colors.white
                                      : AppColors.onSurface,
                                ),
                              ),
                              selected: _selectedCategory == cat.$1,
                              selectedColor: AppColors.primary,
                              backgroundColor:
                                  AppColors.surfaceContainerLowest,
                              side: BorderSide(
                                color: _selectedCategory == cat.$1
                                    ? AppColors.primary
                                    : AppColors.outlineVariant,
                              ),
                              onSelected: (_) =>
                                  setState(() => _selectedCategory = cat.$1),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < quickPrompts.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          ActionChip(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: AppColors.surfaceContainerLowest,
                            side: BorderSide(color: AppColors.outlineVariant),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            label: Text(
                              quickPrompts[i],
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                color: AppColors.onSurface,
                              ),
                            ),
                            onPressed: () => _runQuery(quickPrompts[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Chat Messages Feed
            Expanded(
              child: _isLoading && _history.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: _history.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, idx) {
                        final entry = _history[_history.length - 1 - idx];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (entry.userPrompt != null)
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    entry.userPrompt!,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ),
                            if (entry.headerLabel != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  entry.headerLabel!,
                                  key: const Key(
                                    'smart_assistant_briefing_header',
                                  ),
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            for (final item in entry.insights)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (item.isAlert
                                            ? AppColors.warning
                                            : AppColors.primary)
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      item.summary,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: item.isAlert
                                            ? AppColors.warning
                                            : AppColors.primary,
                                      ),
                                    ),
                                    if (item.details.isNotEmpty) ...[ 
                                      const SizedBox(height: 5),
                                      for (final line in item.details)
                                        _buildDetailLine(
                                          context,
                                          line,
                                          isPost: item.id.startsWith(
                                                'promo_post',
                                              ) ||
                                              item.id.startsWith(
                                                'customer_re_engagement',
                                              ) ||
                                              item.id.startsWith(
                                                'installment_reminder',
                                              ) ||
                                              item.id.startsWith(
                                                'customer_objection_replies',
                                              ),
                                          isSuggestion:
                                              item.id == 'no_direct_match',
                                        ),
                                    ],
                                    if (item.pendingCommand != null &&
                                        !_resolvedCommands.contains(item)) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          ElevatedButton(
                                            key: Key(
                                              'assistant_confirm_${item.id}',
                                            ),
                                            onPressed: () =>
                                                _confirmCommand(item),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.primary,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                            ),
                                            child: const Text(
                                              'تنفيذ الآن',
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          OutlinedButton(
                                            key: Key(
                                              'assistant_cancel_${item.id}',
                                            ),
                                            onPressed: () =>
                                                _cancelCommand(item),
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                            ),
                                            child: const Text(
                                              'إلغاء',
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (_canNavigate(item) &&
                                        item.actionLabel != null) ...[
                                      const SizedBox(height: 6),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          key: Key(
                                            'assistant_action_${item.id}',
                                          ),
                                          onPressed: () => _navigateToRoute(
                                            item.actionRoute!,
                                          ),
                                          icon: const Icon(
                                            Icons.open_in_new_rounded,
                                            size: 14,
                                          ),
                                          label: Text(
                                            item.actionLabel!,
                                            style: const TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (item.id == 'eod_report') ...[
                                      const SizedBox(height: 6),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                          key: const Key(
                                            'assistant_copy_eod_btn',
                                          ),
                                          onPressed: () {
                                            final text = [
                                              item.title,
                                              item.summary,
                                              ...item.details,
                                            ].join('\n');
                                            Clipboard.setData(
                                              ClipboardData(text: text),
                                            );
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'تم نسخ تقرير قفلة اليوم للواتساب',
                                                  style: TextStyle(
                                                    fontFamily: 'Cairo',
                                                  ),
                                                ),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.copy_rounded,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'نسخ لواتساب',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (item.followUpPrompts.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          for (final nextPrompt
                                              in item.followUpPrompts)
                                            ActionChip(
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              backgroundColor: AppColors.primary
                                                  .withValues(alpha: 0.08),
                                              side: BorderSide(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.25),
                                              ),
                                              label: Text(
                                                nextPrompt,
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 10.5,
                                                  color: AppColors.primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              onPressed: () {
                                                if (nextPrompt == 'عدل السعر' &&
                                                    _lastBarcodeProductName !=
                                                        null) {
                                                  _runQuery(
                                                    'عدل سعر $_lastBarcodeProductName',
                                                  );
                                                } else if (nextPrompt ==
                                                        'زود الرصيد' &&
                                                    _lastBarcodeProductName !=
                                                        null) {
                                                  _runQuery(
                                                    'زود رصيد $_lastBarcodeProductName',
                                                  );
                                                } else {
                                                  _runQuery(nextPrompt);
                                                }
                                              },
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),

            // Bottom Input Bar (Submits on Enter)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('smart_assistant_query_field'),
                      controller: _queryCtrl,
                      onSubmitted: _runQuery,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                      decoration: InputDecoration(
                        hintText:
                            'اسأل بالعامية أو اطلب تنفيذ إعداد أو ابحث عن صنف...',
                        hintStyle: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceContainerLowest,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: AppColors.outlineVariant),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 38,
                    child: ElevatedButton(
                      key: const Key('smart_assistant_ask_btn'),
                      onPressed: () => _runQuery(_queryCtrl.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'تحليل',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
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
  }

  /// Renders one detail line.
  /// * [isPost]: Shows a copy button for post/ad/message content lines.
  /// * [isSuggestion]: Renders clickable chips for "did you mean" suggestions.
  Widget _buildDetailLine(
    BuildContext context,
    String line, {
    bool isPost = false,
    bool isSuggestion = false,
  }) {
    // Detect if this detail line is an actual post body (contains ---\n)
    final isPostBody = isPost && line.contains('---\n');

    if (isSuggestion) {
      // Strip bullet if present
      final label = line.startsWith('• ') ? line.substring(2) : line;
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ActionChip(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          backgroundColor: AppColors.primary.withValues(alpha: 0.08),
          side: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.3),
          ),
          label: Text(
            label,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              color: AppColors.primary,
            ),
          ),
          onPressed: () => _runQuery(label),
        ),
      );
    }

    if (isPostBody) {
      // Split "بوست واتساب | هامش الربح الأصلي: 30%\n---\nنص الإعلان"
      final parts = line.split('\n---\n');
      final header = parts[0].trim();
      final body =
          parts.length > 1 ? parts.sublist(1).join('\n---\n').trim() : line;

      return Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with platform label + copy button
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      header,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: body));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'تم نسخ البوست — الصقه في واتساب أو فيسبوك مباشرةً',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'نسخ',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Post body text — selectable for manual copy too
            Padding(
              padding: const EdgeInsets.all(10),
              child: SelectableText(
                body,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  color: AppColors.onSurface,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Default: plain bullet line
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '• $line',
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11.5,
          color: AppColors.onSurface,
        ),
      ),
    );
  }
}
