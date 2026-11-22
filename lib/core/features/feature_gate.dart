import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../database/app_database.dart';
import '../database/branch_provider.dart';
import '../database/tx_writer.dart';
import '../errors/failures.dart';

class FeatureDefinition {
  final String key;
  final String label;
  final bool coreAlwaysEnabled;
  final bool defaultEnabled;
  final Set<String> dependencies;

  const FeatureDefinition({
    required this.key,
    required this.label,
    required this.coreAlwaysEnabled,
    required this.defaultEnabled,
    this.dependencies = const {},
  });

  String get metaKey => 'feature.$key';
}

class FeatureKeys {
  static const auth = 'auth';
  static const pos = 'pos';
  static const inventory = 'inventory';
  static const inventoryLogs = 'inventoryLogs';
  static const customers = 'customers';
  static const purchases = 'purchases';
  static const suppliers = 'suppliers';
  static const employees = 'employees';
  static const payroll = 'payroll';
  static const shifts = 'shifts';
  static const reports = 'reports';
  static const expenses = 'expenses';
  static const installments = 'installments';
  static const partners = 'partners';
  static const loyalty = 'loyalty';
  static const promotions = 'promotions';
  static const preOrders = 'preOrders';
  static const wholesalePricing = 'wholesalePricing';
  static const splitPayment = 'splitPayment';
  static const creditSales = 'creditSales';
  static const holdBills = 'holdBills';
  static const lowStockAlerts = 'lowStockAlerts';
  static const productTimestamps = 'productTimestamps';
  static const consolidatedBatches = 'consolidatedBatches';
  static const telegramBot = 'telegramBot';
  static const whatsappDirect = 'whatsappDirect';
  static const blindShiftClosing = 'blindShiftClosing';
  static const drawerPettyCash = 'drawerPettyCash';
  static const managerPinProtection = 'managerPinProtection';
  static const delivery = 'delivery';

  static const definitions = <FeatureDefinition>[
    FeatureDefinition(
      key: auth,
      label: 'المصادقة',
      coreAlwaysEnabled: true,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: pos,
      label: 'نقطة البيع',
      coreAlwaysEnabled: true,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: inventory,
      label: 'المخزون',
      coreAlwaysEnabled: true,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: inventoryLogs,
      label: 'حركات المخزن',
      coreAlwaysEnabled: true,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: customers,
      label: 'العملاء',
      coreAlwaysEnabled: true,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: purchases,
      label: 'المشتريات',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: suppliers,
      label: 'الموردون',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
      dependencies: {purchases},
    ),
    FeatureDefinition(
      key: employees,
      label: 'الموظفون',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: payroll,
      label: 'الرواتب',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
      dependencies: {employees},
    ),
    FeatureDefinition(
      key: shifts,
      label: 'الورديات',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: reports,
      label: 'التقارير',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: expenses,
      label: 'المصروفات',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: installments,
      label: 'الأقساط',
      coreAlwaysEnabled: false,
      defaultEnabled: false,
      dependencies: {customers},
    ),
    FeatureDefinition(
      key: partners,
      label: 'الشركاء',
      coreAlwaysEnabled: false,
      defaultEnabled: false,
    ),
    FeatureDefinition(
      key: loyalty,
      label: 'الولاء',
      coreAlwaysEnabled: false,
      defaultEnabled: false,
      dependencies: {customers},
    ),
    FeatureDefinition(
      key: promotions,
      label: 'العروض الترويجية',
      coreAlwaysEnabled: false,
      defaultEnabled: false,
    ),
    FeatureDefinition(
      key: preOrders,
      label: 'الحجز المسبق والعربونات',
      coreAlwaysEnabled: false,
      defaultEnabled: false,
    ),
    FeatureDefinition(
      key: delivery,
      label: 'إدارة الدليفري والطيارين',
      coreAlwaysEnabled: false,
      defaultEnabled: false,
    ),
    FeatureDefinition(
      key: wholesalePricing,
      label: 'البيع بالقطاعي والجملة',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: splitPayment,
      label: 'الدفع المجزأ',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: creditSales,
      label: 'البيع الآجل والشكك',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: holdBills,
      label: 'تعليق الفواتير المتعددة',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: lowStockAlerts,
      label: 'تنبيهات نواقص المخزون',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: productTimestamps,
      label: 'توثيق وتتبع تعديل المنتجات',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: consolidatedBatches,
      label: 'الشحنات المجمعة وتوزيع الشحن',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: telegramBot,
      label: 'سحب رسائل تيليجرام التلقائي',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: whatsappDirect,
      label: 'تنبيهات وتحديثات الواتساب',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: blindShiftClosing,
      label: 'الجرد الأعمى عند تقفيل الوردية',
      coreAlwaysEnabled: false,
      defaultEnabled: false,
    ),
    FeatureDefinition(
      key: drawerPettyCash,
      label: 'حركات الدرج النقدية والسحب والإيداع',
      coreAlwaysEnabled: false,
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: managerPinProtection,
      label: 'حماية المدير بالرقم السري',
      coreAlwaysEnabled: false,
      defaultEnabled: false,
    ),
  ];

  static final byKey = {for (final d in definitions) d.key: d};
}

@lazySingleton
class FeatureGate {
  final AppDatabase _db;
  final AuthLocalDataSource _authLocalDataSource;
  final TxWriter _txWriter;
  final BranchProvider _branchProvider;

  Map<String, bool>? _lastFeatures;
  StreamController<Map<String, bool>>? _featuresController;
  StreamSubscription? _driftFeaturesSub;

  FeatureGate(
    this._db,
    this._authLocalDataSource,
    this._txWriter,
    this._branchProvider,
  );

  bool _enabledFromRow(FeatureDefinition def, String? value) {
    if (def.coreAlwaysEnabled) return true;
    if (value == null) return def.defaultEnabled;
    return value == '1';
  }

  Map<String, bool> resolveEnabledMap(Map<String, String> stored) {
    final normalized = Map<String, String>.from(stored);
    // Backward compatibility: legacy shifts toggle key.
    if (!normalized.containsKey(
          FeatureKeys.byKey[FeatureKeys.shifts]!.metaKey,
        ) &&
        stored.containsKey('shifts_enabled')) {
      final legacy = stored['shifts_enabled']?.toLowerCase();
      final enabled = legacy == 'true' || legacy == '1';
      normalized[FeatureKeys.byKey[FeatureKeys.shifts]!.metaKey] = enabled
          ? '1'
          : '0';
    }

    final map = <String, bool>{};
    for (final def in FeatureKeys.definitions) {
      map[def.key] = _enabledFromRow(def, normalized[def.metaKey]);
    }
    bool changed = true;
    while (changed) {
      changed = false;
      for (final def in FeatureKeys.definitions) {
        if (map[def.key] == true) {
          for (final dep in def.dependencies) {
            if (map[dep] != true) {
              map[dep] = true;
              changed = true;
            }
          }
        }
      }
    }
    for (final def in FeatureKeys.definitions) {
      if (def.coreAlwaysEnabled) map[def.key] = true;
    }
    return map;
  }

  Stream<Map<String, bool>> watchFeatures() async* {
    if (_lastFeatures != null) {
      yield _lastFeatures!;
    } else {
      yield await getFeatures();
    }
    yield* _getOrCreateFeaturesStream();
  }

  Stream<Map<String, bool>> _getOrCreateFeaturesStream() {
    if (_featuresController == null || _featuresController!.isClosed) {
      _featuresController = StreamController<Map<String, bool>>.broadcast();
      _driftFeaturesSub = (_db.select(_db.appMeta)
            ..where((t) => t.key.like('feature.%')))
          .watch()
          .listen((rows) {
        final stored = <String, String>{for (final r in rows) r.key: r.value};
        final resolved = resolveEnabledMap(stored);
        _lastFeatures = resolved;
        if (_featuresController != null && !_featuresController!.isClosed) {
          _featuresController!.add(resolved);
        }
      });
    }
    return _featuresController!.stream;
  }

  void dispose() {
    _driftFeaturesSub?.cancel();
    _featuresController?.close();
    _featuresController = null;
    _driftFeaturesSub = null;
  }

  Future<Map<String, bool>> getFeatures() async {
    final rows = await (_db.select(
      _db.appMeta,
    )..where((t) => t.key.like('feature.%'))).get();
    final stored = <String, String>{for (final r in rows) r.key: r.value};
    final resolved = resolveEnabledMap(stored);
    _lastFeatures = resolved;
    return resolved;
  }

  Future<bool> isEnabled(String key) async {
    final map = await getFeatures();
    return map[key] ?? false;
  }

  Future<bool> isCurrentUserAdmin() async {
    final user = await _authLocalDataSource.getCachedUser();
    if (user == null) return false;
    return user.role.toLowerCase() != 'cashier';
  }

  Future<void> setFeatureEnabled(
    String key,
    bool enabled, {
    required String userId,
  }) async {
    final def = FeatureKeys.byKey[key];
    if (def == null) {
      throw Exception('ميزة غير معروفة: $key');
    }
    if (userId != 'system' && !await isCurrentUserAdmin()) {
      throw Exception('غير مصرح: تغيير إعدادات النظام متاح للمدير فقط');
    }
    if (def.coreAlwaysEnabled && !enabled) {
      throw Exception('لا يمكن تعطيل ميزة أساسية: ${def.label}');
    }

    final branchId = await _branchProvider.getBranchId();
    final current = await getFeatures();
    final storedRows = await (_db.select(
      _db.appMeta,
    )..where((t) => t.key.like('feature.%'))).get();
    final stored = <String, String>{for (final r in storedRows) r.key: r.value};

    final target = Map<String, bool>.from(current);
    target[key] = enabled;

    if (enabled) {
      for (final dep in def.dependencies) {
        target[dep] = true;
      }
    }
    if (!enabled) {
      for (final other in FeatureKeys.definitions) {
        if (other.dependencies.contains(key) &&
            (current[other.key] ?? other.defaultEnabled)) {
          throw DependencyBlockedFailure(other.key);
        }
      }
    }
    for (final d in FeatureKeys.definitions) {
      if (d.coreAlwaysEnabled) target[d.key] = true;
    }

    final changes = <MapEntry<String, bool>>[];
    for (final d in FeatureKeys.definitions) {
      final newVal = target[d.key] ?? d.defaultEnabled;
      final oldVal = current[d.key] ?? d.defaultEnabled;
      if (newVal != oldVal) {
        changes.add(MapEntry(d.key, newVal));
      }
    }
    if (changes.isEmpty) return;

    final changeDetails = <Map<String, String>>[];
    for (final change in changes) {
      final d = FeatureKeys.byKey[change.key]!;
      final metaKey = d.metaKey;
      final oldStored =
          stored[metaKey] ?? '(default:${d.defaultEnabled ? '1' : '0'})';
      final newStored = change.value ? '1' : '0';
      changeDetails.add({
        'metaKey': metaKey,
        'oldValue': oldStored,
        'newValue': newStored,
      });
    }

    // Single atomic transaction: all feature toggles + audit + sync, one shot.
    final now = DateTime.now();
    await _txWriter.write(
      writeFn: () async {
        for (final detail in changeDetails) {
          await _db
              .into(_db.appMeta)
              .insertOnConflictUpdate(
                AppMetaCompanion(
                  key: Value(detail['metaKey']!),
                  value: Value(detail['newValue']!),
                  updatedAt: Value(now),
                ),
              );
        }
      },
      branchId: branchId,
      entity: 'app_meta',
      entityId: changeDetails.length == 1
          ? changeDetails.first['metaKey']!
          : changeDetails.map((d) => d['metaKey']).join(','),
      operation: 'upsert',
      userId: userId,
      oldValue: changeDetails.length == 1
          ? changeDetails.first['oldValue']!
          : changeDetails
              .map((d) => '${d['metaKey']}=${d['oldValue']}')
              .join('|'),
      newValue: changeDetails.length == 1
          ? changeDetails.first['newValue']!
          : changeDetails
              .map((d) => '${d['metaKey']}=${d['newValue']}')
              .join('|'),
      auditAction: 'feature_toggle',
      payload: jsonEncode({
        'triggerKey': key,
        'enabled': enabled,
        'changes': changeDetails,
      }),
    );
  }

  Future<String?> getMeta(String key) async {
    final row = await (_db.select(
      _db.appMeta,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watchMeta(String key) {
    final q = _db.select(_db.appMeta)..where((t) => t.key.equals(key));
    return q.watchSingleOrNull().map((r) => r?.value);
  }

  Future<void> setMeta(
    String key,
    String value, {
    required String userId,
    bool audit = true,
  }) async {
    if (userId != 'system' && !await isCurrentUserAdmin()) {
      throw Exception('غير مصرح: تغيير إعدادات النظام متاح للمدير فقط');
    }
    final branchId = await _branchProvider.getBranchId();
    final old = await getMeta(key);
    await _txWriter.write(
      writeFn: () async {
        await _db
            .into(_db.appMeta)
            .insertOnConflictUpdate(
              AppMetaCompanion(
                key: Value(key),
                value: Value(value),
                updatedAt: Value(DateTime.now()),
              ),
            );
      },
      branchId: branchId,
      entity: 'app_meta',
      entityId: key,
      operation: 'upsert',
      userId: userId,
      oldValue: old,
      newValue: value,
      auditAction: 'settings_change',
      payload: jsonEncode({'key': key, 'value': value}),
    );
  }
}
