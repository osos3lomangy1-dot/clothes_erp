import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
import '../utils/logging.dart';
import 'tables/promotions.dart';
import 'tables/promotion_targets.dart';

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

  // Multi-Activity & Adaptive Attributes Engine (Task 8.6)
  TextColumn get activityType =>
      text().withDefault(const Constant('clothing'))();
  TextColumn get warrantyPeriod => text().nullable()();
  TextColumn get brandOrModel => text().nullable()();
  BoolColumn get isInstallmentEligible =>
      boolean().withDefault(const Constant(true))();

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
  IntColumn get promotionDiscountPiasters =>
      integer().withDefault(const Constant(0))();
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
  List<String> get customConstraints => ["CHECK (reason <> '')"];

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

@TableIndex(
  name: 'idx_inventory_logs_variantId_createdAt',
  columns: {#variantId, #createdAt},
)
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
  List<String> get customConstraints => ['CHECK (opening_balance >= 0)'];

  @override
  Set<Column> get primaryKey => {id};
}

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get category => text()();
  IntColumn get amount => integer()();
  TextColumn get kind => text()
      .withDefault(const Constant('operating'))
      .check(
        const CustomExpression<bool>(
          "kind IN ('operating', 'supplier_payment')",
        ),
      )();
  TextColumn get note => text().nullable()();
  TextColumn get userId => text()();
  DateTimeColumn get expenseDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  List<String> get customConstraints => ['CHECK (amount > 0)'];

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
  IntColumn get creditLimit => integer().withDefault(const Constant(0))(); // in piasters (0 = unconstrained)
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

@TableIndex(
  name: 'idx_sync_queue_status_createdAt',
  columns: {#status, #createdAt},
)
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
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending, received, cancelled
  TextColumn get paymentStatus =>
      text().withDefault(const Constant('unpaid'))(); // unpaid, partial, paid
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

class CustomerPayments extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get saleId => text().nullable()();
  TextColumn get shiftId => text().nullable()();
  IntColumn get amount => integer()();
  DateTimeColumn get paymentDate => dateTime()();
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))();
  TextColumn get referenceNumber => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

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

class GoodsReceipts extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get cashierId => text()();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get status => text().withDefault(
    const Constant('pending'),
  )(); // pending, invoiced, cancelled
  IntColumn get totalItems => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class GoodsReceiptItems extends Table {
  TextColumn get id => text()();
  TextColumn get receiptId => text()();
  TextColumn get variantId => text()();
  IntColumn get quantity => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class InstallmentPlans extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get durationMonths => integer()();
  IntColumn get downPaymentPiasters =>
      integer().withDefault(const Constant(0))();
  IntColumn get interestBp => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK(duration_months >= 1 AND duration_months <= 120)',
    'CHECK(down_payment_piasters >= 0)',
    'CHECK(interest_bp >= 0 AND interest_bp <= 10000)',
  ];
}

class CustomerInstallments extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get saleId => text()();
  TextColumn get customerId => text()();
  TextColumn get planId => text().nullable()();
  IntColumn get totalPiasters => integer()();
  IntColumn get downPaymentPiasters =>
      integer().withDefault(const Constant(0))();
  IntColumn get principalPiasters => integer()();
  IntColumn get interestBp => integer()();
  IntColumn get monthlyAmountPiasters => integer()();
  IntColumn get remainingPiasters => integer()();
  IntColumn get durationMonths => integer()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK(status IN ('active','completed','overdue','cancelled'))",
    "CHECK(principal_piasters = total_piasters - down_payment_piasters)",
    'CHECK(total_piasters >= 0)',
    'CHECK(down_payment_piasters >= 0)',
    'CHECK(principal_piasters >= 0)',
    'CHECK(interest_bp >= 0 AND interest_bp <= 10000)',
    'CHECK(monthly_amount_piasters >= 0)',
    'CHECK(remaining_piasters >= 0)',
    'CHECK(duration_months >= 1 AND duration_months <= 120)',
  ];
}

class InstallmentPayments extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get customerInstallmentId => text()();
  IntColumn get amountPiasters => integer()();
  TextColumn get paymentMethod => text()();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get receiptNumber => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get recordedBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK(payment_method IN ('cash','card'))",
    'CHECK(amount_piasters > 0)',
  ];
}

class CashMovements extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get shiftId => text().nullable()();
  TextColumn get type => text()();
  TextColumn get method => text()();
  TextColumn get direction => text()();
  IntColumn get amountPiasters => integer()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (type IN ("
        "'sale','refund',"
        "'purchase_payment','supplier_payment',"
        "'expense','deposit','withdrawal',"
        "'installment_down','installment_payment',"
        "'purchase_reversal','supplier_payment_reversal','expense_reversal'"
        "))",
    "CHECK (method IN ('cash','card','transfer'))",
    "CHECK (direction IN ('in','out'))",
    "CHECK (amount_piasters > 0)",
    "CHECK ("
        "  (type = 'sale' AND direction = 'in') OR "
        "  (type = 'refund' AND direction = 'out') OR "
        "  (type = 'purchase_payment' AND direction = 'out') OR "
        "  (type = 'supplier_payment' AND direction = 'out') OR "
        "  (type = 'expense' AND direction = 'out') OR "
        "  (type = 'deposit' AND direction = 'in') OR "
        "  (type = 'withdrawal' AND direction = 'out') OR "
        "  (type = 'installment_down' AND direction = 'in') OR "
        "  (type = 'installment_payment' AND direction = 'in') OR "
        "  (type = 'purchase_reversal' AND direction = 'in') OR "
        "  (type = 'supplier_payment_reversal' AND direction = 'in') OR "
        "  (type = 'expense_reversal' AND direction = 'in')"
        ")",
  ];
}

class SalePayments extends Table {
  TextColumn get id => text()();
  TextColumn get branchId => text()();
  TextColumn get saleId => text()();
  TextColumn get method => text()();
  IntColumn get amountPiasters => integer()();
  TextColumn get shiftId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (method IN ('cash', 'card'))",
    "CHECK (amount_piasters > 0)",
  ];
}

void _setupSqlite(CommonDatabase rawDb) {
  rawDb.execute('PRAGMA journal_mode = WAL;');
  rawDb.execute('PRAGMA synchronous = NORMAL;');
  rawDb.execute('PRAGMA busy_timeout = 5000;');
  try {
    final v = rawDb.select('SELECT sqlite_version() AS v;');
    if (v.isNotEmpty) {
      Logging.info('[SQLite Runtime Version] ${v.first['v']}');
    }
  } catch (_) {}
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'clothes_erp',
    native: DriftNativeOptions(
      shareAcrossIsolates: true,
      setup: _setupSqlite,
      databaseDirectory: () async {
        final supportDir = await getApplicationSupportDirectory();
        try {
          if (!supportDir.existsSync()) {
            await supportDir.create(recursive: true);
          }
          final targetFile = File('${supportDir.path}/clothes_erp.sqlite');
          // Apply any staged backup restore atomically BEFORE SQLite opens the DB
          final pendingRestore = File('${targetFile.path}.pending_restore');
          if (pendingRestore.existsSync()) {
            if (Platform.isWindows && targetFile.existsSync()) {
              try {
                await Process.run('attrib', ['-r', targetFile.path]);
              } catch (_) {}
            }
            for (final suffix in const ['-wal', '-shm']) {
              final sidecar = File('${targetFile.path}$suffix');
              if (sidecar.existsSync()) {
                try {
                  await sidecar.delete();
                } catch (_) {}
              }
            }
            if (targetFile.existsSync()) {
              await targetFile.delete();
            }
            try {
              await pendingRestore.rename(targetFile.path);
            } catch (_) {
              await pendingRestore.copy(targetFile.path);
              if (pendingRestore.existsSync()) {
                await pendingRestore.delete();
              }
            }
          }
          if (targetFile.existsSync()) {
            if (Platform.isWindows) {
              try {
                await Process.run('attrib', ['-r', targetFile.path]);
              } catch (_) {}
            }
          } else {
            // Migrate existing database from previous app identity (com.example\clothes_erp)
            // or legacy Documents path so upgrading to Bay3ah preserves all user data!
            final candidates = <File>[];
            if (Platform.isWindows) {
              final appData = Platform.environment['APPDATA'];
              if (appData != null && appData.isNotEmpty) {
                candidates.add(File('$appData\\com.example\\clothes_erp\\clothes_erp.sqlite'));
              }
            }
            final docsDir = await getApplicationDocumentsDirectory();
            candidates.add(File('${docsDir.path}/clothes_erp.sqlite'));

            for (final legacyFile in candidates) {
              if (legacyFile.existsSync()) {
                await legacyFile.copy(targetFile.path);
                if (Platform.isWindows) {
                  try {
                    await Process.run('attrib', ['-r', targetFile.path]);
                  } catch (_) {}
                }
                break;
              }
            }
          }
        } catch (_) {}
        return supportDir;
      },
    ),
  );
}

@DriftDatabase(
  tables: [
    Users,
    Categories,
    Products,
    ProductVariants,
    Sales,
    SaleItems,
    Returns,
    ReturnItems,
    InventoryLogs,
    Shifts,
    Expenses,
    Customers,
    Stocktakes,
    StocktakeItems,
    DailyStats,
    AuditLogs,
    SyncQueue,
    AppMeta,
    Suppliers,
    Purchases,
    PurchaseItems,
    SupplierPayments,
    CustomerPayments,
    LoyaltyTransactions,
    GoodsReceipts,
    GoodsReceiptItems,
    InstallmentPlans,
    CustomerInstallments,
    InstallmentPayments,
    CashMovements,
    SalePayments,
    Promotions,
    PromotionApplications,
    PromotionTargets,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 11;

  /// Checkpoints committed WAL frames into the main database file.
  /// Called after POS checkout to guarantee zero receipt loss on sudden power cuts.
  Future<void> flushWal() async {
    try {
      await customStatement('PRAGMA wal_checkpoint(PASSIVE);');
    } catch (_) {}
  }

  @visibleForTesting
  Future<void> migrateToV6(Migrator m) async {
    final result = await customSelect('PRAGMA table_info("expenses")').get();
    final cols = result
        .map((r) => (r.data['name'] as String).toLowerCase())
        .toSet();
    if (!cols.contains('kind')) {
      await m.addColumn(expenses, expenses.kind);
    }
    await customStatement('''
      UPDATE expenses
      SET kind = 'supplier_payment'
      WHERE category IN ('مشتريات بضاعة', 'سداد موردين')
        AND kind = 'operating'
    ''');
  }

  @visibleForTesting
  Future<void> backfillCashMovements() async {
    // 1. Sales (excluding customer installments and already backfilled)
    await customStatement('''
      INSERT INTO cash_movements
        (id, branch_id, shift_id, type, method, direction, amount_piasters, reference_id, notes, created_at, updated_at)
      SELECT
        lower(hex(randomblob(16))),
        s.branch_id,
        s.shift_id,
        'sale',
        CASE WHEN lower(s.payment_method) = 'card' THEN 'card' WHEN lower(s.payment_method) = 'transfer' THEN 'transfer' ELSE 'cash' END,
        'in',
        s.total,
        s.id,
        'مبيعات نقدية / شبكة',
        s.created_at,
        s.updated_at
      FROM sales s
      WHERE s.deleted_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM customer_installments ci
          WHERE ci.sale_id = s.id AND ci.deleted_at IS NULL
        )
        AND NOT EXISTS (
          SELECT 1 FROM cash_movements cm
          WHERE cm.reference_id = s.id AND cm.type = 'sale'
        );
    ''');

    // 2. Supplier payments
    await customStatement('''
      INSERT INTO cash_movements
        (id, branch_id, shift_id, type, method, direction, amount_piasters, reference_id, notes, created_at, updated_at)
      SELECT
        lower(hex(randomblob(16))),
        sp.branch_id,
        NULL,
        'supplier_payment',
        CASE WHEN lower(sp.payment_method) = 'card' THEN 'card' WHEN lower(sp.payment_method) = 'transfer' THEN 'transfer' ELSE 'cash' END,
        'out',
        sp.amount,
        sp.id,
        sp.notes,
        sp.created_at,
        sp.created_at
      FROM supplier_payments sp
      WHERE NOT EXISTS (
        SELECT 1 FROM cash_movements cm
        WHERE cm.reference_id = sp.id AND cm.type = 'supplier_payment'
      );
    ''');

    // 3. Purchases advance payments (where paid_amount > 0 and NOT already in supplier_payments)
    await customStatement('''
      INSERT INTO cash_movements
        (id, branch_id, shift_id, type, method, direction, amount_piasters, reference_id, notes, created_at, updated_at)
      SELECT
        lower(hex(randomblob(16))),
        p.branch_id,
        NULL,
        'purchase_payment',
        'cash',
        'out',
        p.paid_amount,
        p.id,
        p.notes,
        p.created_at,
        p.updated_at
      FROM purchases p
      WHERE p.deleted_at IS NULL
        AND p.paid_amount > 0
        AND NOT EXISTS (
          SELECT 1 FROM supplier_payments sp
          WHERE sp.purchase_id = p.id
        )
        AND NOT EXISTS (
          SELECT 1 FROM cash_movements cm
          WHERE cm.reference_id = p.id AND cm.type = 'purchase_payment'
        );
    ''');

    // 4. Returns (refunds)
    await customStatement('''
      INSERT INTO cash_movements
        (id, branch_id, shift_id, type, method, direction, amount_piasters, reference_id, notes, created_at, updated_at)
      SELECT
        lower(hex(randomblob(16))),
        r.branch_id,
        NULL,
        'refund',
        CASE WHEN lower(r.payment_method) = 'card' THEN 'card' WHEN lower(r.payment_method) = 'transfer' THEN 'transfer' ELSE 'cash' END,
        'out',
        r.refund_amount,
        r.id,
        r.reason,
        r.created_at,
        r.updated_at
      FROM returns r
      WHERE r.deleted_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM cash_movements cm
          WHERE cm.reference_id = r.id AND cm.type = 'refund'
        );
    ''');

    // 5. Installment down payments (from customer_installments)
    await customStatement('''
      INSERT INTO cash_movements
        (id, branch_id, shift_id, type, method, direction, amount_piasters, reference_id, notes, created_at, updated_at)
      SELECT
        lower(hex(randomblob(16))),
        ci.branch_id,
        s.shift_id,
        'installment_down',
        'cash',
        'in',
        ci.down_payment_piasters,
        ci.id,
        'مقدم عقد تقسيط',
        ci.created_at,
        ci.updated_at
      FROM customer_installments ci
      LEFT JOIN sales s ON s.id = ci.sale_id
      WHERE ci.deleted_at IS NULL
        AND ci.down_payment_piasters > 0
        AND NOT EXISTS (
          SELECT 1 FROM cash_movements cm
          WHERE cm.reference_id = ci.id AND cm.type = 'installment_down'
        );
    ''');

    // 6. Installment payments
    await customStatement('''
      INSERT INTO cash_movements
        (id, branch_id, shift_id, type, method, direction, amount_piasters, reference_id, notes, created_at, updated_at)
      SELECT
        lower(hex(randomblob(16))),
        ip.branch_id,
        NULL,
        'installment_payment',
        CASE WHEN lower(ip.payment_method) = 'card' THEN 'card' WHEN lower(ip.payment_method) = 'transfer' THEN 'transfer' ELSE 'cash' END,
        'in',
        ip.amount_piasters,
        ip.id,
        ip.notes,
        ip.created_at,
        ip.updated_at
      FROM installment_payments ip
      WHERE ip.deleted_at IS NULL
        AND COALESCE(ip.receipt_number, '') != 'INTEREST_WAIVER'
        AND NOT EXISTS (
          SELECT 1 FROM cash_movements cm
          WHERE cm.reference_id = ip.id AND cm.type = 'installment_payment'
        );
    ''');

    // 7. Operating expenses
    await customStatement('''
      INSERT INTO cash_movements
        (id, branch_id, shift_id, type, method, direction, amount_piasters, reference_id, notes, created_at, updated_at)
      SELECT
        lower(hex(randomblob(16))),
        e.branch_id,
        NULL,
        'expense',
        'cash',
        'out',
        e.amount,
        e.id,
        e.note,
        e.created_at,
        e.updated_at
      FROM expenses e
      WHERE e.deleted_at IS NULL
        AND e.kind = 'operating'
        AND NOT EXISTS (
          SELECT 1 FROM cash_movements cm
          WHERE cm.reference_id = e.id AND cm.type = 'expense'
        );
    ''');
  }

  @visibleForTesting
  Future<void> migrateToV7(Migrator m) async {
    // 1. Detect open shift (Correction 3: closed_at IS NULL)
    final openShiftRow = await customSelect(
      'SELECT id FROM shifts WHERE closed_at IS NULL AND deleted_at IS NULL LIMIT 1',
    ).getSingleOrNull();

    if (openShiftRow != null) {
      final openShiftId = openShiftRow.read<String>('id');
      // Correction 2: timestamps in SECONDS
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await customStatement(
        'INSERT OR REPLACE INTO app_meta ("key", "value", "updated_at") VALUES (?, ?, ?)',
        ['migration_v7_open_shift_id', openShiftId, nowSec],
      );
    }

    // 2. Create cash_movements table if missing
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='cash_movements'",
    ).get();
    if (tables.isEmpty) {
      await m.createTable(cashMovements);
    }

    // 3. Backfill cash movements
    await backfillCashMovements();
  }

  @visibleForTesting
  Future<void> migrateToV8(Migrator m) async {
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sale_payments'",
    ).get();
    if (tables.isEmpty) {
      await m.createTable(salePayments);
    }
    await customStatement('''
      INSERT INTO sale_payments
        (id, branch_id, sale_id, method, amount_piasters, shift_id, created_at, updated_at)
      SELECT
        lower(hex(randomblob(16))),
        s.branch_id,
        s.id,
        CASE WHEN lower(s.payment_method) = 'card' THEN 'card' ELSE 'cash' END,
        s.total,
        s.shift_id,
        s.created_at,
        s.updated_at
      FROM sales s
      WHERE s.deleted_at IS NULL
        AND s.total > 0
        AND NOT EXISTS (
          SELECT 1 FROM customer_installments ci
          WHERE ci.sale_id = s.id AND ci.deleted_at IS NULL
        )
        AND NOT EXISTS (
          SELECT 1 FROM sale_payments sp
          WHERE sp.sale_id = s.id
        );
    ''');
  }

  @visibleForTesting
  Future<void> migrateToV9(Migrator m) async {
    final promoTables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='promotions'",
    ).get();
    if (promoTables.isEmpty) {
      await m.createTable(promotions);
    }

    final appTables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='promotion_applications'",
    ).get();
    if (appTables.isEmpty) {
      await m.createTable(promotionApplications);
    }

    final saleItemCols = await customSelect(
      'PRAGMA table_info("sale_items")',
    ).get();
    final cols = saleItemCols
        .map((r) => (r.data['name'] as String).toLowerCase())
        .toSet();
    if (!cols.contains('promotion_discount_piasters')) {
      await m.addColumn(saleItems, saleItems.promotionDiscountPiasters);
    }
  }

  @visibleForTesting
  Future<void> migrateToV10(Migrator m) async {
    final targetsTables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='promotion_targets'",
    ).get();
    if (targetsTables.isEmpty) {
      await m.createTable(promotionTargets);
    }

    await customStatement('''
      INSERT INTO promotion_targets
        (id, branch_id, promotion_id, target_type, target_id, created_at)
      SELECT
        lower(hex(randomblob(16))),
        p.branch_id,
        p.id,
        p.scope,
        p.target_id,
        p.created_at
      FROM promotions p
      WHERE p.target_id IS NOT NULL
        AND p.scope IN ('product', 'category')
        AND p.deleted_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM promotion_targets pt
          WHERE pt.promotion_id = p.id
            AND pt.target_id = p.target_id
        );
    ''');
  }

  @visibleForTesting
  Future<void> migrateToV11(Migrator m) async {
    final payTables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='customer_payments'",
    ).get();
    if (payTables.isEmpty) {
      await m.createTable(customerPayments);
    }

    final custCols = await customSelect('PRAGMA table_info("customers")').get();
    final cols = custCols.map((r) => (r.data['name'] as String).toLowerCase()).toSet();
    if (!cols.contains('credit_limit')) {
      await m.addColumn(customers, customers.creditLimit);
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await customStatement(
        'CREATE UNIQUE INDEX idx_variants_sku_unique ON product_variants(sku) WHERE deleted_at IS NULL',
      );
    },
    onUpgrade: (Migrator m, int from, int to) async {
      await m.database.transaction(() async {
        if (from < 2) {
          Future<void> safeAddColumn(
            String tableName,
            String columnName,
            TableInfo table,
            GeneratedColumn col,
          ) async {
            final result = await customSelect(
              'PRAGMA table_info("$tableName")',
            ).get();
            final cols = result
                .map((r) => (r.data['name'] as String).toLowerCase())
                .toSet();
            if (!cols.contains(columnName.toLowerCase())) {
              await m.addColumn(table, col);
            }
          }

          await safeAddColumn(
            'product_variants',
            'wholesale_price',
            productVariants,
            productVariants.wholesalePrice,
          );
          await safeAddColumn(
            'customers',
            'discount_percent',
            customers,
            customers.discountPercent,
          );
          await safeAddColumn(
            'customers',
            'customer_type',
            customers,
            customers.customerType,
          );
          await safeAddColumn('users', 'salary', users, users.salary);
        }

        if (from < 3) {
          await m.createTable(suppliers);
          await m.createTable(purchases);
          await m.createTable(purchaseItems);
          await m.createTable(supplierPayments);
          await m.createTable(loyaltyTransactions);

          final nowMs = DateTime.now().millisecondsSinceEpoch;
          await customStatement(
            'INSERT OR IGNORE INTO app_meta ("key", "value", "updated_at") VALUES '
            "('loyalty_earn_rate', '10', $nowMs), "
            "('loyalty_redeem_rate', '10', $nowMs), "
            "('loyalty_max_redeem_percent', '30', $nowMs);",
          );
        }

        if (from < 4) {
          await m.createTable(goodsReceipts);
          await m.createTable(goodsReceiptItems);
        }

        if (from < 5) {
          await m.createTable(installmentPlans);
          await m.createTable(customerInstallments);
          await m.createTable(installmentPayments);
        }

        if (from < 6 && to >= 6) {
          await migrateToV6(m);
        }

        if (from < 7 && to >= 7) {
          await migrateToV7(m);
        }

        if (from < 8 && to >= 8) {
          await migrateToV8(m);
        }

        if (from < 9 && to >= 9) {
          await migrateToV9(m);
        }

        if (from < 10 && to >= 10) {
          await migrateToV10(m);
        }

        if (from < 11 && to >= 11) {
          await migrateToV11(m);
        }

        // Commit target user_version inside the transaction to eliminate the post-commit window
        await m.database.customStatement('PRAGMA user_version = $to;');
      });
    },
    beforeOpen: (details) async {
      Future<void> addColumnIfNotExists(
        String table,
        String column,
        String definition,
      ) async {
        try {
          final result = await customSelect(
            'PRAGMA table_info("$table")',
          ).get();
          final columnNames = result
              .map((row) => (row.data['name'] as String).toLowerCase())
              .toSet();
          if (!columnNames.contains(column.toLowerCase())) {
            await customStatement(
              'ALTER TABLE "$table" ADD COLUMN "$column" $definition',
            );
          }
        } catch (_) {}
      }

      Future<void> createTableIfNotExists(
        String table,
        TableInfo tableInfo,
      ) async {
        try {
          final result = await customSelect(
            'SELECT name FROM sqlite_master WHERE type="table" AND name="$table"',
          ).get();
          if (result.isEmpty) {
            final m = Migrator(this);
            await m.createTable(tableInfo);
          }
        } catch (_) {}
      }

      await createTableIfNotExists('goods_receipts', goodsReceipts);
      await createTableIfNotExists('goods_receipt_items', goodsReceiptItems);
      await createTableIfNotExists('installment_plans', installmentPlans);
      await createTableIfNotExists(
        'customer_installments',
        customerInstallments,
      );
      await createTableIfNotExists('installment_payments', installmentPayments);
      await createTableIfNotExists('cash_movements', cashMovements);
      await createTableIfNotExists('sale_payments', salePayments);
      await createTableIfNotExists('promotions', promotions);
      await createTableIfNotExists(
        'promotion_applications',
        promotionApplications,
      );
      await createTableIfNotExists('customer_payments', customerPayments);

      await addColumnIfNotExists(
        'product_variants',
        'wholesale_price',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await addColumnIfNotExists(
        'customers',
        'discount_percent',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await addColumnIfNotExists(
        'customers',
        'customer_type',
        "TEXT NOT NULL DEFAULT 'retail'",
      );
      await addColumnIfNotExists(
        'customers',
        'credit_limit',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await addColumnIfNotExists(
        'users',
        'salary',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await addColumnIfNotExists(
        'expenses',
        'kind',
        "TEXT NOT NULL DEFAULT 'operating' CHECK (kind IN ('operating', 'supplier_payment'))",
      );
      await addColumnIfNotExists(
        'sale_items',
        'promotion_discount_piasters',
        'INTEGER NOT NULL DEFAULT 0',
      );
      await addColumnIfNotExists(
        'products',
        'activity_type',
        "TEXT NOT NULL DEFAULT 'clothing'",
      );
      await addColumnIfNotExists(
        'products',
        'warranty_period',
        'TEXT',
      );
      await addColumnIfNotExists(
        'products',
        'brand_or_model',
        'TEXT',
      );
      await addColumnIfNotExists(
        'products',
        'is_installment_eligible',
        'INTEGER NOT NULL DEFAULT 1',
      );
    },
  );
}

Future<String?> getMigrationOpenShiftBannerMessage(AppDatabase db) async {
  final row =
      await (db.select(db.appMeta)
            ..where((t) => t.key.equals('migration_v7_open_shift_id')))
          .getSingleOrNull();
  if (row == null || row.value.isEmpty) return null;
  return 'وردية ${row.value} كانت مفتوحة أثناء ترقية قاعدة البيانات. راجع حركاتها قبل الإغلاق.';
}
