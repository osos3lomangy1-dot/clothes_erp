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
  const OfflineSmartAssistantDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const OfflineSmartAssistantDialog(),
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
      final res = await _resolveService().ask(trimmed);
      if (!mounted) return;
      setState(() {
        _history.add(
          _AssistantChatEntry(userPrompt: trimmed, insights: res),
        );
        _queryCtrl.clear();
        _isLoading = false;
      });
      _scrollToLatest();
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

  @override
  Widget build(BuildContext context) {
    const quickPrompts = [
      'وضع المحل دلوقتي؟',
      'المبيعات قليلة ليه؟',
      'أعمل عروض على إيه؟',
      'صافي ربح اليوم ومقارنته بأمس',
      'أعلى 5 أصناف ربحاً',
      'الأقساط المتأخرة',
      'مستحقات الموردين',
    ];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'المساعد التحليلي الذكي (أوفلاين)',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: 660,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('smart_assistant_query_field'),
                      controller: _queryCtrl,
                      onSubmitted: _runQuery,
                      decoration: const InputDecoration(
                        hintText:
                            'اسأل بالعامية أو اطلب تنفيذ إعداد أو ابحث عن صنف...',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const Key('smart_assistant_ask_btn'),
                    onPressed: () => _runQuery(_queryCtrl.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('تحليل'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final prompt in quickPrompts)
                    ActionChip(
                      label: Text(prompt, style: const TextStyle(fontSize: 11.5)),
                      onPressed: () => _runQuery(prompt),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading && _history.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        controller: _scrollCtrl,
                        itemCount: _history.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
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
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      entry.userPrompt!,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              if (entry.headerLabel != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    entry.headerLabel!,
                                    key: const Key('smart_assistant_briefing_header'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              for (final item in entry.insights)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.summary,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          color: item.isAlert
                                              ? AppColors.warning
                                              : AppColors.primary,
                                        ),
                                      ),
                                      if (item.details.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        for (final line in item.details)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              '• $line',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                      ],
                                      if (item.pendingCommand != null &&
                                          !_resolvedCommands.contains(item)) ...[
                                        const SizedBox(height: 10),
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
                                              ),
                                              child: const Text('تأكيد التعديل'),
                                            ),
                                            const SizedBox(width: 8),
                                            OutlinedButton(
                                              key: Key(
                                                'assistant_cancel_${item.id}',
                                              ),
                                              onPressed: () =>
                                                  _cancelCommand(item),
                                              child: const Text('إلغاء'),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (_canNavigate(item) &&
                                          item.actionLabel != null) ...[
                                        const SizedBox(height: 8),
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
                                              size: 15,
                                            ),
                                            label: Text(item.actionLabel!),
                                          ),
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
            ],
          ),
        ),
      ),
    );
  }
}
