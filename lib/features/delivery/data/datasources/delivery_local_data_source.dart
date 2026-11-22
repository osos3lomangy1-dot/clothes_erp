import 'dart:async';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../domain/entities/delivery_courier_entity.dart';
import '../../domain/entities/delivery_order_entity.dart';
import '../../domain/entities/shipping_company_payout_entity.dart';

abstract class DeliveryLocalDataSource {
  Future<void> ensureTablesExist();
  Future<void> insertDeliveryOrder(DeliveryOrderEntity order);
  Future<void> updateDeliveryStatus(
    String orderId,
    String status, {
    DateTime? deliveredAt,
  });
  Future<void> assignCourier(
    String orderId,
    String courierId,
    String courierName, {
    String? waybillNumber,
    int? shippingCostPiasters,
  });
  Future<List<DeliveryOrderEntity>> getDeliveryOrders({
    String? status,
    String? courierId,
    DateTime? from,
    DateTime? to,
  });
  Future<List<DeliveryCourierEntity>> getCouriers();
  Future<void> insertCourier(DeliveryCourierEntity courier);
  Future<void> updateCourier(DeliveryCourierEntity courier);
  Future<void> settleCourierOrders(String courierId, List<String> orderIds);
  Future<void> recordShippingCompanyPayout(ShippingCompanyPayoutEntity payout);
  Future<List<ShippingCompanyPayoutEntity>> getShippingCompanyPayouts(String courierId);
  Future<void> reconcileShippingBatch(String courierId, List<String> orderIds, String batchId);
}

@LazySingleton(as: DeliveryLocalDataSource)
class DeliveryLocalDataSourceImpl implements DeliveryLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  final _uuid = const Uuid();
  bool _initialized = false;

  DeliveryLocalDataSourceImpl(this._db, this._branchProvider);

  @override
  Future<void> ensureTablesExist() async {
    if (_initialized) return;

    // 1. Create base tables
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS delivery_orders (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        sale_id TEXT,
        order_ref TEXT NOT NULL,
        customer_id TEXT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT NOT NULL,
        delivery_address TEXT NOT NULL,
        courier_id TEXT,
        courier_name TEXT,
        delivery_fee_piasters INTEGER NOT NULL DEFAULT 0,
        order_total_piasters INTEGER NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cod',
        payment_status TEXT NOT NULL DEFAULT 'pending',
        status TEXT NOT NULL DEFAULT 'preparing',
        courier_settled INTEGER NOT NULL DEFAULT 0,
        provider_type TEXT NOT NULL DEFAULT 'in_house',
        shipping_fee_payer TEXT NOT NULL DEFAULT 'store_collected',
        waybill_number TEXT,
        shipping_cost_piasters INTEGER,
        shipping_batch_id TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        delivered_at INTEGER,
        updated_at INTEGER NOT NULL
      );
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS delivery_couriers (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        vehicle_type TEXT,
        provider_type TEXT NOT NULL DEFAULT 'in_house',
        tracking_url_template TEXT,
        default_rate_piasters INTEGER,
        account_number TEXT,
        created_at INTEGER NOT NULL
      );
    ''');

    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS shipping_company_payouts (
        id TEXT PRIMARY KEY,
        branch_id TEXT NOT NULL,
        courier_id TEXT NOT NULL,
        amount_piasters INTEGER NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'bank_transfer',
        reference_number TEXT,
        notes TEXT,
        payout_date INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');

    // 2. Migration for existing tables (alter table defensively)
    final alterations = [
      "ALTER TABLE delivery_orders ADD COLUMN provider_type TEXT NOT NULL DEFAULT 'in_house'",
      "ALTER TABLE delivery_orders ADD COLUMN shipping_fee_payer TEXT NOT NULL DEFAULT 'store_collected'",
      "ALTER TABLE delivery_orders ADD COLUMN waybill_number TEXT",
      "ALTER TABLE delivery_orders ADD COLUMN shipping_cost_piasters INTEGER",
      "ALTER TABLE delivery_orders ADD COLUMN shipping_batch_id TEXT",
      "ALTER TABLE delivery_couriers ADD COLUMN provider_type TEXT NOT NULL DEFAULT 'in_house'",
      "ALTER TABLE delivery_couriers ADD COLUMN tracking_url_template TEXT",
      "ALTER TABLE delivery_couriers ADD COLUMN default_rate_piasters INTEGER",
      "ALTER TABLE delivery_couriers ADD COLUMN account_number TEXT",
    ];

    for (final alt in alterations) {
      try {
        await _db.customStatement(alt);
      } catch (_) {
        // Column already exists, safe to ignore
      }
    }

    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_deliv_orders_status ON delivery_orders(status);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_deliv_orders_courier ON delivery_orders(courier_id);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_shipping_payouts_courier ON shipping_company_payouts(courier_id);
    ''');

    _initialized = true;
  }

  @override
  Future<void> insertDeliveryOrder(DeliveryOrderEntity order) async {
    await ensureTablesExist();
    final effectiveBranchId = order.branchId.isNotEmpty
        ? order.branchId
        : await _branchProvider.getBranchId();

    await _db.customInsert(
      '''
      INSERT INTO delivery_orders (
        id, branch_id, sale_id, order_ref, customer_id,
        customer_name, customer_phone, delivery_address,
        courier_id, courier_name, delivery_fee_piasters,
        order_total_piasters, payment_method, payment_status,
        status, courier_settled, provider_type, shipping_fee_payer,
        waybill_number, shipping_cost_piasters, shipping_batch_id,
        notes, created_at, delivered_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable.withString(order.id),
        Variable.withString(effectiveBranchId),
        Variable(order.saleId),
        Variable.withString(order.orderRef),
        Variable(order.customerId),
        Variable.withString(order.customerName),
        Variable.withString(order.customerPhone),
        Variable.withString(order.deliveryAddress),
        Variable(order.courierId),
        Variable(order.courierName),
        Variable.withInt(order.deliveryFeePiasters),
        Variable.withInt(order.orderTotalPiasters),
        Variable.withString(order.paymentMethod),
        Variable.withString(order.paymentStatus),
        Variable.withString(order.status),
        Variable.withInt(order.courierSettled ? 1 : 0),
        Variable.withString(order.providerType),
        Variable.withString(order.shippingFeePayer),
        Variable(order.waybillNumber),
        Variable(order.shippingCostPiasters),
        Variable(order.shippingBatchId),
        Variable(order.notes),
        Variable.withInt(order.createdAt.millisecondsSinceEpoch),
        Variable(order.deliveredAt?.millisecondsSinceEpoch),
        Variable.withInt(order.updatedAt.millisecondsSinceEpoch),
      ],
    );
  }

  @override
  Future<void> updateDeliveryStatus(
    String orderId,
    String status, {
    DateTime? deliveredAt,
  }) async {
    await ensureTablesExist();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final delivMs = deliveredAt?.millisecondsSinceEpoch;

    if (deliveredAt != null) {
      await _db.customUpdate(
        '''
        UPDATE delivery_orders
        SET status = ?, delivered_at = ?, updated_at = ?
        WHERE id = ?
        ''',
        variables: [
          Variable.withString(status),
          Variable.withInt(delivMs!),
          Variable.withInt(nowMs),
          Variable.withString(orderId),
        ],
      );
    } else {
      await _db.customUpdate(
        '''
        UPDATE delivery_orders
        SET status = ?, updated_at = ?
        WHERE id = ?
        ''',
        variables: [
          Variable.withString(status),
          Variable.withInt(nowMs),
          Variable.withString(orderId),
        ],
      );
    }
  }

  @override
  Future<void> assignCourier(
    String orderId,
    String courierId,
    String courierName, {
    String? waybillNumber,
    int? shippingCostPiasters,
  }) async {
    await ensureTablesExist();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // Check provider type of the courier
    final courierRows = await _db.customSelect(
      'SELECT provider_type, default_rate_piasters FROM delivery_couriers WHERE id = ?',
      variables: [Variable.withString(courierId)],
    ).get();

    String providerType = 'in_house';
    int? effectiveCost = shippingCostPiasters;

    if (courierRows.isNotEmpty) {
      providerType = courierRows.first.data['provider_type'] as String? ?? 'in_house';
      effectiveCost ??= (courierRows.first.data['default_rate_piasters'] as num?)?.toInt();
    }

    await _db.customUpdate(
      '''
      UPDATE delivery_orders
      SET courier_id = ?, courier_name = ?, provider_type = ?,
          waybill_number = COALESCE(?, waybill_number),
          shipping_cost_piasters = COALESCE(?, shipping_cost_piasters),
          status = CASE WHEN status = 'preparing' THEN 'out_for_delivery' ELSE status END,
          updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(courierId),
        Variable.withString(courierName),
        Variable.withString(providerType),
        Variable(waybillNumber),
        Variable(effectiveCost),
        Variable.withInt(nowMs),
        Variable.withString(orderId),
      ],
    );
  }

  @override
  Future<List<DeliveryOrderEntity>> getDeliveryOrders({
    String? status,
    String? courierId,
    DateTime? from,
    DateTime? to,
  }) async {
    await ensureTablesExist();
    var sql = 'SELECT * FROM delivery_orders WHERE 1=1';
    final vars = <Variable>[];

    if (status != null && status != 'all') {
      sql += ' AND status = ?';
      vars.add(Variable.withString(status));
    }
    if (courierId != null && courierId.isNotEmpty) {
      sql += ' AND courier_id = ?';
      vars.add(Variable.withString(courierId));
    }
    if (from != null) {
      sql += ' AND created_at >= ?';
      vars.add(Variable.withInt(from.millisecondsSinceEpoch));
    }
    if (to != null) {
      sql += ' AND created_at <= ?';
      vars.add(Variable.withInt(to.millisecondsSinceEpoch));
    }

    sql += ' ORDER BY created_at DESC';

    final rows = await _db.customSelect(sql, variables: vars).get();
    return rows.map((row) {
      final data = row.data;
      return DeliveryOrderEntity(
        id: data['id'] as String,
        branchId: data['branch_id'] as String,
        saleId: data['sale_id'] as String?,
        orderRef: data['order_ref'] as String,
        customerId: data['customer_id'] as String?,
        customerName: data['customer_name'] as String,
        customerPhone: data['customer_phone'] as String,
        deliveryAddress: data['delivery_address'] as String,
        courierId: data['courier_id'] as String?,
        courierName: data['courier_name'] as String?,
        deliveryFeePiasters: (data['delivery_fee_piasters'] as num).toInt(),
        orderTotalPiasters: (data['order_total_piasters'] as num).toInt(),
        paymentMethod: data['payment_method'] as String? ?? 'cod',
        paymentStatus: data['payment_status'] as String? ?? 'pending',
        status: data['status'] as String? ?? 'preparing',
        courierSettled: (data['courier_settled'] as num? ?? 0) == 1,
        providerType: data['provider_type'] as String? ?? 'in_house',
        shippingFeePayer: data['shipping_fee_payer'] as String? ?? 'store_collected',
        waybillNumber: data['waybill_number'] as String?,
        shippingCostPiasters: (data['shipping_cost_piasters'] as num?)?.toInt(),
        shippingBatchId: data['shipping_batch_id'] as String?,
        notes: data['notes'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (data['created_at'] as num).toInt(),
        ),
        deliveredAt: data['delivered_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (data['delivered_at'] as num).toInt(),
              )
            : null,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (data['updated_at'] as num).toInt(),
        ),
      );
    }).toList();
  }

  @override
  Future<List<DeliveryCourierEntity>> getCouriers() async {
    await ensureTablesExist();
    final rows = await _db.customSelect(
      'SELECT * FROM delivery_couriers WHERE is_active = 1 ORDER BY name ASC',
    ).get();

    return rows.map((row) {
      final data = row.data;
      return DeliveryCourierEntity(
        id: data['id'] as String,
        branchId: data['branch_id'] as String,
        name: data['name'] as String,
        phone: data['phone'] as String,
        isActive: (data['is_active'] as num? ?? 1) == 1,
        vehicleType: data['vehicle_type'] as String?,
        providerType: data['provider_type'] as String? ?? 'in_house',
        trackingUrlTemplate: data['tracking_url_template'] as String?,
        defaultRatePiasters: (data['default_rate_piasters'] as num?)?.toInt(),
        accountNumber: data['account_number'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (data['created_at'] as num).toInt(),
        ),
      );
    }).toList();
  }

  @override
  Future<void> insertCourier(DeliveryCourierEntity courier) async {
    await ensureTablesExist();
    final effectiveBranchId = courier.branchId.isNotEmpty
        ? courier.branchId
        : await _branchProvider.getBranchId();

    await _db.customInsert(
      '''
      INSERT INTO delivery_couriers (
        id, branch_id, name, phone, is_active, vehicle_type,
        provider_type, tracking_url_template, default_rate_piasters,
        account_number, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable.withString(courier.id),
        Variable.withString(effectiveBranchId),
        Variable.withString(courier.name),
        Variable.withString(courier.phone),
        Variable.withInt(courier.isActive ? 1 : 0),
        Variable(courier.vehicleType),
        Variable.withString(courier.providerType),
        Variable(courier.trackingUrlTemplate),
        Variable(courier.defaultRatePiasters),
        Variable(courier.accountNumber),
        Variable.withInt(courier.createdAt.millisecondsSinceEpoch),
      ],
    );
  }

  @override
  Future<void> updateCourier(DeliveryCourierEntity courier) async {
    await ensureTablesExist();
    await _db.customUpdate(
      '''
      UPDATE delivery_couriers
      SET name = ?, phone = ?, is_active = ?, vehicle_type = ?,
          provider_type = ?, tracking_url_template = ?,
          default_rate_piasters = ?, account_number = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(courier.name),
        Variable.withString(courier.phone),
        Variable.withInt(courier.isActive ? 1 : 0),
        Variable(courier.vehicleType),
        Variable.withString(courier.providerType),
        Variable(courier.trackingUrlTemplate),
        Variable(courier.defaultRatePiasters),
        Variable(courier.accountNumber),
        Variable.withString(courier.id),
      ],
    );
  }

  @override
  Future<void> settleCourierOrders(
    String courierId,
    List<String> orderIds,
  ) async {
    await ensureTablesExist();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 1. Fetch orders being settled to calculate net cash handover
    final orders = await getDeliveryOrders(courierId: courierId);
    final targeted = orders.where((o) => orderIds.contains(o.id) && o.status == 'delivered').toList();

    int totalCashCollected = 0;
    for (final o in targeted) {
      if (o.paymentMethod == 'cod') {
        totalCashCollected += o.grandTotalPiasters;
      }
    }

    // 2. Mark orders as settled
    for (final id in orderIds) {
      await _db.customUpdate(
        '''
        UPDATE delivery_orders
        SET courier_settled = 1, payment_status = 'collected', updated_at = ?
        WHERE id = ? AND courier_id = ?
        ''',
        variables: [
          Variable.withInt(nowMs),
          Variable.withString(id),
          Variable.withString(courierId),
        ],
      );
    }

    // 3. If in-house courier: perform direct cash-in to active cashier shift
    final couriers = await getCouriers();
    final courier = couriers.firstWhere(
      (c) => c.id == courierId,
      orElse: () => DeliveryCourierEntity(
        id: courierId,
        branchId: 'default',
        name: 'طيار',
        phone: '',
        createdAt: DateTime.now(),
      ),
    );

    if (courier.isInHouse && totalCashCollected > 0) {
      try {
        final shiftRows = await _db.customSelect(
          'SELECT id, branch_id FROM shifts WHERE closed_at IS NULL AND deleted_at IS NULL ORDER BY opened_at DESC LIMIT 1',
        ).get();

        if (shiftRows.isNotEmpty) {
          final activeShiftId = shiftRows.first.data['id'] as String;
          final shiftBranchId = shiftRows.first.data['branch_id'] as String;

          await _db.customInsert(
            '''
            INSERT INTO cash_movements (
              id, branch_id, shift_id, type, method, direction,
              amount_piasters, reference_id, notes, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            variables: [
              Variable.withString(_uuid.v4()),
              Variable.withString(shiftBranchId),
              Variable.withString(activeShiftId),
              Variable.withString('deposit'),
              Variable.withString('cash'),
              Variable.withString('in'),
              Variable.withInt(totalCashCollected),
              Variable.withString(courierId),
              Variable.withString('توريد كاش دليفري - الطيار: ${courier.name} - إجمالي ${orderIds.length} طلبات'),
              Variable.withInt(DateTime.now().millisecondsSinceEpoch ~/ 1000),
              Variable.withInt(DateTime.now().millisecondsSinceEpoch ~/ 1000),
            ],
          );
        }
      } catch (_) {
        // Table or shift might not exist in isolated test contexts
      }
    }
  }

  @override
  Future<void> recordShippingCompanyPayout(ShippingCompanyPayoutEntity payout) async {
    await ensureTablesExist();
    final effectiveBranchId = payout.branchId.isNotEmpty
        ? payout.branchId
        : await _branchProvider.getBranchId();

    await _db.customInsert(
      '''
      INSERT INTO shipping_company_payouts (
        id, branch_id, courier_id, amount_piasters, payment_method,
        reference_number, notes, payout_date, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable.withString(payout.id),
        Variable.withString(effectiveBranchId),
        Variable.withString(payout.courierId),
        Variable.withInt(payout.amountPiasters),
        Variable.withString(payout.paymentMethod),
        Variable(payout.referenceNumber),
        Variable(payout.notes),
        Variable.withInt(payout.payoutDate.millisecondsSinceEpoch),
        Variable.withInt(payout.createdAt.millisecondsSinceEpoch),
      ],
    );
  }

  @override
  Future<List<ShippingCompanyPayoutEntity>> getShippingCompanyPayouts(String courierId) async {
    await ensureTablesExist();
    final rows = await _db.customSelect(
      'SELECT * FROM shipping_company_payouts WHERE courier_id = ? ORDER BY payout_date DESC',
      variables: [Variable.withString(courierId)],
    ).get();

    return rows.map((r) {
      final data = r.data;
      return ShippingCompanyPayoutEntity(
        id: data['id'] as String,
        branchId: data['branch_id'] as String,
        courierId: data['courier_id'] as String,
        amountPiasters: (data['amount_piasters'] as num).toInt(),
        paymentMethod: data['payment_method'] as String? ?? 'bank_transfer',
        referenceNumber: data['reference_number'] as String?,
        notes: data['notes'] as String?,
        payoutDate: DateTime.fromMillisecondsSinceEpoch((data['payout_date'] as num).toInt()),
        createdAt: DateTime.fromMillisecondsSinceEpoch((data['created_at'] as num).toInt()),
      );
    }).toList();
  }

  @override
  Future<void> reconcileShippingBatch(String courierId, List<String> orderIds, String batchId) async {
    await ensureTablesExist();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final id in orderIds) {
      await _db.customUpdate(
        '''
        UPDATE delivery_orders
        SET shipping_batch_id = ?, courier_settled = 1, payment_status = 'collected', updated_at = ?
        WHERE id = ? AND courier_id = ?
        ''',
        variables: [
          Variable.withString(batchId),
          Variable.withInt(nowMs),
          Variable.withString(id),
          Variable.withString(courierId),
        ],
      );
    }
  }
}
