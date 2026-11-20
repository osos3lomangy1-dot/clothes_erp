import 'dart:async';
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/branch_provider.dart';
import '../../domain/entities/delivery_courier_entity.dart';
import '../../domain/entities/delivery_order_entity.dart';

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
    String courierName,
  );
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
}

@LazySingleton(as: DeliveryLocalDataSource)
class DeliveryLocalDataSourceImpl implements DeliveryLocalDataSource {
  final AppDatabase _db;
  final BranchProvider _branchProvider;
  bool _initialized = false;

  DeliveryLocalDataSourceImpl(this._db, this._branchProvider);

  @override
  Future<void> ensureTablesExist() async {
    if (_initialized) return;
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
        created_at INTEGER NOT NULL
      );
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_deliv_orders_status ON delivery_orders(status);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_deliv_orders_courier ON delivery_orders(courier_id);
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
        status, courier_settled, notes, created_at,
        delivered_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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

    if (delivMs != null) {
      await _db.customUpdate(
        '''
        UPDATE delivery_orders
        SET status = ?, delivered_at = ?, updated_at = ?
        WHERE id = ?
        ''',
        variables: [
          Variable.withString(status),
          Variable.withInt(delivMs),
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
    String courierName,
  ) async {
    await ensureTablesExist();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await _db.customUpdate(
      '''
      UPDATE delivery_orders
      SET courier_id = ?, courier_name = ?, status = 'out_for_delivery', updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(courierId),
        Variable.withString(courierName),
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
      INSERT INTO delivery_couriers (id, branch_id, name, phone, is_active, vehicle_type, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable.withString(courier.id),
        Variable.withString(effectiveBranchId),
        Variable.withString(courier.name),
        Variable.withString(courier.phone),
        Variable.withInt(courier.isActive ? 1 : 0),
        Variable(courier.vehicleType),
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
      SET name = ?, phone = ?, is_active = ?, vehicle_type = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withString(courier.name),
        Variable.withString(courier.phone),
        Variable.withInt(courier.isActive ? 1 : 0),
        Variable(courier.vehicleType),
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
  }
}
