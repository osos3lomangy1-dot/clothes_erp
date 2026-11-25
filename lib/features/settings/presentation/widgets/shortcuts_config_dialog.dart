import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/retail_sector.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/services/shortcut_settings_service.dart';
import '../../../../features/auth/presentation/cubits/auth_cubit.dart';
import '../../../../features/auth/presentation/cubits/auth_state.dart';
import '../../../../features/auth/services/cashier_permissions_service.dart';

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
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _captureFocusNode = FocusNode();
  Map<String, String> _shortcuts = {};
  bool _isLoading = true;
  bool _isHospitality = false;
  bool _inventoryEnabled = true;
  bool _purchasesEnabled = true;
  String _searchQuery = '';
  String? _editingAction;
  String? _conflictWarning;

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _captureFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadShortcuts() async {
    setState(() => _isLoading = true);
    final data = await _service.loadShortcuts();
    bool isHosp = false;
    bool invEnabled = true;
    bool purEnabled = true;
    if (getIt.isRegistered<FeatureGate>()) {
      try {
        final gate = getIt<FeatureGate>();
        final sector = await gate.getMeta(RetailSector.metaKey) ?? RetailSector.apparel;
        isHosp = RetailSector.isHospitalityMode(sector);
        invEnabled = await gate.isEnabled(FeatureKeys.inventory);
        purEnabled = await gate.isEnabled(FeatureKeys.purchases);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _shortcuts = data;
      _isHospitality = isHosp;
      _inventoryEnabled = invEnabled;
      _purchasesEnabled = purEnabled;
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
    _captureFocusNode.requestFocus();
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
    bool isCashier = false;
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        isCashier = authState.user.role == 'cashier';
      }
    } catch (_) {}

    return Dialog(
      key: const Key('shortcuts_config_dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
        child: KeyboardListener(
          focusNode: _captureFocusNode,
          onKeyEvent: _handleKeyCapture,
          child: DefaultTabController(
            length: 2,
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
                  TabBar(
                    labelColor: AppColors.primary,
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: AppColors.primary,
                    tabs: const [
                      Tab(
                        key: Key('shortcuts_cheatsheet_tab'),
                        icon: Icon(Icons.menu_book_rounded, size: 18),
                        text: 'دليل الاختصارات السريع',
                      ),
                      Tab(
                        key: Key('shortcuts_customizer_tab'),
                        icon: Icon(Icons.tune_rounded, size: 18),
                        text: 'تخصيص المفاتيح',
                      ),
                    ],
                  ),
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

                  // Tab Views
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : TabBarView(
                            children: [
                              _buildCheatsheetTab(isCashier: isCashier),
                              _buildCustomizerTab(isCashier: isCashier),
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
      ),
    );
  }

  String _keyFor(String action, String fallback) {
    final val = _shortcuts[action];
    if (val == null || val.trim().isEmpty) return fallback;
    return val;
  }

  Widget _buildCheatsheetTab({required bool isCashier}) {
    final cashierPerms = CashierPermissionsService.current;
    final canProducts = !isCashier && _inventoryEnabled;
    final canBlindReceive = (!isCashier || cashierPerms.allowGoodsIntake) && !_isHospitality;
    final canPurchases = (!isCashier || cashierPerms.allowViewPurchases) && _purchasesEnabled;

    final groups = <_CheatsheetGroupData>[
      _CheatsheetGroupData(
        title: 'نقطة البيع (الكاشير)',
        icon: Icons.point_of_sale_rounded,
        items: [
          _CheatsheetItemData(label: 'إتمام ودفع الفاتورة', combo: _keyFor('completeSale', 'F12')),
          _CheatsheetItemData(label: 'تعليق الفاتورة (Hold Bill)', combo: _keyFor('holdBill', 'F10')),
          _CheatsheetItemData(label: 'استرجاع الفاتورة المعلقة (Recall)', combo: _keyFor('recallBill', 'F11')),
          _CheatsheetItemData(label: 'اختيار دفع كاش نقدي', combo: _keyFor('quickPayCash', 'F5')),
          _CheatsheetItemData(label: 'اختيار دفع شبكة / فيزا', combo: _keyFor('quickPayCard', 'F6')),
          _CheatsheetItemData(label: 'التركيز على حقل الخصم', combo: _keyFor('focusDiscount', 'Ctrl+D')),
          _CheatsheetItemData(label: 'بحث سريع عن صنف', combo: _keyFor('quickSearch', 'F2')),
          _CheatsheetItemData(label: 'الحجز المسبق والطلبات الخاصة', combo: _keyFor('preOrders', 'F7')),
          _CheatsheetItemData(label: 'إعادة طباعة آخر فاتورة', combo: _keyFor('reprintReceipt', 'F9')),
          _CheatsheetItemData(label: 'التنقل في الشبكة والإضافة بـ Enter', combo: _keyFor('gridNavigation', '↑ ↓ ← →')),
          _CheatsheetItemData(label: 'إلغاء التحديد أو الخروج من النوافذ', combo: _keyFor('cancelSelection', 'Esc')),
        ],
      ),
      _CheatsheetGroupData(
        title: 'الانتقال السريع والنظام العام',
        icon: Icons.bolt_rounded,
        items: [
          _CheatsheetItemData(label: 'الانتقال الفوري لشاشة الكاشير', combo: _keyFor('openPos', 'Alt+P')),
          if (canProducts)
            _CheatsheetItemData(label: 'إضافة صنف جديد فوراً', combo: _keyFor('openAddProduct', 'Alt+A')),
          if (canBlindReceive)
            _CheatsheetItemData(label: 'الانتقال لشاشة استلام بضاعة / شحنة جديدة', combo: _keyFor('openBlindReceive', 'Alt+R')),
          if (canPurchases)
            _CheatsheetItemData(label: 'الانتقال لشاشة إنشاء فاتورة مشتريات جديدة', combo: _keyFor('openCreatePurchase', 'Alt+B')),
          _CheatsheetItemData(label: 'لوحة الأوامر الشاملة (Spotlight)', combo: _keyFor('openCommandPalette', 'Ctrl+K')),
          _CheatsheetItemData(label: 'دليل وتخصيص اختصارات النظام', combo: _keyFor('openShortcuts', 'F1')),
          _CheatsheetItemData(label: 'البحث المباشر في الإعدادات', combo: _keyFor('openSettingsSearch', 'Ctrl+F')),
        ],
      ),
      if (canProducts || canBlindReceive)
        _CheatsheetGroupData(
          title: 'المنتجات واستلام البضاعة',
          icon: Icons.inventory_2_rounded,
          items: [
            if (canProducts) ...[
              const _CheatsheetItemData(label: 'إضافة صنف جديد داخل شاشة المنتجات', combo: 'Ctrl+N / F3'),
              const _CheatsheetItemData(label: 'التركيز على بحث المنتجات', combo: 'F2 / Ctrl+F'),
              const _CheatsheetItemData(label: 'حفظ الصنف في نموذج الإضافة البسيط', combo: 'Ctrl+S / F12'),
              const _CheatsheetItemData(label: 'التنقل بين حقول نموذج الصنف / الحفظ', combo: 'Enter'),
            ],
            if (canBlindReceive) ...[
              const _CheatsheetItemData(label: 'التركيز على حقل باركود استلام الشحنة', combo: 'F2'),
              const _CheatsheetItemData(label: 'إضافة صنف سريع أثناء استلام الشحنة', combo: 'F3'),
              const _CheatsheetItemData(label: 'حفظ واعتماد إذن استلام البضاعة', combo: 'Ctrl+S / F12'),
            ],
          ],
        ),
      if (canPurchases)
        const _CheatsheetGroupData(
          title: 'المشتريات وفواتير الموردين',
          icon: Icons.shopping_bag_rounded,
          items: [
            _CheatsheetItemData(label: 'إنشاء فاتورة مشتريات جديدة (من شاشة المشتريات)', combo: 'Ctrl+N / F3'),
            _CheatsheetItemData(label: 'التركيز على اختيار المورد / البحث', combo: 'F2'),
            _CheatsheetItemData(label: 'إضافة صنف سريع داخل فاتورة الشراء', combo: 'F3'),
            _CheatsheetItemData(label: 'حفظ واعتماد فاتورة المشتريات', combo: 'Ctrl+S / F12'),
          ],
        ),
    ];

    final query = _searchQuery.trim().toLowerCase();
    final filteredGroups = groups
        .map((g) {
          if (query.isEmpty) return g;
          final titleMatches = g.title.toLowerCase().contains(query);
          final matchingItems = g.items
              .where((item) =>
                  titleMatches ||
                  item.label.toLowerCase().contains(query) ||
                  item.combo.toLowerCase().contains(query))
              .toList();
          return _CheatsheetGroupData(
            title: g.title,
            icon: g.icon,
            items: matchingItems,
          );
        })
        .where((g) => g.items.isNotEmpty)
        .toList();

    return Column(
      children: [
        TextField(
          key: const Key('shortcuts_cheatsheet_search_field'),
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: 'ابحث عن اختصار أو زر (مثال: Alt+A، مشتريات، حفظ، F2)...',
            prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            isDense: true,
            filled: true,
            fillColor: AppColors.surfaceContainer,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppColors.outlineVariant),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filteredGroups.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد اختصارات مطابقة لبحثك',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  itemCount: filteredGroups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) {
                    final group = filteredGroups[idx];
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(group.icon, size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Text(
                                group.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 14),
                          ...group.items.map(
                            (item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
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
                                      item.combo,
                                      textDirection: TextDirection.ltr,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCustomizerTab({required bool isCashier}) {
    return ListView(
      children: [
        _buildCategorySection('كاشير ومبيعات', 'pos'),
        if (!isCashier || CashierPermissionsService.current.allowGoodsIntake) ...[
          const SizedBox(height: 14),
          _buildCategorySection('المخزن والمنتجات', 'inventory'),
        ],
        const SizedBox(height: 14),
        _buildCategorySection('التنقل والنظام العام', 'navigation'),
      ],
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

class _CheatsheetGroupData {
  final String title;
  final IconData icon;
  final List<_CheatsheetItemData> items;

  const _CheatsheetGroupData({
    required this.title,
    required this.icon,
    required this.items,
  });
}

class _CheatsheetItemData {
  final String label;
  final String combo;

  const _CheatsheetItemData({
    required this.label,
    required this.combo,
  });
}
