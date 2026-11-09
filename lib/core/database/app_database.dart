import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Users extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get username => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get role => text()();
  TextColumn get passwordHash => text()();
  TextColumn get passwordSalt => text()();
  TextColumn get pinHash => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get salary => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get description => text().nullable()();
  IntColumn get minStock => integer().withDefault(const Constant(5))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ProductVariants extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get sku => text()();
  TextColumn get color => text()();
  TextColumn get size => text()();
  IntColumn get quantity => integer().withDefault(const Constant(0))();
  IntColumn get costPrice => integer()();
  IntColumn get sellPrice => integer()();
  IntColumn get wholesalePrice => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (quantity >= 0)',
    'CHECK (cost_price >= 0)',
    'CHECK (sell_price >= 0)',
  ];

  @override
  Set<Column> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get shortRef => text().unique()();
  TextColumn get cashierId => text()();
  TextColumn get shiftId => text().nullable()();
  TextColumn get customerId => text().nullable()();
  IntColumn get subtotal => integer()();
  TextColumn get discountType => text()();
  IntColumn get discountValue => integer().withDefault(const Constant(0))();
  IntColumn get discountAmount => integer().withDefault(const Constant(0))();
  IntColumn get total => integer()();
  TextColumn get paymentMethod => text()();
  TextColumn get note => text().nullable()();
  TextColumn get approvedByAdminId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (total >= 0)',
    'CHECK (subtotal >= 0)',
    'CHECK (discount_amount >= 0)',
  ];

  @override
  Set<Column> get primaryKey => {id};
}

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get variantId => text()();
  TextColumn get productName => text()();
  TextColumn get color => text()();
  TextColumn get size => text()();
  IntColumn get qty => integer()();
  IntColumn get priceSnapshot => integer()();
  IntColumn get costSnapshot => integer()();
  IntColumn get lineDiscount => integer().withDefault(const Constant(0))();
  IntColumn get lineTotal => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'CHECK (qty > 0)',
    'CHECK (price_snapshot >= 0)',
    'CHECK (cost_snapshot >= 0)',
    'CHECK (line_total >= 0)',
  ];

  @override
  Set<Column> get primaryKey => {id};
}

class Returns extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get saleId => text().nullable()();
  TextColumn get cashierId => text()();
  TextColumn get reason => text()();
  IntColumn get refundAmount => integer()();
  TextColumn get paymentMethod => text()();
  TextColumn get approvedByAdminId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
    "CHECK (reason <> '')",
  ];

  @override
  Set<Column> get primaryKey => {id};
}

class ReturnItems extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get returnId => text().references(Returns, #id)();
  TextColumn get saleItemId => text().nullable()();
  TextColumn get variantId => text()();
  IntColumn get qty => integer()();
  IntColumn get refundUnitPrice => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<String> get customConstraints => [
    'CHECK (qty > 0)',
    'CHECK (refund_unit_price >= 0)',
  ];

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_inventory_logs_variantId_createdAt', columns: {#variantId, #createdAt})
class InventoryLogs extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get variantId => text()();
  TextColumn get type => text()();
  IntColumn get qtyDelta => integer()();
  TextColumn get refType => text()();
  TextColumn get refId => text().nullable()();
  TextColumn get reason => text().nullable()();
  TextColumn get userId => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Shifts extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get cashierId => text()();
  IntColumn get openingBalance => integer()();
  DateTimeColumn get openedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  IntColumn get expectedBalance => integer().nullable()();
  IntColumn get countedBalance => integer().nullable()();
  IntColumn get difference => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (opening_balance >= 0)',
  ];

  @override
  Set<Column> get primaryKey => {id};
}

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get category => text()();
  IntColumn get amount => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get userId => text()();
  DateTimeColumn get expenseDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (amount > 0)',
  ];

  @override
  Set<Column> get primaryKey => {id};
}

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().unique()();
  IntColumn get loyaltyPoints => integer().withDefault(const Constant(0))();
  IntColumn get discountPercent => integer().withDefault(const Constant(0))();
  TextColumn get customerType => text().withDefault(const Constant('retail'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Stocktakes extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get cashierId => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get approvedByAdminId => text().nullable()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class StocktakeItems extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get stocktakeId => text().references(Stocktakes, #id)();
  TextColumn get variantId => text()();
  IntColumn get expectedQty => integer()();
  IntColumn get countedQty => integer()();
  IntColumn get difference => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class DailyStats extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  DateTimeColumn get date => dateTime()();
  IntColumn get salesTotal => integer().withDefault(const Constant(0))();
  IntColumn get salesCount => integer().withDefault(const Constant(0))();
  IntColumn get returnsTotal => integer().withDefault(const Constant(0))();
  IntColumn get discountsTotal => integer().withDefault(const Constant(0))();
  IntColumn get costTotal => integer().withDefault(const Constant(0))();
  IntColumn get cashTotal => integer().withDefault(const Constant(0))();
  IntColumn get visaTotal => integer().withDefault(const Constant(0))();
  IntColumn get expensesTotal => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get userId => text()();
  TextColumn get action => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'idx_sync_queue_status_createdAt', columns: {#status, #createdAt})
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AppMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get companyName => text().nullable()();
  TextColumn get address => text().nullable()();
  IntColumn get balance => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Purchases extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get supplierId => text()();
  TextColumn get invoiceNumber => text().nullable()();
  DateTimeColumn get purchaseDate => dateTime()();
  IntColumn get totalAmount => integer()();
  IntColumn get paidAmount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, received, cancelled
  TextColumn get paymentStatus => text().withDefault(const Constant('unpaid'))(); // unpaid, partial, paid
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class PurchaseItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseId => text()();
  TextColumn get variantId => text()();
  IntColumn get qty => integer()();
  IntColumn get costPrice => integer()();
  IntColumn get totalCost => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class SupplierPayments extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get supplierId => text()();
  TextColumn get purchaseId => text().nullable()();
  IntColumn get amount => integer()();
  DateTimeColumn get paymentDate => dateTime()();
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class LoyaltyTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get customerId => text()();
  TextColumn get saleId => text().nullable()();
  IntColumn get pointsDelta => integer()();
  TextColumn get reason => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Users, Categories, Products, ProductVariants, Sales, SaleItems,
  Returns, ReturnItems, InventoryLogs, Shifts, Expenses, Customers,
  Stocktakes, StocktakeItems, DailyStats, AuditLogs, SyncQueue, AppMeta,
  Suppliers, Purchases, PurchaseItems, SupplierPayments, LoyaltyTransactions,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'clothes_erp'));

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await customStatement(
        'CREATE UNIQUE INDEX idx_variants_sku_unique ON product_variants(sku) WHERE deleted_at IS NULL',
      );
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        Future<void> safeAddColumn(String tableName, String columnName, TableInfo table, GeneratedColumn col) async {
          final result = await customSelect('PRAGMA table_info("$tableName")').get();
          final cols = result.map((r) => (r.data['name'] as String).toLowerCase()).toSet();
          if (!cols.contains(columnName.toLowerCase())) {
            await m.addColumn(table, col);
          }
        }

        await safeAddColumn('product_variants', 'wholesale_price', productVariants, productVariants.wholesalePrice);
        await safeAddColumn('customers', 'discount_percent', customers, customers.discountPercent);
        await safeAddColumn('customers', 'customer_type', customers, customers.customerType);
        await safeAddColumn('users', 'salary', users, users.salary);
      }

      if (from < 3) {
        Future<void> safeCreateTable(String tableName, TableInfo table) async {
          final result = await customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='$tableName'",
          ).get();
          if (result.isEmpty) {
            await m.createTable(table);
          }
        }

        await safeCreateTable('suppliers', suppliers);
        await safeCreateTable('purchases', purchases);
        await safeCreateTable('purchase_items', purchaseItems);
        await safeCreateTable('supplier_payments', supplierPayments);
        await safeCreateTable('loyalty_transactions', loyaltyTransactions);

        // Seed default loyalty configuration in app_meta if not already present
        final now = DateTime.now();
        Future<void> seedMeta(String key, String value) async {
          final existing = await (select(appMeta)..where((t) => t.key.equals(key))).getSingleOrNull();
          if (existing == null) {
            await into(appMeta).insert(
              AppMetaCompanion.insert(key: key, value: value, updatedAt: now),
            );
          }
        }

        await seedMeta('loyalty_earn_rate', '10');
        await seedMeta('loyalty_redeem_rate', '10');
        await seedMeta('loyalty_max_redeem_percent', '30');
      }
    },
    beforeOpen: (details) async {
      Future<void> addColumnIfNotExists(String table, String column, String definition) async {
        try {
          final result = await customSelect('PRAGMA table_info("$table")').get();
          final columnNames = result.map((row) => (row.data['name'] as String).toLowerCase()).toSet();
          if (!columnNames.contains(column.toLowerCase())) {
            await customStatement('ALTER TABLE "$table" ADD COLUMN "$column" $definition');
          }
        } catch (_) {}
      }

      await addColumnIfNotExists('product_variants', 'wholesale_price', 'INTEGER NOT NULL DEFAULT 0');
      await addColumnIfNotExists('customers', 'discount_percent', 'INTEGER NOT NULL DEFAULT 0');
      await addColumnIfNotExists('customers', 'customer_type', "TEXT NOT NULL DEFAULT 'retail'");
      await addColumnIfNotExists('users', 'salary', 'INTEGER NOT NULL DEFAULT 0');
    },
  );
}
