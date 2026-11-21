import 'dart:async';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../domain/entities/pre_order_batch_entity.dart';
import '../../domain/entities/pre_order_entity.dart';
import '../../domain/entities/pre_order_item_entity.dart';
import '../../domain/entities/pre_order_payment_entity.dart';

abstract class PreOrdersLocalDataSource {
  Future<void> ensureTablesExist();
  Future<List<PreOrderEntity>> getPreOrders({
    String? status,
    String? searchQuery,
    String? batchId,
  });
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

  // --- الشحنات المجمعة (Batches) ---
  Future<List<PreOrderBatchEntity>> getBatches({
    String? status,
    String? searchQuery,
  });
  Future<PreOrderBatchEntity?> getBatchById(String id);
  Future<PreOrderBatchEntity> insertBatch(
    PreOrderBatchEntity batch,
    List<PreOrderEntity> orders, {
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  });
  Future<void> markBatchArrivedAtStore(String batchId);
  Future<void> deleteBatch(String batchId);

  // --- سيناريوهات الشحنات والبنود الطارئة (Task 8.5.2) ---
  Future<void> attachOrderToBatch(String batchId, String orderId);
  Future<void> applyBatchEmergencyIncrease(
    String batchId,
    int increasePiasters,
    String handledBy,
  );
  Future<void> cancelOrderItem(
    String itemId, {
    required String refundOption,
    int refundPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  });
  Future<void> markOrderItemOutOfStock(
    String itemId, {
    required String refundOption,
    int refundPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  });
  Future<void> markOrderItemDamaged(
    String itemId, {
    bool refundDeposit = true,
    int refundPiasters = 0,
    bool transferToClearance = true,
    String? categoryId,
    String? notes,
    String? shiftId,
    String? cashierId,
  });
  Future<PreOrderEntity> addCustomerToBatch(
    String batchId,
    PreOrderEntity order, {
    int initialDepositPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  });

  // --- إدارة وتعديل الأصناف (Task 8.5.4) ---
  Future<void> updateOrderItem(PreOrderItemEntity item);
  Future<void> deleteOrderItem(String itemId);
  Future<PreOrderItemEntity> addOrderItem(
    String orderId,
    PreOrderItemEntity item,
  );
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
        batch_id TEXT,
        customer_id TEXT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT NOT NULL,
        agent_name TEXT,
        tracking_number TEXT,
        source_platform TEXT,
        notes TEXT,
        expected_delivery_date INTEGER,
        total_piasters INTEGER NOT NULL,
        allocated_shipping_piasters INTEGER NOT NULL DEFAULT 0,
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
      CREATE TABLE IF NOT EXISTS pre_order_batches (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        batch_number TEXT NOT NULL,
        agent_name TEXT,
        tracking_number TEXT,
        total_shipping_piasters INTEGER NOT NULL DEFAULT 0,
        shipping_split_method TEXT NOT NULL DEFAULT 'perItem',
        status TEXT NOT NULL DEFAULT 'pendingProcessing',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        arrived_at INTEGER,
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
        source_platform TEXT,
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
        'ALTER TABLE pre_orders ADD COLUMN batch_id TEXT;',
      );
    } catch (_) {}
    try {
      await _db.customStatement(
        'ALTER TABLE pre_orders ADD COLUMN allocated_shipping_piasters INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await _db.customStatement(
        'CREATE INDEX IF NOT EXISTS idx_pre_orders_batch ON pre_orders(batch_id);',
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
    try {
      await _db.customStatement(
        'ALTER TABLE pre_orders ADD COLUMN emergency_increase_piasters INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await _db.customStatement(
        'ALTER TABLE pre_order_batches ADD COLUMN emergency_increase_piasters INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await _db.customStatement(
        "ALTER TABLE pre_order_batches ADD COLUMN emergency_increase_handled_by TEXT NOT NULL DEFAULT 'merchant';",
      );
    } catch (_) {}
    try {
      await _db.customStatement(
        "ALTER TABLE pre_order_items ADD COLUMN status TEXT NOT NULL DEFAULT 'active';",
      );
    } catch (_) {}
    try {
      await _db.customStatement(
        'ALTER TABLE pre_orders ADD COLUMN source_platform TEXT;',
      );
    } catch (_) {}
    try {
      await _db.customStatement(
        'ALTER TABLE pre_order_items ADD COLUMN source_platform TEXT;',
      );
    } catch (_) {}

    _initialized = true;
  }

  @override
  Future<List<PreOrderEntity>> getPreOrders({
    String? status,
    String? searchQuery,
    String? batchId,
  }) async {
    await ensureTablesExist();

    final whereClauses = <String>['deleted_at IS NULL'];
    final variables = <Variable>[];

    if (batchId != null && batchId.isNotEmpty) {
      whereClauses.add('batch_id = ?');
      variables.add(Variable.withString(batchId));
    }

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
        id, branch_id, order_number, batch_id, customer_id, customer_name, customer_phone,
        agent_name, tracking_number, source_platform, notes, expected_delivery_date,
        total_piasters, allocated_shipping_piasters, emergency_increase_piasters, deposit_piasters, status, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable.withString(orderId),
        Variable.withString(branchId),
        Variable.withString(orderNum),
        Variable(order.batchId),
        Variable(order.customerId),
        Variable.withString(order.customerName),
        Variable.withString(order.customerPhone),
        Variable(order.agentName),
        Variable(order.trackingNumber),
        Variable(order.sourcePlatform),
        Variable(order.notes),
        Variable(
          order.expectedDeliveryDate != null
              ? order.expectedDeliveryDate!.millisecondsSinceEpoch ~/ 1000
              : null,
        ),
        Variable.withInt(order.totalPiasters),
        Variable.withInt(order.allocatedShippingPiasters),
        Variable.withInt(order.emergencyIncreasePiasters),
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
          commission_piasters, item_url, source_platform, notes, transferred_to_inventory, status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
          Variable(item.sourcePlatform),
          Variable(item.notes),
          Variable.withInt(0),
          Variable.withString(item.status),
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

    // If part of a batch, check if all orders in batch are now delivered
    if (order.batchId != null && order.batchId!.isNotEmpty) {
      try {
        final remainingBatchOrders = await _db.customSelect(
          'SELECT COUNT(*) as cnt FROM pre_orders WHERE batch_id = ? AND status != ? AND deleted_at IS NULL',
          variables: [
            Variable.withString(order.batchId!),
            Variable.withString(PreOrderStatuses.delivered),
          ],
        ).getSingle();
        if (remainingBatchOrders.read<int>('cnt') == 0) {
          await _db.customUpdate(
            'UPDATE pre_order_batches SET status = ?, updated_at = ? WHERE id = ?',
            variables: [
              Variable.withString(PreOrderStatuses.delivered),
              Variable.withInt(nowSec),
              Variable.withString(order.batchId!),
            ],
          );
        }
      } catch (_) {}
    }
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

  // ==========================================
  // --- الشحنات المجمعة (Batch Operations) ---
  // ==========================================

  @override
  Future<List<PreOrderBatchEntity>> getBatches({
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
        '(batch_number LIKE ? OR agent_name LIKE ? OR tracking_number LIKE ?)',
      );
      variables.add(Variable.withString(q));
      variables.add(Variable.withString(q));
      variables.add(Variable.withString(q));
    }

    final query = '''
      SELECT * FROM pre_order_batches
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY created_at DESC
    ''';

    final rows = await _db.customSelect(query, variables: variables).get();
    final results = <PreOrderBatchEntity>[];

    for (final row in rows) {
      final batchId = row.read<String>('id');
      final orders = await getPreOrders(batchId: batchId);
      results.add(PreOrderBatchEntity.fromMap(row.data, orders: orders));
    }

    return results;
  }

  @override
  Future<PreOrderBatchEntity?> getBatchById(String id) async {
    await ensureTablesExist();

    final rows = await _db.customSelect(
      'SELECT * FROM pre_order_batches WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();

    if (rows.isEmpty) return null;
    final row = rows.first;
    final orders = await getPreOrders(batchId: id);
    return PreOrderBatchEntity.fromMap(row.data, orders: orders);
  }

  @override
  Future<PreOrderBatchEntity> insertBatch(
    PreOrderBatchEntity batch,
    List<PreOrderEntity> orders, {
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  }) async {
    await ensureTablesExist();

    final branchId = batch.branchId.isNotEmpty
        ? batch.branchId
        : await _branchProvider.getBranchId();
    final batchId = batch.id.isNotEmpty ? batch.id : _uuid.v4();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    String batchNum = batch.batchNumber.trim();
    if (batchNum.isEmpty) {
      final countRow = await _db.customSelect('SELECT COUNT(*) as cnt FROM pre_order_batches').getSingle();
      final count = (countRow.read<int>('cnt')) + 101;
      batchNum = 'BATCH-$count';
    }

    await _db.customInsert(
      '''
      INSERT INTO pre_order_batches (
        id, branch_id, batch_number, agent_name, tracking_number,
        total_shipping_piasters, shipping_split_method,
        emergency_increase_piasters, emergency_increase_handled_by, status,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable.withString(batchId),
        Variable.withString(branchId),
        Variable.withString(batchNum),
        Variable(batch.agentName),
        Variable(batch.trackingNumber),
        Variable.withInt(batch.totalShippingPiasters),
        Variable.withString(batch.shippingSplitMethod),
        Variable.withInt(batch.emergencyIncreasePiasters),
        Variable.withString(batch.emergencyIncreaseHandledBy),
        Variable.withString(batch.status),
        Variable.withInt(nowSec),
        Variable.withInt(nowSec),
      ],
    );

    final insertedOrders = <PreOrderEntity>[];
    for (final order in orders) {
      final updatedOrder = order.copyWith(
        batchId: batchId,
        agentName: order.agentName ?? batch.agentName,
        trackingNumber: order.trackingNumber ?? batch.trackingNumber,
      );
      final created = await insertPreOrder(
        updatedOrder,
        initialDepositPiasters: updatedOrder.depositPiasters,
        paymentMethod: paymentMethod,
        shiftId: shiftId,
        cashierId: cashierId,
      );
      insertedOrders.add(created);
    }

    return batch.copyWith(
      id: batchId,
      branchId: branchId,
      batchNumber: batchNum,
      orders: insertedOrders,
    );
  }

  @override
  Future<void> markBatchArrivedAtStore(String batchId) async {
    await ensureTablesExist();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _db.customUpdate(
      '''
      UPDATE pre_order_batches
      SET status = ?, arrived_at = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(PreOrderStatuses.arrivedAtStore),
        Variable.withInt(nowSec),
        Variable.withInt(nowSec),
        Variable.withString(batchId),
      ],
    );

    // تحويل كافة الأوردرات الفرعية التابعة لهذه الشحنة إلى وصل للمحل
    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET status = ?, arrived_at = ?, updated_at = ?
      WHERE batch_id = ? AND status = ? AND deleted_at IS NULL
      ''',
      variables: [
        Variable.withString(PreOrderStatuses.arrivedAtStore),
        Variable.withInt(nowSec),
        Variable.withInt(nowSec),
        Variable.withString(batchId),
        Variable.withString(PreOrderStatuses.pendingProcessing),
      ],
    );
  }

  @override
  Future<void> deleteBatch(String batchId) async {
    await ensureTablesExist();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _db.customUpdate(
      'UPDATE pre_order_batches SET deleted_at = ? WHERE id = ?',
      variables: [Variable.withInt(nowSec), Variable.withString(batchId)],
    );

    await _db.customUpdate(
      'UPDATE pre_orders SET deleted_at = ? WHERE batch_id = ?',
      variables: [Variable.withInt(nowSec), Variable.withString(batchId)],
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

  // ========================================================
  // --- سيناريوهات الشحنات والبنود الطارئة (Task 8.5.2) ---
  // ========================================================

  @override
  Future<void> attachOrderToBatch(String batchId, String orderId) async {
    await ensureTablesExist();
    final batch = await getBatchById(batchId);
    if (batch == null) throw Exception('الشحنة المجمعة غير موجودة');

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET batch_id = ?,
          agent_name = CASE WHEN agent_name IS NULL OR agent_name = '' THEN ? ELSE agent_name END,
          tracking_number = CASE WHEN tracking_number IS NULL OR tracking_number = '' THEN ? ELSE tracking_number END,
          updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(batchId),
        Variable(batch.agentName),
        Variable(batch.trackingNumber),
        Variable.withInt(nowSec),
        Variable.withString(orderId),
      ],
    );
  }

  @override
  Future<void> applyBatchEmergencyIncrease(
    String batchId,
    int increasePiasters,
    String handledBy,
  ) async {
    await ensureTablesExist();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _db.customUpdate(
      '''
      UPDATE pre_order_batches
      SET emergency_increase_piasters = ?, emergency_increase_handled_by = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withInt(increasePiasters),
        Variable.withString(handledBy),
        Variable.withInt(nowSec),
        Variable.withString(batchId),
      ],
    );

    if (handledBy == 'customers' && increasePiasters > 0) {
      final orders = await getPreOrders(batchId: batchId);
      final totalActivePieces = orders.fold(
        0,
        (sum, o) =>
            sum +
            o.items
                .where((it) => it.isActive)
                .fold(0, (s, it) => s + it.quantity),
      );

      if (totalActivePieces > 0) {
        for (final o in orders) {
          final oPieces = o.items
              .where((it) => it.isActive)
              .fold(0, (s, it) => s + it.quantity);
          final allocated =
              ((increasePiasters * oPieces) / totalActivePieces).round();
          await _db.customUpdate(
            'UPDATE pre_orders SET emergency_increase_piasters = ?, updated_at = ? WHERE id = ?',
            variables: [
              Variable.withInt(allocated),
              Variable.withInt(nowSec),
              Variable.withString(o.id),
            ],
          );
        }
      }
    } else {
      // If merchant absorbs it, clear customer orders emergency increase
      await _db.customUpdate(
        'UPDATE pre_orders SET emergency_increase_piasters = 0, updated_at = ? WHERE batch_id = ?',
        variables: [Variable.withInt(nowSec), Variable.withString(batchId)],
      );
    }
  }

  @override
  Future<void> cancelOrderItem(
    String itemId, {
    required String refundOption,
    int refundPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  }) async {
    await ensureTablesExist();
    final itemRows = await _db.customSelect(
      'SELECT * FROM pre_order_items WHERE id = ?',
      variables: [Variable.withString(itemId)],
    ).get();
    if (itemRows.isEmpty) throw Exception('الصنف غير موجود');
    final item = PreOrderItemEntity.fromMap(itemRows.first.data);

    final order = await getPreOrderById(item.preOrderId);
    if (order == null) throw Exception('طلب الحجز غير موجود');

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final branchId = order.branchId.isNotEmpty
        ? order.branchId
        : await _branchProvider.getBranchId();

    // 1. Mark item status as cancelled
    await _db.customUpdate(
      'UPDATE pre_order_items SET status = ?, notes = ? WHERE id = ?',
      variables: [
        Variable.withString('cancelled'),
        Variable(notes ?? 'ألغي قبل الطلب'),
        Variable.withString(itemId),
      ],
    );

    // 2. Recalculate order total from active items
    final updatedItems = await _getItemsForOrder(order.id);
    final newTotalPiasters = updatedItems
        .where((it) => it.isActive)
        .fold(0, (sum, it) => sum + it.totalPricePiasters);

    int newDeposit = order.depositPiasters;
    int newRefunded = order.refundedPiasters ?? 0;

    // 3. Handle refund if cash option chosen
    if (refundOption == 'cash' && refundPiasters > 0) {
      newDeposit = (order.depositPiasters - refundPiasters).clamp(0, order.depositPiasters);
      newRefunded += refundPiasters;

      await _db.into(_db.cashMovements).insert(
        CashMovementsCompanion(
          id: Value(_uuid.v4()),
          branchId: Value(branchId),
          shiftId: Value(shiftId),
          type: const Value('refund'),
          direction: const Value('out'),
          amountPiasters: Value(refundPiasters),
          method: const Value('cash'),
          referenceId: Value(order.id),
          notes: Value(
            'رد عربون صنف ملغي (${item.productName}) - حجز #${order.orderNumber}',
          ),
          createdAt: Value(nowSec),
          updatedAt: Value(nowSec),
        ),
      );
    }

    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET total_piasters = ?, deposit_piasters = ?, refunded_piasters = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withInt(newTotalPiasters),
        Variable.withInt(newDeposit),
        Variable.withInt(newRefunded),
        Variable.withInt(nowSec),
        Variable.withString(order.id),
      ],
    );
  }

  @override
  Future<void> markOrderItemOutOfStock(
    String itemId, {
    required String refundOption,
    int refundPiasters = 0,
    String? notes,
    String? shiftId,
    String? cashierId,
  }) async {
    await ensureTablesExist();
    final itemRows = await _db.customSelect(
      'SELECT * FROM pre_order_items WHERE id = ?',
      variables: [Variable.withString(itemId)],
    ).get();
    if (itemRows.isEmpty) throw Exception('الصنف غير موجود');
    final item = PreOrderItemEntity.fromMap(itemRows.first.data);

    final order = await getPreOrderById(item.preOrderId);
    if (order == null) throw Exception('طلب الحجز غير موجود');

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final branchId = order.branchId.isNotEmpty
        ? order.branchId
        : await _branchProvider.getBranchId();

    // 1. Mark item as outOfStock
    await _db.customUpdate(
      'UPDATE pre_order_items SET status = ?, notes = ? WHERE id = ?',
      variables: [
        Variable.withString('outOfStock'),
        Variable(notes ?? 'نفد من شي إن / المصدر'),
        Variable.withString(itemId),
      ],
    );

    // 2. Recalculate order total from active items
    final updatedItems = await _getItemsForOrder(order.id);
    final newTotalPiasters = updatedItems
        .where((it) => it.isActive)
        .fold(0, (sum, it) => sum + it.totalPricePiasters);

    int newDeposit = order.depositPiasters;
    int newRefunded = order.refundedPiasters ?? 0;

    if (refundOption == 'cash' && refundPiasters > 0) {
      newDeposit = (order.depositPiasters - refundPiasters).clamp(0, order.depositPiasters);
      newRefunded += refundPiasters;

      await _db.into(_db.cashMovements).insert(
        CashMovementsCompanion(
          id: Value(_uuid.v4()),
          branchId: Value(branchId),
          shiftId: Value(shiftId),
          type: const Value('refund'),
          direction: const Value('out'),
          amountPiasters: Value(refundPiasters),
          method: const Value('cash'),
          referenceId: Value(order.id),
          notes: Value(
            'رد عربون صنف نفد من المصدر (${item.productName}) - حجز #${order.orderNumber}',
          ),
          createdAt: Value(nowSec),
          updatedAt: Value(nowSec),
        ),
      );
    }

    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET total_piasters = ?, deposit_piasters = ?, refunded_piasters = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withInt(newTotalPiasters),
        Variable.withInt(newDeposit),
        Variable.withInt(newRefunded),
        Variable.withInt(nowSec),
        Variable.withString(order.id),
      ],
    );
  }

  @override
  Future<void> markOrderItemDamaged(
    String itemId, {
    bool refundDeposit = true,
    int refundPiasters = 0,
    bool transferToClearance = true,
    String? categoryId,
    String? notes,
    String? shiftId,
    String? cashierId,
  }) async {
    await ensureTablesExist();
    final itemRows = await _db.customSelect(
      'SELECT * FROM pre_order_items WHERE id = ?',
      variables: [Variable.withString(itemId)],
    ).get();
    if (itemRows.isEmpty) throw Exception('الصنف غير موجود');
    final item = PreOrderItemEntity.fromMap(itemRows.first.data);

    final order = await getPreOrderById(item.preOrderId);
    if (order == null) throw Exception('طلب الحجز غير موجود');

    final now = DateTime.now();
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    final branchId = order.branchId.isNotEmpty
        ? order.branchId
        : await _branchProvider.getBranchId();

    // 1. Mark item as damaged
    await _db.customUpdate(
      'UPDATE pre_order_items SET status = ?, notes = ? WHERE id = ?',
      variables: [
        Variable.withString('damaged'),
        Variable(notes ?? 'غير مطابق أو تالف شحن'),
        Variable.withString(itemId),
      ],
    );

    // 2. Transfer to clearance / outlet in products table if requested
    if (transferToClearance && !item.transferredToInventory) {
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
              name: 'ركن التخفيضات والأوتلت',
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }

      final productId = _uuid.v4();
      await _db.into(_db.products).insert(
        ProductsCompanion.insert(
          id: productId,
          branchId: branchId,
          name: '${item.productName} (أوتلت / عيوب شحن)',
          categoryId: catId,
          description: Value(
            'صنف غير مطابق أو تالف شحن معروض بسعر مخفض - حجز #${order.orderNumber}',
          ),
          minStock: const Value(1),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final barcode = 'OUTLET-${nowSec % 1000000}';
      await _db.into(_db.productVariants).insert(
        ProductVariantsCompanion.insert(
          id: _uuid.v4(),
          productId: productId,
          branchId: branchId,
          color: 'عام',
          size: item.variantDescription?.isNotEmpty == true
              ? item.variantDescription!
              : 'حر',
          sku: 'SKU-$barcode',
          quantity: Value(item.quantity),
          costPrice: item.costPricePiasters,
          sellPrice: (item.unitPricePiasters * 0.7).round(), // discounted
          wholesalePrice: Value(item.costPricePiasters),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await _db.customUpdate(
        'UPDATE pre_order_items SET transferred_to_inventory = 1 WHERE id = ?',
        variables: [Variable.withString(itemId)],
      );
    }

    // 3. Deduct from total piasters
    final updatedItems = await _getItemsForOrder(order.id);
    final newTotalPiasters = updatedItems
        .where((it) => it.isActive)
        .fold(0, (sum, it) => sum + it.totalPricePiasters);

    int newDeposit = order.depositPiasters;
    int newRefunded = order.refundedPiasters ?? 0;

    if (refundDeposit && refundPiasters > 0) {
      newDeposit = (order.depositPiasters - refundPiasters).clamp(0, order.depositPiasters);
      newRefunded += refundPiasters;

      await _db.into(_db.cashMovements).insert(
        CashMovementsCompanion(
          id: Value(_uuid.v4()),
          branchId: Value(branchId),
          shiftId: Value(shiftId),
          type: const Value('refund'),
          direction: const Value('out'),
          amountPiasters: Value(refundPiasters),
          method: const Value('cash'),
          referenceId: Value(order.id),
          notes: Value(
            'رد عربون صنف غير مطابق/تالف (${item.productName}) - حجز #${order.orderNumber}',
          ),
          createdAt: Value(nowSec),
          updatedAt: Value(nowSec),
        ),
      );
    }

    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET total_piasters = ?, deposit_piasters = ?, refunded_piasters = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withInt(newTotalPiasters),
        Variable.withInt(newDeposit),
        Variable.withInt(newRefunded),
        Variable.withInt(nowSec),
        Variable.withString(order.id),
      ],
    );
  }

  @override
  Future<PreOrderEntity> addCustomerToBatch(
    String batchId,
    PreOrderEntity order, {
    int initialDepositPiasters = 0,
    String paymentMethod = 'cash',
    String? shiftId,
    String? cashierId,
  }) async {
    final batch = await getBatchById(batchId);
    final updatedOrder = order.copyWith(
      batchId: batchId,
      agentName: order.agentName ?? batch?.agentName,
      trackingNumber: order.trackingNumber ?? batch?.trackingNumber,
    );
    return insertPreOrder(
      updatedOrder,
      initialDepositPiasters: initialDepositPiasters,
      paymentMethod: paymentMethod,
      shiftId: shiftId,
      cashierId: cashierId,
    );
  }

  // ===================================================
  // --- إدارة وتعديل الأصناف وإعادة الحسابات (Task 8.5.4) ---
  // ===================================================

  @override
  Future<void> updateOrderItem(PreOrderItemEntity item) async {
    await ensureTablesExist();
    await _db.customUpdate(
      '''
      UPDATE pre_order_items
      SET product_name = ?,
          variant_description = ?,
          quantity = ?,
          unit_price_piasters = ?,
          total_price_piasters = ?,
          cost_price_piasters = ?,
          commission_piasters = ?,
          item_url = ?,
          source_platform = ?,
          notes = ?,
          status = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(item.productName),
        Variable(item.variantDescription),
        Variable.withInt(item.quantity),
        Variable.withInt(item.unitPricePiasters),
        Variable.withInt(item.totalPricePiasters),
        Variable.withInt(item.costPricePiasters),
        Variable.withInt(item.commissionPiasters),
        Variable(item.itemUrl),
        Variable(item.sourcePlatform),
        Variable(item.notes),
        Variable.withString(item.status),
        Variable.withString(item.id),
      ],
    );

    await _recalculateOrderAndBatch(item.preOrderId);
  }

  @override
  Future<void> deleteOrderItem(String itemId) async {
    await ensureTablesExist();
    final itemRows = await _db.customSelect(
      'SELECT pre_order_id FROM pre_order_items WHERE id = ?',
      variables: [Variable.withString(itemId)],
    ).get();
    if (itemRows.isEmpty) return;
    final orderId = itemRows.first.read<String>('pre_order_id');

    await _db.customUpdate(
      'DELETE FROM pre_order_items WHERE id = ?',
      variables: [Variable.withString(itemId)],
    );

    await _recalculateOrderAndBatch(orderId);
  }

  @override
  Future<PreOrderItemEntity> addOrderItem(
    String orderId,
    PreOrderItemEntity item,
  ) async {
    await ensureTablesExist();
    final itemId = item.id.isNotEmpty ? item.id : _uuid.v4();
    await _db.customInsert(
      '''
      INSERT INTO pre_order_items (
        id, pre_order_id, product_name, variant_description, quantity,
        unit_price_piasters, total_price_piasters, cost_price_piasters,
        commission_piasters, item_url, source_platform, notes, transferred_to_inventory, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        Variable(item.sourcePlatform),
        Variable(item.notes),
        Variable.withInt(0),
        Variable.withString(item.status),
      ],
    );

    await _recalculateOrderAndBatch(orderId);

    final createdRows = await _db.customSelect(
      'SELECT * FROM pre_order_items WHERE id = ?',
      variables: [Variable.withString(itemId)],
    ).get();
    return PreOrderItemEntity.fromMap(createdRows.first.data);
  }

  Future<void> _recalculateOrderAndBatch(String orderId) async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final items = await _getItemsForOrder(orderId);
    final newTotalPiasters = items
        .where((it) => it.isActive)
        .fold(0, (sum, it) => sum + it.totalPricePiasters);

    await _db.customUpdate(
      '''
      UPDATE pre_orders
      SET total_piasters = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withInt(newTotalPiasters),
        Variable.withInt(nowSec),
        Variable.withString(orderId),
      ],
    );

    final orderRows = await _db.customSelect(
      'SELECT batch_id FROM pre_orders WHERE id = ?',
      variables: [Variable.withString(orderId)],
    ).get();

    if (orderRows.isNotEmpty) {
      final batchId = orderRows.first.readNullable<String>('batch_id');
      if (batchId != null && batchId.isNotEmpty) {
        await _recalculateBatchAllocations(batchId);
      }
    }
  }

  Future<void> _recalculateBatchAllocations(String batchId) async {
    final batch = await getBatchById(batchId);
    if (batch == null) return;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final orders = await getPreOrders(batchId: batchId);
    if (orders.isEmpty) return;

    if (batch.totalShippingPiasters > 0) {
      if (batch.shippingSplitMethod == ShippingSplitMethods.perItem) {
        final totalActivePieces = orders.fold(
          0,
          (sum, o) =>
              sum +
              o.items
                  .where((it) => it.isActive)
                  .fold(0, (s, it) => s + it.quantity),
        );
        if (totalActivePieces > 0) {
          for (final o in orders) {
            final oPieces = o.items
                .where((it) => it.isActive)
                .fold(0, (s, it) => s + it.quantity);
            final allocated =
                ((batch.totalShippingPiasters * oPieces) / totalActivePieces)
                    .round();
            await _db.customUpdate(
              'UPDATE pre_orders SET allocated_shipping_piasters = ?, updated_at = ? WHERE id = ?',
              variables: [
                Variable.withInt(allocated),
                Variable.withInt(nowSec),
                Variable.withString(o.id),
              ],
            );
          }
        }
      } else if (batch.shippingSplitMethod ==
          ShippingSplitMethods.equalPerCustomer) {
        final perCustomer = (batch.totalShippingPiasters / orders.length).round();
        for (final o in orders) {
          await _db.customUpdate(
            'UPDATE pre_orders SET allocated_shipping_piasters = ?, updated_at = ? WHERE id = ?',
            variables: [
              Variable.withInt(perCustomer),
              Variable.withInt(nowSec),
              Variable.withString(o.id),
            ],
          );
        }
      }
    }

    if (batch.emergencyIncreaseHandledBy == 'customers' &&
        batch.emergencyIncreasePiasters > 0) {
      final totalActivePieces = orders.fold(
        0,
        (sum, o) =>
            sum +
            o.items
                .where((it) => it.isActive)
                .fold(0, (s, it) => s + it.quantity),
      );
      if (totalActivePieces > 0) {
        for (final o in orders) {
          final oPieces = o.items
              .where((it) => it.isActive)
              .fold(0, (s, it) => s + it.quantity);
          final allocated =
              ((batch.emergencyIncreasePiasters * oPieces) / totalActivePieces)
                  .round();
          await _db.customUpdate(
            'UPDATE pre_orders SET emergency_increase_piasters = ?, updated_at = ? WHERE id = ?',
            variables: [
              Variable.withInt(allocated),
              Variable.withInt(nowSec),
              Variable.withString(o.id),
            ],
          );
        }
      }
    }
  }
}
