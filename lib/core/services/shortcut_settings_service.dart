import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:drift/drift.dart';
import '../database/app_database.dart';

class ShortcutDefinition {
  final String action;
  final String label;
  final String category; // 'pos', 'inventory', 'navigation'
  final String defaultCombo;

  const ShortcutDefinition({
    required this.action,
    required this.label,
    required this.category,
    required this.defaultCombo,
  });
}

class ShortcutSettingsService {
  final AppDatabase _db;

  ShortcutSettingsService(this._db);

  static const Map<String, String> defaultShortcuts = {
    'openPos': 'Alt+P',
    'openAddProduct': 'Alt+A',
    'openBlindReceive': 'Alt+R',
    'openCreatePurchase': 'Alt+B',
    'openCommandPalette': 'Ctrl+K',
    'openShortcuts': 'F1',
    'quickSearch': 'F2',
    'newRow': 'F3',
    'save': 'Ctrl+S',
    'quickPayCash': 'F5',
    'quickPayCard': 'F6',
    'preOrders': 'F7',
    'reprintReceipt': 'F9',
    'holdBill': 'F10',
    'recallBill': 'F11',
    'completeSale': 'F12',
    'gridNavigation': '↑ ↓ ← →',
    'cancelSelection': 'Esc',
    'focusDiscount': 'Ctrl+D',
    'openSettingsSearch': 'Ctrl+F',
  };

  static const List<ShortcutDefinition> definitions = [
    // 1. POS / Cashier
    ShortcutDefinition(
      action: 'completeSale',
      label: 'إتمام ودفع الفاتورة',
      category: 'pos',
      defaultCombo: 'F12',
    ),
    ShortcutDefinition(
      action: 'holdBill',
      label: 'تعليق الفاتورة (Hold Bill)',
      category: 'pos',
      defaultCombo: 'F10',
    ),
    ShortcutDefinition(
      action: 'recallBill',
      label: 'استرجاع الفاتورة المعلقة (Recall)',
      category: 'pos',
      defaultCombo: 'F11',
    ),
    ShortcutDefinition(
      action: 'quickPayCash',
      label: 'اختيار دفع كاش نقدي',
      category: 'pos',
      defaultCombo: 'F5',
    ),
    ShortcutDefinition(
      action: 'quickPayCard',
      label: 'اختيار دفع شبكة / فيزا',
      category: 'pos',
      defaultCombo: 'F6',
    ),
    ShortcutDefinition(
      action: 'focusDiscount',
      label: 'التركيز على حقل الخصم',
      category: 'pos',
      defaultCombo: 'Ctrl+D',
    ),
    ShortcutDefinition(
      action: 'quickSearch',
      label: 'بحث سريع عن صنف',
      category: 'pos',
      defaultCombo: 'F2',
    ),
    ShortcutDefinition(
      action: 'preOrders',
      label: 'الحجز المسبق والطلبات الخاصة',
      category: 'pos',
      defaultCombo: 'F7',
    ),
    ShortcutDefinition(
      action: 'reprintReceipt',
      label: 'إعادة طباعة آخر فاتورة',
      category: 'pos',
      defaultCombo: 'F9',
    ),
    ShortcutDefinition(
      action: 'gridNavigation',
      label: 'التنقل بالأسهم في شبكة المنتجات والإضافة بـ Enter',
      category: 'pos',
      defaultCombo: '↑ ↓ ← →',
    ),
    ShortcutDefinition(
      action: 'cancelSelection',
      label: 'إلغاء التحديد أو الخروج من النوافذ',
      category: 'pos',
      defaultCombo: 'Esc',
    ),

    // 2. Inventory / Products
    ShortcutDefinition(
      action: 'newRow',
      label: 'إضافة سطر مقاس جديد في الجداول',
      category: 'inventory',
      defaultCombo: 'F3',
    ),
    ShortcutDefinition(
      action: 'save',
      label: 'الحفظ الفوري للشاشة',
      category: 'inventory',
      defaultCombo: 'Ctrl+S',
    ),

    // 3. Navigation & General
    ShortcutDefinition(
      action: 'openPos',
      label: 'الانتقال الفوري لشاشة الكاشير من أي مكان',
      category: 'navigation',
      defaultCombo: 'Alt+P',
    ),
    ShortcutDefinition(
      action: 'openAddProduct',
      label: 'إضافة صنف جديد فوراً',
      category: 'navigation',
      defaultCombo: 'Alt+A',
    ),
    ShortcutDefinition(
      action: 'openBlindReceive',
      label: 'الانتقال لشاشة استلام بضاعة / شحنة جديدة',
      category: 'navigation',
      defaultCombo: 'Alt+R',
    ),
    ShortcutDefinition(
      action: 'openCreatePurchase',
      label: 'الانتقال لشاشة إنشاء فاتورة مشتريات جديدة',
      category: 'navigation',
      defaultCombo: 'Alt+B',
    ),
    ShortcutDefinition(
      action: 'openCommandPalette',
      label: 'لوحة الأوامر الشاملة (Spotlight)',
      category: 'navigation',
      defaultCombo: 'Ctrl+K',
    ),
    ShortcutDefinition(
      action: 'openShortcuts',
      label: 'دليل وتخصيص اختصارات النظام',
      category: 'navigation',
      defaultCombo: 'F1',
    ),
    ShortcutDefinition(
      action: 'openSettingsSearch',
      label: 'البحث المباشر في شاشة الإعدادات',
      category: 'navigation',
      defaultCombo: 'Ctrl+F',
    ),
  ];

  final Map<String, String> _customCache = {};
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  /// Loads all stored custom shortcuts from app_meta
  Future<Map<String, String>> loadShortcuts() async {
    final rows = await (_db.select(_db.appMeta)
          ..where((t) => t.key.like('shortcuts.%')))
        .get();

    _customCache.clear();
    for (final r in rows) {
      final action = r.key.replaceFirst('shortcuts.', '');
      _customCache[action] = r.value;
    }
    _isLoaded = true;
    return getAllShortcuts();
  }

  /// Returns the effective shortcut for an action (custom if set, otherwise default)
  String getShortcut(String action) {
    if (_customCache.containsKey(action)) {
      return _customCache[action]!;
    }
    return defaultShortcuts[action] ?? '';
  }

  /// Returns a SingleActivator for the action
  SingleActivator getActivator(String action) {
    final combo = getShortcut(action);
    return parseCombo(combo);
  }

  /// Parses a string representation like 'Ctrl+K', 'Alt+1', 'F12' into SingleActivator
  static SingleActivator parseCombo(String combo) {
    final parts = combo.toUpperCase().split('+').map((s) => s.trim()).toList();
    bool ctrl = false;
    bool alt = false;
    bool shift = false;
    LogicalKeyboardKey key = LogicalKeyboardKey.f12;

    for (final p in parts) {
      if (p == 'CTRL' || p == 'CONTROL') {
        ctrl = true;
      } else if (p == 'ALT') {
        alt = true;
      } else if (p == 'SHIFT') {
        shift = true;
      } else {
        key = _parseKey(p);
      }
    }
    return SingleActivator(key, control: ctrl, alt: alt, shift: shift);
  }

  static LogicalKeyboardKey _parseKey(String name) {
    switch (name.toUpperCase()) {
      case 'F1': return LogicalKeyboardKey.f1;
      case 'F2': return LogicalKeyboardKey.f2;
      case 'F3': return LogicalKeyboardKey.f3;
      case 'F4': return LogicalKeyboardKey.f4;
      case 'F5': return LogicalKeyboardKey.f5;
      case 'F6': return LogicalKeyboardKey.f6;
      case 'F7': return LogicalKeyboardKey.f7;
      case 'F8': return LogicalKeyboardKey.f8;
      case 'F9': return LogicalKeyboardKey.f9;
      case 'F10': return LogicalKeyboardKey.f10;
      case 'F11': return LogicalKeyboardKey.f11;
      case 'F12': return LogicalKeyboardKey.f12;
      case '1': return LogicalKeyboardKey.digit1;
      case '2': return LogicalKeyboardKey.digit2;
      case '3': return LogicalKeyboardKey.digit3;
      case '4': return LogicalKeyboardKey.digit4;
      case '5': return LogicalKeyboardKey.digit5;
      case '6': return LogicalKeyboardKey.digit6;
      case '7': return LogicalKeyboardKey.digit7;
      case '8': return LogicalKeyboardKey.digit8;
      case '9': return LogicalKeyboardKey.digit9;
      case '0': return LogicalKeyboardKey.digit0;
      case 'A': return LogicalKeyboardKey.keyA;
      case 'B': return LogicalKeyboardKey.keyB;
      case 'D': return LogicalKeyboardKey.keyD;
      case 'F': return LogicalKeyboardKey.keyF;
      case 'K': return LogicalKeyboardKey.keyK;
      case 'N': return LogicalKeyboardKey.keyN;
      case 'P': return LogicalKeyboardKey.keyP;
      case 'R': return LogicalKeyboardKey.keyR;
      case 'S': return LogicalKeyboardKey.keyS;
      case 'ENTER': return LogicalKeyboardKey.enter;
      case 'ESC':
      case 'ESCAPE': return LogicalKeyboardKey.escape;
      default: return LogicalKeyboardKey.f12;
    }
  }

  /// Returns all active shortcuts mapped by action
  Map<String, String> getAllShortcuts() {
    final map = Map<String, String>.from(defaultShortcuts);
    map.addAll(_customCache);
    return map;
  }

  /// Checks if another action uses the given key combination
  bool hasConflict(String action, String keyCombo) {
    final cleanCombo = keyCombo.trim().toUpperCase();
    final all = getAllShortcuts();
    for (final entry in all.entries) {
      if (entry.key != action && entry.value.trim().toUpperCase() == cleanCombo) {
        return true;
      }
    }
    return false;
  }

  /// Returns the action name conflicting with the given key combo, if any
  String? getConflictingAction(String action, String keyCombo) {
    final cleanCombo = keyCombo.trim().toUpperCase();
    final all = getAllShortcuts();
    for (final entry in all.entries) {
      if (entry.key != action && entry.value.trim().toUpperCase() == cleanCombo) {
        return entry.key;
      }
    }
    return null;
  }

  /// Saves a custom shortcut for a specific action
  Future<void> setShortcut(
    String action,
    String keyCombo, {
    String userId = 'admin',
  }) async {
    final cleanCombo = keyCombo.trim();
    await _db.into(_db.appMeta).insertOnConflictUpdate(
          AppMetaCompanion.insert(
            key: 'shortcuts.$action',
            value: cleanCombo,
            updatedAt: DateTime.now(),
          ),
        );
    _customCache[action] = cleanCombo;
  }

  /// Restores all shortcuts to system defaults
  Future<void> restoreDefaults({String userId = 'admin'}) async {
    await (_db.delete(_db.appMeta)..where((t) => t.key.like('shortcuts.%'))).go();
    _customCache.clear();
  }
}
