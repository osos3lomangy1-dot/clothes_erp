import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../data/services/offline_smart_assistant_service.dart';

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
  List<AssistantInsight> _insights = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _runQuery('');
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  OfflineSmartAssistantService _resolveService() {
    if (getIt.isRegistered<OfflineSmartAssistantService>()) {
      return getIt<OfflineSmartAssistantService>();
    }
    return OfflineSmartAssistantService(getIt<AppDatabase>());
  }

  Future<void> _runQuery(String query) async {
    setState(() => _isLoading = true);
    try {
      final res = await _resolveService().ask(query);
      if (!mounted) return;
      setState(() {
        _insights = res;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quickPrompts = const [
      'صافي ربح اليوم',
      'أعلى 5 أصناف ربحاً',
      'الأصناف الراكدة',
      'تنبيهات نفاد المخزون',
      'مقارنة مصاريف الشهر',
      'الأقساط المتأخرة',
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
          width: 600,
          height: 460,
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
                        hintText: 'اسأل عن الربح، المخزون، المصاريف، أو الأقساط...',
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
                      onPressed: () {
                        _queryCtrl.text = prompt;
                        _runQuery(prompt);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        itemCount: _insights.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _insights[index];
                          final accent =
                              item.isAlert ? AppColors.warning : AppColors.primary;
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: accent,
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
                              ],
                            ),
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

