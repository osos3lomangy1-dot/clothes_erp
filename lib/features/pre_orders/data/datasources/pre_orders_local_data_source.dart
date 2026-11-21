import 'dart:async';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/entities/pre_order_item_entity.dart';
import '../../domain/entities/pre_order_payment_entity.dart';

abstract class PreOrdersLocalDataSource {
  Future<void> ensureTablesExist();
  Future<List<PreOrderEntity>> getPreOrders({String? status, String? searchQuery});
  Future<PreOrderEntity?> getPreOrderById(String id);
  Future<PreOrderEntity> insertPreOrder(
    PreOrderEntity order, {
    int initialDepositPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  });
  Future<void> addPayment(
    String preOrderId,
    int amountPiasters, {
    String paymentMethod = 'cash',
    String? notes,
    String? shiftId,
    String? cashierId,
  });
  Future<void> markArrivedAtStore(String preOrderId);
  Future<void> deliverPreOrder(
    String preOrderId, {
    int finalPaymentPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  });
  Future<void> forfeitDeposit(
    String preOrderId, {
    bool transferItemsToInventory = true,
    String? categoryId,
  });
  Future<void> cancelAndRefund(
    String preOrderId, {
    int refundAmountPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  });
  Future<void> deletePreOrder(String preOrderId);
}

@LazySingleton(as: PreOrdersLocalDataSource)
class PreOrdersLocalDataSourceImpl implements PreOrdersLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final _uuid = const Uuid();
  bool _initialized = false;

  PreOrdersLocalDataSourceImpl(this._db, this._branchProvider);

  @override
  Future<void> ensureTablesExist() async {
    if (_initialized) return;

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS pre_orders (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        order_number TEXT NOT NULL,
        customer_id TEXT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT NOT NULL,
        agent_name TEXT,
        tracking_number TEXT,
        notes TEXT,
        expected_delivery_date INTEGER,
        total_piasters INTEGER NOT NULL,
        deposit_piasters INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pendingProcessing',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        arrived_at INTEGER,
        delivered_at INTEGER,
        sale_id TEXT,
        forfeited_at INTEGER,
        forfeited_revenue_piasters INTEGER,
        refunded_at INTEGER,
        refunded_piasters INTEGER,
        deleted_at INTEGER
      );
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS pre_order_items (
        id TEXT PRIMARY KEY,
        pre_order_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        variant_description TEXT,
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_price_piasters INTEGER NOT NULL,
        total_price_piasters INTEGER NOT NULL,
        cost_price_piasters INTEGER NOT NULL DEFAULT 0,
        commission_piasters INTEGER NOT NULL DEFAULT 0,
        item_url TEXT,
        notes TEXT,
        transferred_to_inventory INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS pre_order_payments (
        id TEXT PRIMARY KEY,
        pre_order_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        shift_id TEXT,
        cashier_id TEXT,
        amount_piasters INTEGER NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        notes TEXT,
        created_at INTEGER NOT NULL
      );
    ''');

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_pre_orders_status ON pre_orders(status);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_pre_orders_customer ON pre_orders(customer_phone);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_pre_order_items_order ON pre_order_items(pre_order_id);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_pre_order_payments_order ON pre_order_payments(pre_order_id);
    ''');

    // Safe inline migrations for existing databases
    try {
      await _db.customStatement(
        'ALTER TABLE pre_orders ADD COLUMN agent_name TEXT;',
      );
    } catch (_) {}
    try {
      await _db.customStatement(
        'ALTER TABLE pre_orders ADD COLUMN tracking_number TEXT;',
      );
    } catch (_) {}
    try {
      await _db.customStatement(
        'ALTER TABLE pre_order_items ADD COLUMN cost_price_piasters INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await _db.customStatement(
        'ALTER TABLE pre_order_items ADD COLUMN commission_piasters INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}

    _initialized = true;
  }

  @override
  Future<List<PreOrderEntity>> getPreOrders({
    String? status,
    String? searchQuery,
  }) async {
    await ensureTablesExist();

    final whereClauses = <String>['deleted_at IS NULL'];
    final variables = <Variable>[];

    if (status != null && status.isNotEmpty && status != 'all') {
      whereClauses.add('status = ?');
      variables.add(Variable.withString(status));
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      whereClauses.add(
        '(order_number LIKE ? OR customer_name LIKE ? OR customer_phone LIKE ? OR agent_name LIKE ? OR tracking_number LIKE ?)',
      );
      variables.add(Variable.withString(q));
      variables.add(Variable.withString(q));
      variables.add(Variable.withString(q));
      variables.add(Variable.withString(q));
      variables.add(Variable.withString(q));
    }

    final query = '''
      SELECT * FROM pre_orders
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY created_at DESC
    ''';

    final rows = await _db.customSelect(query, variables: variables).get();
    final results = <PreOrderEntity>[];

    for (final row in rows) {
      final orderId = row.read<String>('id');
      final items = await _getItemsForOrder(orderId);
      final payments = await _getPaymentsForOrder(orderId);

      results.add(
        PreOrderEntity.fromMap(
          row.data,
          items: items,
          payments: payments,
        ),
      );
    }

    return results;
  }

  @override
  Future<PreOrderEntity?> getPreOrderById(String id) async {
    await ensureTablesExist();

    final rows = await _db.customSelect(
      'SELECT * FROM pre_orders WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();

    if (rows.isEmpty) return null;

    final row = rows.first;
    final items = await _getItemsForOrder(id);
    final payments = await _getPaymentsForOrder(id);

    return PreOrderEntity.fromMap(
      row.data,
      items: items,
      payments: payments,
    );
  }

  Future<List<PreOrderItemEntity>> _getItemsForOrder(String orderId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM pre_order_items WHERE pre_order_id = ?',
      variables: [Variable.withString(orderId)],
    ).get();

    return rows.map((r) => PreOrderItemEntity.fromMap(r.data)).toList();
  }

  Future<List<PreOrderPaymentEntity>> _getPaymentsForOrder(String orderId) async {
    final rows = await _db.customSelect(
      'SELECT * FROM pre_order_payments WHERE pre_order_id = ? ORDER BY created_at ASC',
      variables: [Variable.withString(orderId)],
    ).get();

    return rows.map((r) => PreOrderPaymentEntity.fromMap(r.data)).toList();
  }

  @override
  Future<PreOrderEntity> insertPreOrder(
    PreOrderEntity order, {
    int initialDepositPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  }) async {
    await ensureTablesExist();

    final branchId = order.branchId.isNotEmpty
        ? order.branchId
        : await _branchProvider.getBranchId();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final orderId = order.id.isNotEmpty ? order.id : _uuid.v4();

    String orderNum = order.orderNumber;
    if (orderNum.isEmpty) {
      final countRow = await _db.customSelect('SELECT COUNT(*) as cnt FROM pre_orders').getSingle();
      final count = (countRow.read<int>('cnt')) + 1001;
      orderNum = 'PO-$count';
    }

    final totalDeposit = initialDepositPiasters > 0 ? initialDepositPiasters : order.depositPiasters;

    await _db.customInsert(
      '''
      INSERT INTO pre_orders (
        id, branch_id, order_number, customer_id, customer_name, customer_phone,
        agent_name, tracking_number, notes, expected_delivery_date,
        total_piasters, deposit_piasters, status, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable.withString(orderId),
        Variable.withString(branchId),
        Variable.withString(orderNum),
        Variable(order.customerId),
        Variable.withString(order.customerName),
        Variable.withString(order.customerPhone),
        Variable(order.agentName),
        Variable(order.trackingNumber),
        Variable(order.notes),
        Variable(
          order.expectedDeliveryDate != null
              ? order.expectedDeliveryDate!.millisecondsSinceEpoch ~/ 1000
              : null,
        ),
        Variable.withInt(order.totalPiasters),
        Variable.withInt(totalDeposit),
        Variable.withString(order.status),
        Variable.withInt(nowSec),
        Variable.withInt(nowSec),
      ],
    );

    // Insert items
    for (final item in order.items) {
      final itemId = item.id.isNotEmpty ? item.id : _uuid.v4();
      await _db.customInsert(
        '''
        INSERT INTO pre_order_items (
          id, pre_order_id, product_name, variant_description, quantity,
          unit_price_piasters, total_price_piasters, cost_price_piasters,
          commission_piasters, item_url, notes, transferred_to_inventory
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable.withString(itemId),
          Variable.withString(orderId),
          Variable.withString(item.productName),
          Variable(item.variantDescription),
          Variable.withInt(item.quantity),
          Variable.withInt(item.unitPricePiasters),
          Variable.withInt(item.totalPricePiasters),
          Variable.withInt(item.costPricePiasters),
          Variable.withInt(item.commissionPiasters),
          Variable(item.itemUrl),
          Variable(item.notes),
          Variable.withInt(0),
        ],
      );
    }

    // Insert initial deposit payment if greater than 0
    if (totalDeposit > 0) {
      final paymentId = _uuid.v4();
      await _db.customInsert(
        '''
        INSERT INTO pre_order_payments (
          id, pre_order_id, branch_id, shift_id, cashier_id,
          amount_piasters, payment_method, notes, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable.withString(paymentId),
          Variable.withString(orderId),
          Variable.withString(branchId),
          Variable(shiftId),
          Variable(cashierId),
          Variable.withInt(totalDeposit),
          Variable.withString(paymentMethod),
          Variable.withString('سند قبض عربون حجز مسبق'),
          Variable.withInt(nowSec),
        ],
      );

      // Record in CashMovements
      await _recordCashMovement(
        branchId: branchId,
        shiftId: shiftId,
        amountPiasters: totalDeposit,
        method: paymentMethod,
        referenceId: orderId,
        notes: 'سند قبض عربون حجز مسبق #$orderNum - ${order.customerName}',
        nowSec: nowSec,
      );
    }

    return (await getPreOrderById(orderId))!;
  }

  @override
  Future<void> addPayment(
    String preOrderId,
    int amountPiasters, {
    String paymentMethod = 'cash',
    String? notes,
    String? shiftId,
    String? cashierId,
  }) async {
    await ensureTablesExist();

    final order = await getPreOrderById(preOrderId);
    if (order == null) throw Exception('طلب الحجز غير موجود');

    final branchId = order.branchId.isNotEmpty
        ? order.branchId
        : await _branchProvider.getBranchId();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final paymentId = _uuid.v4();

    await _db.customInsert(
      '''
      INSERT INTO pre_order_payments (
        id, pre_order_id, branch_id, shift_id, cashier_id,
        amount_piasters, payment_method, notes, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable.withString(paymentId),
        Variable.withString(preOrderId),
        Variable.withString(branchId),
        Variable(shiftId),
        Variable(cashierId),
        Variable.withInt(amountPiasters),
        Variable.withString(paymentMethod),
        Variable(notes ?? 'دفعة وسيطة على حساب الحجز'),
        Variable.withInt(nowSec),
      ],
    );

    final newDeposit = order.depositPiasters + amountPiasters;
    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET deposit_piasters = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withInt(newDeposit),
        Variable.withInt(nowSec),
        Variable.withString(preOrderId),
      ],
    );

    await _recordCashMovement(
      branchId: branchId,
      shiftId: shiftId,
      amountPiasters: amountPiasters,
      method: paymentMethod,
      referenceId: preOrderId,
      notes: 'دفعة حجز مسبق #${order.orderNumber} - ${order.customerName} (${notes ?? ''})',
      nowSec: nowSec,
    );
  }

  @override
  Future<void> markArrivedAtStore(String preOrderId) async {
    await ensureTablesExist();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET status = ?, arrived_at = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(PreOrderStatuses.arrivedAtStore),
        Variable.withInt(nowSec),
        Variable.withInt(nowSec),
        Variable.withString(preOrderId),
      ],
    );
  }

  @override
  Future<void> deliverPreOrder(
    String preOrderId, {
    int finalPaymentPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  }) async {
    await ensureTablesExist();
    final order = await getPreOrderById(preOrderId);
    if (order == null) throw Exception('طلب الحجز غير موجود');

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final branchId = order.branchId.isNotEmpty
        ? order.branchId
        : await _branchProvider.getBranchId();

    int finalDeposit = order.depositPiasters;

    if (finalPaymentPiasters > 0) {
      final paymentId = _uuid.v4();
      await _db.customInsert(
        '''
        INSERT INTO pre_order_payments (
          id, pre_order_id, branch_id, shift_id, cashier_id,
          amount_piasters, payment_method, notes, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable.withString(paymentId),
          Variable.withString(preOrderId),
          Variable.withString(branchId),
          Variable(shiftId),
          Variable(cashierId),
          Variable.withInt(finalPaymentPiasters),
          Variable.withString(paymentMethod),
          Variable.withString('سداد المتبقي عند الاستلام'),
          Variable.withInt(nowSec),
        ],
      );

      await _recordCashMovement(
        branchId: branchId,
        shiftId: shiftId,
        amountPiasters: finalPaymentPiasters,
        method: paymentMethod,
        referenceId: preOrderId,
        notes: 'سداد متبقي حجز مسبق #${order.orderNumber} عند الاستلام',
        nowSec: nowSec,
      );

      finalDeposit += finalPaymentPiasters;
    }

    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET status = ?, deposit_piasters = ?, delivered_at = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(PreOrderStatuses.delivered),
        Variable.withInt(finalDeposit),
        Variable.withInt(nowSec),
        Variable.withInt(nowSec),
        Variable.withString(preOrderId),
      ],
    );
  }

  @override
  Future<void> forfeitDeposit(
    String preOrderId, {
    bool transferItemsToInventory = true,
    String? categoryId,
  }) async {
    await ensureTablesExist();
    final order = await getPreOrderById(preOrderId);
    if (order == null) throw Exception('طلب الحجز غير موجود');

    final now = DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final branchId = order.branchId.isNotEmpty
        ? order.branchId
        : await _branchProvider.getBranchId();

    // 1. Mark status as defaultedForfeited and record forfeited revenue
    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET status = ?, forfeited_at = ?, forfeited_revenue_piasters = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(PreOrderStatuses.defaultedForfeited),
        Variable.withInt(nowSec),
        Variable.withInt(order.depositPiasters),
        Variable.withInt(nowSec),
        Variable.withString(preOrderId),
      ],
    );

    // 2. Transfer items to general store inventory for instant retail sale if requested
    if (transferItemsToInventory && order.items.isNotEmpty) {
      String catId = categoryId ?? '';
      if (catId.isEmpty) {
        final catRows = await (_db.select(_db.categories)..limit(1)).get();
        if (catRows.isNotEmpty) {
          catId = catRows.first.id;
        } else {
          catId = _uuid.v4();
          await _db.into(_db.categories).insert(
            CategoriesCompanion.insert(
              id: catId,
              branchId: branchId,
              name: 'أصناف حجوزات ملغاة ومعروضة',
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }

      for (final item in order.items) {
        if (item.transferredToInventory) continue;

        final productId = _uuid.v4();
        await _db.into(_db.products).insert(
          ProductsCompanion.insert(
            id: productId,
            branchId: branchId,
            name: '${item.productName} (حجز معروض)',
            categoryId: catId,
            description: Value('بضاعة حجز مسبق معروضة للبيع الفوري بعد تعثر الاستلام #${order.orderNumber}'),
            minStock: const Value(1),
            createdAt: now,
            updatedAt: now,
          ),
        );

        final barcode = 'PRE-${DateTime.now().millisecondsSinceEpoch % 1000000}';
        await _db.into(_db.productVariants).insert(
          ProductVariantsCompanion.insert(
            id: _uuid.v4(),
            productId: productId,
            branchId: branchId,
            color: 'عام',
            size: item.variantDescription?.isNotEmpty == true ? item.variantDescription! : 'حر',
            sku: 'SKU-$barcode',
            quantity: Value(item.quantity),
            costPrice: 0, // Cost covered by forfeit/loss accounting
            sellPrice: item.unitPricePiasters,
            wholesalePrice: Value(item.unitPricePiasters),
            createdAt: now,
            updatedAt: now,
          ),
        );

        await _db.customUpdate(
          'UPDATE pre_order_items SET transferred_to_inventory = 1 WHERE id = ?',
          variables: [Variable.withString(item.id)],
        );
      }
    }
  }

  @override
  Future<void> cancelAndRefund(
    String preOrderId, {
    int refundAmountPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  }) async {
    await ensureTablesExist();
    final order = await getPreOrderById(preOrderId);
    if (order == null) throw Exception('طلب الحجز غير موجود');

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final branchId = order.branchId.isNotEmpty
        ? order.branchId
        : await _branchProvider.getBranchId();

    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET status = ?, refunded_at = ?, refunded_piasters = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(PreOrderStatuses.refundedCancelled),
        Variable.withInt(nowSec),
        Variable.withInt(refundAmountPiasters),
        Variable.withInt(nowSec),
        Variable.withString(preOrderId),
      ],
    );

    if (refundAmountPiasters > 0) {
      // Record refund outflow in CashMovements
      await _db.into(_db.cashMovements).insert(
        CashMovementsCompanion(
          id: Value(_uuid.v4()),
          branchId: Value(branchId),
          shiftId: Value(shiftId),
          type: const Value('refund'),
          direction: const Value('out'),
          amountPiasters: Value(refundAmountPiasters),
          method: const Value('cash'),
          referenceId: Value(preOrderId),
          notes: Value(
            'رد عربون حجز مسبق #${order.orderNumber} - ${order.customerName} (${notes ?? ''})',
          ),
          createdAt: Value(nowSec),
          updatedAt: Value(nowSec),
        ),
      );
    }
  }

  @override
  Future<void> deletePreOrder(String preOrderId) async {
    await ensureTablesExist();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _db.customUpdate(
      'UPDATE pre_orders SET deleted_at = ? WHERE id = ?',
      variables: [Variable.withInt(nowSec), Variable.withString(preOrderId)],
    );
  }

  Future<void> _recordCashMovement({
    required String branchId,
    required String? shiftId,
    required int amountPiasters,
    required String method,
    required String referenceId,
    required String notes,
    required int nowSec,
  }) async {
    if (amountPiasters <= 0) return;
    try {
      final mMethod = method == 'card' ? 'card' : (method == 'cash' ? 'cash' : 'transfer');
      await _db.into(_db.cashMovements).insert(
        CashMovementsCompanion(
          id: Value(_uuid.v4()),
          branchId: Value(branchId),
          shiftId: Value(shiftId),
          type: const Value('deposit'),
          direction: const Value('in'),
          amountPiasters: Value(amountPiasters),
          method: Value(mMethod),
          referenceId: Value(referenceId),
          notes: Value(notes),
          createdAt: Value(nowSec),
          updatedAt: Value(nowSec),
        ),
      );
    } catch (_) {
      // Ignore if table constraints differ in older schema
    }
  }
}
