import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../../../core/database/tx_writer.dart';
import '../../../../core/utils/money.dart';

class UsedDeviceIntakeResult {
  final String unitId;
  final String variantId;
  final String productName;
  final String imei;
  final String condition;
  final int buyPricePiasters;
  final int? batteryHealth;
  final bool deductedFromDrawer;

  const UsedDeviceIntakeResult({
    required this.unitId,
    required this.variantId,
    required this.productName,
    required this.imei,
    required this.condition,
    required this.buyPricePiasters,
    this.batteryHealth,
    this.deductedFromDrawer = false,
  });
}

@lazySingleton
class DeviceSerialService {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final TxWriter _txWriter;
  final Uuid _uuid = const Uuid();

  DeviceSerialService(this._db, this._branchProvider, this._txWriter);

  static String conditionLabel(String? condition) {
    switch (condition) {
      case 'used':
        return 'مستعمل';
      case 'refurbished':
        return 'مجدد';
      case 'new':
      default:
        return 'جديد';
    }
  }

  static void validateOptionalNationalId(String? nationalId) {
    final clean = nationalId?.trim() ?? '';
    if (clean.isEmpty) return;
    if (!RegExp(r'^\d{14}$').hasMatch(clean)) {
      throw Exception('الرقم القومي للبائع يجب أن يتكون من 14 رقماً صحيحاً');
    }
  }

  Future<void> registerSerialUnits({
    required String variantId,
    required List<String> imeis,
    String condition = 'new',
    int? batteryHealth,
    String? notes,
    String? sellerName,
    String? sellerNationalId,
    String? sellerPhone,
    int buyPricePiasters = 0,
    String userId = 'admin',
  }) async {
    final cleaned = imeis
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) return;

    final uniqueImeis = <String>{};
    for (final code in cleaned) {
      if (!uniqueImeis.add(code.toLowerCase())) {
        throw Exception('تم تكرار رقم IMEI ($code) في نفس الإدخال');
      }
    }

    validateOptionalNationalId(sellerNationalId);

    final branchId = await _branchProvider.getBranchId();
    final now = DateTime.now();

    await _txWriter.write(
      branchId: branchId,
      entity: 'device_serial_units',
      entityId: variantId,
      operation: 'register_device_serials',
      userId: userId,
      writeFn: () async {
        for (final imei in cleaned) {
          final existing = await (_db.select(_db.deviceSerialUnits)
                ..where(
                  (t) => t.imei.equals(imei) & t.deletedAt.isNull(),
                ))
              .getSingleOrNull();
          if (existing != null) {
            throw Exception('رقم الـ IMEI ($imei) مسجل بالفعل في النظام');
          }

          final id = _uuid.v4();
          await _db.into(_db.deviceSerialUnits).insert(
                DeviceSerialUnitsCompanion.insert(
                  id: id,
                  branchId: branchId,
                  variantId: variantId,
                  imei: imei,
                  condition: Value(condition),
                  batteryHealth: Value(batteryHealth),
                  notes: Value(
                    notes != null && notes.trim().isNotEmpty ? notes.trim() : null,
                  ),
                  sellerName: Value(
                    sellerName != null && sellerName.trim().isNotEmpty
                        ? sellerName.trim()
                        : null,
                  ),
                  sellerNationalId: Value(
                    sellerNationalId != null && sellerNationalId.trim().isNotEmpty
                        ? sellerNationalId.trim()
                        : null,
                  ),
                  sellerPhone: Value(
                    sellerPhone != null && sellerPhone.trim().isNotEmpty
                        ? sellerPhone.trim()
                        : null,
                  ),
                  buyPrice: Value(buyPricePiasters),
                  status: const Value('in_stock'),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
      },
    );
  }

  Future<UsedDeviceIntakeResult> registerUsedOrTradeInDevice({
    required String variantId,
    required String productName,
    required String imei,
    String condition = 'used',
    int? batteryHealth,
    String? notes,
    String? sellerName,
    String? sellerNationalId,
    String? sellerPhone,
    required int buyPricePiasters,
    bool deductFromDrawer = false,
    String userId = 'admin',
  }) async {
    final cleanImei = imei.trim();
    if (cleanImei.isEmpty) {
      throw Exception('يرجى إدخال رقم الـ IMEI للجهاز');
    }
    if (buyPricePiasters < 0) {
      throw Exception('سعر الشراء لا يمكن أن يكون سالباً');
    }
    if (batteryHealth != null && (batteryHealth < 0 || batteryHealth > 100)) {
      throw Exception('نسبة البطارية يجب أن تكون بين 0% و 100%');
    }
    validateOptionalNationalId(sellerNationalId);

    final branchId = await _branchProvider.getBranchId();
    final now = DateTime.now();
    final unitId = _uuid.v4();

    await _txWriter.write(
      branchId: branchId,
      entity: 'device_serial_units',
      entityId: unitId,
      operation: 'intake_used_device',
      userId: userId,
      writeFn: () async {
        final existing = await (_db.select(_db.deviceSerialUnits)
              ..where(
                (t) => t.imei.equals(cleanImei) & t.deletedAt.isNull(),
              ))
            .getSingleOrNull();
        if (existing != null) {
          throw Exception('رقم الـ IMEI ($cleanImei) مسجل بالفعل في النظام');
        }

        await _db.into(_db.deviceSerialUnits).insert(
              DeviceSerialUnitsCompanion.insert(
                id: unitId,
                branchId: branchId,
                variantId: variantId,
                imei: cleanImei,
                condition: Value(condition),
                batteryHealth: Value(batteryHealth),
                notes: Value(
                  notes != null && notes.trim().isNotEmpty ? notes.trim() : null,
                ),
                sellerName: Value(
                  sellerName != null && sellerName.trim().isNotEmpty
                      ? sellerName.trim()
                      : null,
                ),
                sellerNationalId: Value(
                  sellerNationalId != null && sellerNationalId.trim().isNotEmpty
                      ? sellerNationalId.trim()
                      : null,
                ),
                sellerPhone: Value(
                  sellerPhone != null && sellerPhone.trim().isNotEmpty
                      ? sellerPhone.trim()
                      : null,
                ),
                buyPrice: Value(buyPricePiasters),
                status: const Value('in_stock'),
                createdAt: now,
                updatedAt: now,
              ),
            );

        // Increment variant quantity by +1
        final variantRow = await (_db.select(_db.productVariants)
              ..where((t) => t.id.equals(variantId)))
            .getSingleOrNull();
        if (variantRow != null) {
          final newQty = variantRow.quantity + 1;
          await (_db.update(_db.productVariants)
                ..where((t) => t.id.equals(variantId)))
              .write(
            ProductVariantsCompanion(
              quantity: Value(newQty),
              updatedAt: Value(now),
            ),
          );
          await _db.into(_db.inventoryLogs).insert(
                InventoryLogsCompanion.insert(
                  id: _uuid.v4(),
                  branchId: branchId,
                  variantId: variantId,
                  qtyDelta: 1,
                  type: 'purchase',
                  reason: Value(
                    'شراء جهاز ${conditionLabel(condition)} IMEI: $cleanImei',
                  ),
                  refType: 'device_serial',
                  refId: Value(unitId),
                  userId: userId,
                  createdAt: now,
                ),
              );
        }

        if (deductFromDrawer && buyPricePiasters > 0) {
          await _db.into(_db.expenses).insert(
                ExpensesCompanion.insert(
                  id: _uuid.v4(),
                  branchId: branchId,
                  category: 'شراء أجهزة مستعملة',
                  amount: buyPricePiasters,
                  note: Value(
                    'شراء جهاز ($productName) IMEI: $cleanImei - البائع: ${sellerName?.trim().isNotEmpty == true ? sellerName!.trim() : "غير مسجل"} (${Money(buyPricePiasters).toDisplay()} ج.م)',
                  ),
                  expenseDate: now,
                  userId: userId,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
        }
      },
    );

    return UsedDeviceIntakeResult(
      unitId: unitId,
      variantId: variantId,
      productName: productName,
      imei: cleanImei,
      condition: condition,
      buyPricePiasters: buyPricePiasters,
      batteryHealth: batteryHealth,
      deductedFromDrawer: deductFromDrawer,
    );
  }

  Future<DeviceSerialUnit?> findInStockByImei(String imei) async {
    final clean = imei.trim();
    if (clean.isEmpty) return null;
    return (_db.select(_db.deviceSerialUnits)
          ..where(
            (t) =>
                t.imei.equals(clean) &
                t.status.equals('in_stock') &
                t.deletedAt.isNull(),
          ))
        .getSingleOrNull();
  }

  Future<List<DeviceSerialUnit>> getInStockUnitsForVariant(String variantId) {
    return (_db.select(_db.deviceSerialUnits)
          ..where(
            (t) =>
                t.variantId.equals(variantId) &
                t.status.equals('in_stock') &
                t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<bool> hasTrackedSerialsForVariant(String variantId) async {
    final rows = await (_db.select(_db.deviceSerialUnits)
          ..where(
            (t) =>
                t.variantId.equals(variantId) &
                t.status.equals('in_stock') &
                t.deletedAt.isNull(),
          )
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  Future<List<DeviceSerialUnit>> getUnitsForSale(String saleId) {
    return (_db.select(_db.deviceSerialUnits)
          ..where(
            (t) => t.saleId.equals(saleId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> markSoldByImei({
    required String imei,
    required String saleId,
  }) async {
    final clean = imei.trim();
    if (clean.isEmpty) return;
    await (_db.update(_db.deviceSerialUnits)
          ..where(
            (t) =>
                t.imei.equals(clean) &
                t.status.equals('in_stock') &
                t.deletedAt.isNull(),
          ))
        .write(
      DeviceSerialUnitsCompanion(
        status: const Value('sold'),
        saleId: Value(saleId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> verifyAndReturnByImei({
    required String saleId,
    required String imei,
  }) async {
    final clean = imei.trim();
    if (clean.isEmpty) {
      throw Exception('يرجى إدخال رقم الـ IMEI للتحقق من الجهاز المرتجع');
    }

    final unit = await (_db.select(_db.deviceSerialUnits)
          ..where(
            (t) => t.imei.equals(clean) & t.deletedAt.isNull(),
          ))
        .getSingleOrNull();

    if (unit == null || unit.saleId != saleId || unit.status != 'sold') {
      throw Exception(
        'رقم الـ IMEI ($clean) لا يطابق أي جهاز مباع في هذه الفاتورة',
      );
    }

    await (_db.update(_db.deviceSerialUnits)
          ..where((t) => t.id.equals(unit.id)))
        .write(
      DeviceSerialUnitsCompanion(
        status: const Value('in_stock'),
        saleId: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

