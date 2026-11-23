import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/shortcut_settings_service.dart';

class ShortcutsConfigDialog extends StatefulWidget {
  const ShortcutsConfigDialog({super.key});

  static bool _isOpen = false;
  static bool get isOpen => _isOpen;

  static Future<T?> show<T>(BuildContext context) async {
    if (_isOpen) return null;
    _isOpen = true;
    try {
      return await showDialog<T>(
        context: context,
        builder: (_) => const ShortcutsConfigDialog(),
      );
    } finally {
      _isOpen = false;
    }
  }

  @override
  State<ShortcutsConfigDialog> createState() => _ShortcutsConfigDialogState();
}

class _ShortcutsConfigDialogState extends State<ShortcutsConfigDialog> {
  final ShortcutSettingsService _service = getIt<ShortcutSettingsService>();
  Map<String, String> _shortcuts = {};
  bool _isLoading = true;
  String? _editingAction;
  String? _conflictWarning;

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  Future<void> _loadShortcuts() async {
    setState(() => _isLoading = true);
    final data = await _service.loadShortcuts();
    if (!mounted) return;
    setState(() {
      _shortcuts = data;
      _isLoading = false;
    });
  }

  Future<void> _restoreDefaults() async {
    await _service.restoreDefaults();
    await _loadShortcuts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم استعادة الاختصارات الافتراضية للنظام بنجاح'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _startEditing(String action) {
    setState(() {
      _editingAction = action;
      _conflictWarning = null;
    });
  }

  Future<void> _handleKeyCapture(KeyEvent event) async {
    if (_editingAction == null || event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _editingAction = null;
        _conflictWarning = null;
      });
      return;
    }

    String combo = '';
    final isControl = HardwareKeyboard.instance.isControlPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isControl) combo += 'Ctrl+';
    if (isAlt) combo += 'Alt+';
    if (isShift) combo += 'Shift+';

    // Format single key
    String keyLabel = key.keyLabel;
    if (key == LogicalKeyboardKey.f1) {
      keyLabel = 'F1';
    } else if (key == LogicalKeyboardKey.f2) {
      keyLabel = 'F2';
    } else if (key == LogicalKeyboardKey.f3) {
      keyLabel = 'F3';
    } else if (key == LogicalKeyboardKey.f4) {
      keyLabel = 'F4';
    } else if (key == LogicalKeyboardKey.f5) {
      keyLabel = 'F5';
    } else if (key == LogicalKeyboardKey.f6) {
      keyLabel = 'F6';
    } else if (key == LogicalKeyboardKey.f7) {
      keyLabel = 'F7';
    } else if (key == LogicalKeyboardKey.f8) {
      keyLabel = 'F8';
    } else if (key == LogicalKeyboardKey.f9) {
      keyLabel = 'F9';
    } else if (key == LogicalKeyboardKey.f10) {
      keyLabel = 'F10';
    } else if (key == LogicalKeyboardKey.f11) {
      keyLabel = 'F11';
    } else if (key == LogicalKeyboardKey.f12) {
      keyLabel = 'F12';
    } else if (key == LogicalKeyboardKey.enter) {
      keyLabel = 'Enter';
    } else if (key == LogicalKeyboardKey.space) {
      keyLabel = 'Space';
    } else if (key == LogicalKeyboardKey.tab) {
      keyLabel = 'Tab';
    }

    // Avoid recording modifier only
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      return;
    }

    combo += keyLabel.toUpperCase();

    // Check conflict
    final conflictingAction = _service.getConflictingAction(_editingAction!, combo);
    if (conflictingAction != null) {
      final conflictDef = ShortcutSettingsService.definitions.firstWhere(
        (d) => d.action == conflictingAction,
        orElse: () => ShortcutDefinition(action: conflictingAction, label: conflictingAction, category: '', defaultCombo: ''),
      );
      setState(() {
        _conflictWarning = 'تنبيه: هذا الاختصار ($combo) مستخدم بالفعل لـ "${conflictDef.label}"';
      });
    }

    await _service.setShortcut(_editingAction!, combo);
    setState(() {
      _shortcuts[_editingAction!] = combo;
      _editingAction = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('shortcuts_config_dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 650),
        child: KeyboardListener(
          focusNode: FocusNode()..requestFocus(),
          onKeyEvent: _handleKeyCapture,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.keyboard_rounded, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'مركز دليل وتخصيص اختصارات لوحة المفاتيح',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'عرض وتخصيص كافة أزرار التحكم السريع لسرعة إنجاز العمليات',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),

                // Conflict warning banner if present
                if (_conflictWarning != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _conflictWarning!,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_editingAction != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.touch_app_rounded, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'وضع الاستماع مفعل: اضغط الزر الجديد المطلوب من لوحة المفاتيح الآن (أو Esc للإلغاء)...',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Shortcuts List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          children: [
                            _buildCategorySection('كاشير ومبيعات', 'pos'),
                            const SizedBox(height: 14),
                            _buildCategorySection('المخزن والمنتجات', 'inventory'),
                            const SizedBox(height: 14),
                            _buildCategorySection('التنقل والنظام العام', 'navigation'),
                          ],
                        ),
                ),

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Actions Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('restore_default_shortcuts_btn'),
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('استعادة الإعدادات الافتراضية'),
                      onPressed: _restoreDefaults,
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إغلاق', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  Widget _buildCategorySection(String title, String category) {
    final items = ShortcutSettingsService.definitions.where((d) => d.category == category).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 6),
        ...items.map((def) {
          final isEditing = _editingAction == def.action;
          final currentKey = _shortcuts[def.action] ?? def.defaultCombo;

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isEditing ? Colors.blue.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isEditing ? Colors.blue.shade400 : Colors.grey.shade200,
                width: isEditing ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(def.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('افتراضي: ${def.defaultCombo}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Text(
                    isEditing ? 'اضغط الزر...' : currentKey,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: isEditing ? Colors.blue.shade800 : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: Key('edit_shortcut_btn_${def.action}'),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  tooltip: 'تعديل الاختصار',
                  onPressed: () => _startEditing(def.action),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
