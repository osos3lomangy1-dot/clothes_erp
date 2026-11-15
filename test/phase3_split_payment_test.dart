import 'package:clothes_erp/core/database/app_database.dart';
import 'package:clothes_erp/core/database/branch_provider.dart';
import 'package:clothes_erp/core/database/tx_writer.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';
import 'package:clothes_erp/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:clothes_erp/features/auth/data/models/user_model.dart';
import 'package:clothes_erp/features/categories/domain/repositories/category_repository.dart';
import 'package:clothes_erp/features/installments/data/repositories/installments_facade_impl.dart';
import 'package:clothes_erp/features/installments/data/services/manager_pin_service.dart';
import 'package:clothes_erp/features/installments/domain/services/installment_calculator.dart';
import 'package:clothes_erp/features/inventory/data/datasources/inventory_local_data_source.dart';
import 'package:clothes_erp/features/pos/data/datasources/pos_local_data_source.dart';
import 'package:clothes_erp/features/pos/domain/entities/payment_split.dart';
import 'package:clothes_erp/features/pos/domain/entities/sale_item_entity.dart';
import 'package:clothes_erp/features/pos/domain/repositories/pos_repository.dart';
import 'package:clothes_erp/features/pos/presentation/cubits/pos_cubit.dart';
import 'package:clothes_erp/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:clothes_erp/features/pos/domain/usecases/create_sale_usecase.dart';
import 'package:clothes_erp/features/product_variants/domain/repositories/variant_repository.dart';
import 'package:clothes_erp/features/products/domain/repositories/product_repository.dart';
import 'package:clothes_erp/features/reports/data/datasources/reports_local_data_source.dart';
import 'package:clothes_erp/features/returns/data/datasources/returns_local_data_source.dart';
import 'package:clothes_erp/features/returns/domain/entities/return_item_entity.dart';
import 'package:clothes_erp/features/shifts/data/datasources/shift_local_data_source.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBranchProvider extends BranchProvider {
  _FakeBranchProvider(super.db);
  @override
  Future<String> getBranchId() async => 'branch-1';
}

class _FakeInventoryLocalDataSource implements InventoryLocalDataSource {
  @override
  Future<void> applyStockMovement({
    required String variantId,
    required int qtyDelta,
    required StockMovementType type,
    String? reason,
    String? userId,
    String? refType,
    String? refId,
    int? customCostSnapshot,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthLocalDataSource implements AuthLocalDataSource {
  UserModel? _user;
  @override
  Future<void> cacheUser(UserModel user) async => _user = user;
  @override
  Future<UserModel?> getCachedUser() async => _user;
  @override
  Future<void> clearCache() async => _user = null;
}

class _TestManagerPinService extends ManagerPinService {
  _TestManagerPinService(
    super.db,
    super.txWriter,
    super.branchProvider,
    super.auth,
    super.featureGate,
  );

  @override
  Future<bool> isPinRequired() async => true;

  @override
  Future<PinVerificationResult> verifyPin({
    required String pin,
    required String operation,
    DateTime? now,
  }) async {
    if (pin == '1234') {
      return const PinVerificationResult.success();
    }
    return const PinVerificationResult.failure('الرقم السري للمدير غير صحيح');
  }
}

class _DummyVariantRepo implements VariantRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DummyCategoryRepo implements CategoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DummyProductRepo implements ProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPosCubit extends PosCubit {
  _TestPosCubit(CreateSaleUseCase useCase, PosRepository posRepo)
      : super(
          useCase,
          _DummyVariantRepo(),
          _DummyCategoryRepo(),
          _DummyProductRepo(),
          posRepo,
        );

  void setCart(int total) {
    emit(PosLoaded(
      cart: const [
        SaleItemEntity(
          variantId: 'v-1',
          productName: 'Item',
          color: 'Blue',
          size: 'M',
          quantity: 1,
          price: 10000,
        ),
      ],
      total: total,
      subtotal: total,
    ));
  }
}

void main() {
  group('Phase 3 — Split Payment + Two-Section Report Tests', () {
    late AppDatabase db;
    late BranchProvider branchProvider;
    late TxWriter txWriter;
    late InventoryLocalDataSource inventory;
    late PosLocalDataSource posDataSource;
    late ShiftLocalDataSource shiftDataSource;
    late ReturnsLocalDataSource returnsDataSource;
    late ReportsLocalDataSource reportsDataSource;
    late InstallmentsFacadeImpl installmentsFacade;
    late PosRepositoryImpl posRepo;
    late CreateSaleUseCase createSaleUseCase;
    late _FakeAuthLocalDataSource authDataSource;
    late FeatureGate featureGate;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      branchProvider = _FakeBranchProvider(db);
      txWriter = TxWriter(db);
      inventory = _FakeInventoryLocalDataSource();
      authDataSource = _FakeAuthLocalDataSource();
      final now = DateTime.now();

      await authDataSource.cacheUser(UserModel(
        id: 'user-1',
        name: 'Test Cashier',
        email: 'cashier@test.com',
        role: 'admin',
        isActive: true,
        createdAt: now,
      ));

      featureGate = FeatureGate(db, authDataSource, txWriter, branchProvider);
      posRepo = PosRepositoryImpl(PosLocalDataSource(db, branchProvider, txWriter, inventory), featureGate);
      posDataSource = PosLocalDataSource(db, branchProvider, txWriter, inventory);
      createSaleUseCase = CreateSaleUseCase(posRepo);

      shiftDataSource = ShiftLocalDataSourceImpl(db, branchProvider, txWriter, featureGate);
      returnsDataSource = ReturnsLocalDataSourceImpl(db, branchProvider, txWriter, inventory);
      reportsDataSource = ReportsLocalDataSourceImpl(db);
      installmentsFacade = InstallmentsFacadeImpl(
        db,
        txWriter,
        branchProvider,
        authDataSource,
        featureGate,
        _TestManagerPinService(db, txWriter, branchProvider, authDataSource, featureGate),
      );

      // Seed an active shift
      await db.into(db.shifts).insert(ShiftsCompanion.insert(
        id: 'shift-phase3',
        branchId: 'branch-1',
        cashierId: 'user-1',
        openedAt: now,
        openingBalance: 10000,
        createdAt: now,
        updatedAt: now,
      ));

      // Enable feature gates for test
      await db.into(db.appMeta).insert(AppMetaCompanion.insert(
        key: 'feature.installments',
        value: '1',
        updatedAt: now,
      ));
      await db.into(db.appMeta).insert(AppMetaCompanion.insert(
        key: 'feature.customers',
        value: '1',
        updatedAt: now,
      ));
      await db.into(db.appMeta).insert(AppMetaCompanion.insert(
        key: 'feature.pos',
        value: '1',
        updatedAt: now,
      ));
    });

    tearDown(() async {
      await db.close();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 1. SalePayments CHECK Constraints
    // ─────────────────────────────────────────────────────────────────────────
    group('1. SalePayments CHECK Constraints', () {
      test('Rejects method = transfer', () async {
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        expect(
          () => db.into(db.salePayments).insert(SalePaymentsCompanion.insert(
            id: 'sp-1',
            branchId: 'branch-1',
            saleId: 'sale-1',
            method: 'transfer',
            amountPiasters: 1000,
            createdAt: nowSec,
            updatedAt: nowSec,
          )),
          throwsA(isA<Exception>()),
        );
      });

      test('Rejects amount_piasters <= 0', () async {
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        expect(
          () => db.into(db.salePayments).insert(SalePaymentsCompanion.insert(
            id: 'sp-2',
            branchId: 'branch-1',
            saleId: 'sale-1',
            method: 'cash',
            amountPiasters: 0,
            createdAt: nowSec,
            updatedAt: nowSec,
          )),
          throwsA(isA<Exception>()),
        );
      });

      test('Accepts valid cash and card payments', () async {
        final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await db.into(db.salePayments).insert(SalePaymentsCompanion.insert(
          id: 'sp-valid-cash',
          branchId: 'branch-1',
          saleId: 'sale-1',
          method: 'cash',
          amountPiasters: 5000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));
        await db.into(db.salePayments).insert(SalePaymentsCompanion.insert(
          id: 'sp-valid-card',
          branchId: 'branch-1',
          saleId: 'sale-1',
          method: 'card',
          amountPiasters: 5000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));

        final rows = await db.select(db.salePayments).get();
        expect(rows.length, equals(2));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Migration v8 Backfill & Idempotency
    // ─────────────────────────────────────────────────────────────────────────
    group('2. Migration v8 Backfill & Idempotency', () {
      test('Migration v8 backfills sale_payments from existing sales', () async {
        final now = DateTime.now();
        await db.into(db.sales).insert(SalesCompanion.insert(
          id: 'sale-mig-1',
          branchId: 'branch-1',
          shortRef: 'S-MIG-1',
          cashierId: 'user-1',
          subtotal: 10000,
          discountType: 'none',
          total: 10000,
          paymentMethod: 'card',
          date: now,
          createdAt: now,
          updatedAt: now,
        ));

        await db.migrateToV8(Migrator(db));

        final rows = await (db.select(db.salePayments)..where((sp) => sp.saleId.equals('sale-mig-1'))).get();
        expect(rows.length, equals(1));
        expect(rows.first.method, equals('card'));
        expect(rows.first.amountPiasters, equals(10000));
      });

      test('Migration v8 excludes installment-contract sales', () async {
        final now = DateTime.now();
        await db.into(db.sales).insert(SalesCompanion.insert(
          id: 'sale-install-1',
          branchId: 'branch-1',
          shortRef: 'S-INST-1',
          cashierId: 'user-1',
          subtotal: 50000,
          discountType: 'none',
          total: 50000,
          paymentMethod: 'installment',
          date: now,
          createdAt: now,
          updatedAt: now,
        ));
        await db.into(db.customerInstallments).insert(CustomerInstallmentsCompanion.insert(
          id: 'contract-1',
          branchId: 'branch-1',
          saleId: 'sale-install-1',
          customerId: 'cust-1',
          totalPiasters: 50000,
          principalPiasters: 50000,
          interestBp: 0,
          monthlyAmountPiasters: 5000,
          remainingPiasters: 50000,
          durationMonths: 10,
          startDate: now,
          endDate: now,
          createdBy: 'user-1',
          createdAt: now,
          updatedAt: now,
        ));

        await db.migrateToV8(Migrator(db));

        final rows = await (db.select(db.salePayments)..where((sp) => sp.saleId.equals('sale-install-1'))).get();
        expect(rows, isEmpty);
      });

      test('Migration v8 is idempotent (run twice)', () async {
        final now = DateTime.now();
        await db.into(db.sales).insert(SalesCompanion.insert(
          id: 'sale-idemp-1',
          branchId: 'branch-1',
          shortRef: 'S-IDEMP-1',
          cashierId: 'user-1',
          subtotal: 20000,
          discountType: 'none',
          total: 20000,
          paymentMethod: 'cash',
          date: now,
          createdAt: now,
          updatedAt: now,
        ));

        // Run twice
        await db.migrateToV8(Migrator(db));
        await db.migrateToV8(Migrator(db));

        final rows = await (db.select(db.salePayments)..where((sp) => sp.saleId.equals('sale-idemp-1'))).get();
        expect(rows.length, equals(1));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. POS Split Checkout & Cash Movements
    // ─────────────────────────────────────────────────────────────────────────
    group('3. POS Split Checkout & Cash Movements', () {
      test('Split checkout creates 1 sale row, 2 sale_payments rows, 2 cash_movements rows', () async {
        final createdId = await posDataSource.checkout(
          items: [
            {'variantId': 'var-1', 'name': 'Shirt', 'color': 'Blue', 'size': 'M', 'qty': 2, 'price': 5000, 'cost': 3000}
          ],
          total: 10000,
          cashierId: 'user-1',
          paymentMethod: 'split',
          splits: const [
            PaymentSplit(method: 'cash', amountPiasters: 6000),
            PaymentSplit(method: 'card', amountPiasters: 4000),
          ],
        );

        // Check sales row
        final sale = await (db.select(db.sales)..where((s) => s.id.equals(createdId))).getSingle();
        expect(sale.paymentMethod, equals('split'));
        expect(sale.total, equals(10000));

        // Check sale_payments
        final payments = await (db.select(db.salePayments)..where((sp) => sp.saleId.equals(createdId))).get();
        expect(payments.length, equals(2));
        final cashPayment = payments.firstWhere((p) => p.method == 'cash');
        final cardPayment = payments.firstWhere((p) => p.method == 'card');
        expect(cashPayment.amountPiasters, equals(6000));
        expect(cardPayment.amountPiasters, equals(4000));

        // Check cash_movements
        final movements = await (db.select(db.cashMovements)..where((m) => m.referenceId.equals(createdId))).get();
        expect(movements.length, equals(2));
        expect(movements.every((m) => m.type == 'sale' && m.direction == 'in'), isTrue);
        final cashMov = movements.firstWhere((m) => m.method == 'cash');
        final cardMov = movements.firstWhere((m) => m.method == 'card');
        expect(cashMov.amountPiasters, equals(6000));
        expect(cardMov.amountPiasters, equals(4000));
      });

      test('Split sum must equal cart total (reject under/over)', () async {
        final posCubit = _TestPosCubit(createSaleUseCase, posRepo);
        posCubit.setCart(10000);

        // Try under-split (5000 + 3000 = 8000 != 10000)
        final underOk = await posCubit.checkout(
          cashierId: 'user-1',
          splits: const [
            PaymentSplit(method: 'cash', amountPiasters: 5000),
            PaymentSplit(method: 'card', amountPiasters: 3000),
          ],
        );
        expect(underOk, isFalse);

        // Try over-split (6000 + 5000 = 11000 != 10000)
        final overOk = await posCubit.checkout(
          cashierId: 'user-1',
          splits: const [
            PaymentSplit(method: 'cash', amountPiasters: 6000),
            PaymentSplit(method: 'card', amountPiasters: 5000),
          ],
        );
        expect(overOk, isFalse);

        // Exact split succeeds
        final exactOk = await posCubit.checkout(
          cashierId: 'user-1',
          splits: const [
            PaymentSplit(method: 'cash', amountPiasters: 6000),
            PaymentSplit(method: 'card', amountPiasters: 4000),
          ],
        );
        expect(exactOk, isTrue);
      });

      test('Normal sale backward compat: 1 sale_payment row and 1 cash_movement row', () async {
        final createdId = await posDataSource.checkout(
          items: [
            {'variantId': 'var-1', 'name': 'Shirt', 'color': 'Blue', 'size': 'M', 'qty': 1, 'price': 5000, 'cost': 3000}
          ],
          total: 5000,
          cashierId: 'user-1',
          paymentMethod: 'card',
        );

        final payments = await (db.select(db.salePayments)..where((sp) => sp.saleId.equals(createdId))).get();
        expect(payments.length, equals(1));
        expect(payments.first.method, equals('card'));
        expect(payments.first.amountPiasters, equals(5000));

        final movements = await (db.select(db.cashMovements)..where((m) => m.referenceId.equals(createdId))).get();
        expect(movements.length, equals(1));
        expect(movements.first.method, equals('card'));
        expect(movements.first.amountPiasters, equals(5000));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Shift Closing
    // ─────────────────────────────────────────────────────────────────────────
    group('4. Shift Closing', () {
      test('Shift close sums cash + card from cash_movements', () async {
        // Create split sale in shift
        await posDataSource.checkout(
          items: [
            {'variantId': 'var-1', 'name': 'Dress', 'color': 'Red', 'size': 'L', 'qty': 1, 'price': 10000, 'cost': 6000}
          ],
          total: 10000,
          cashierId: 'user-1',
          shiftId: 'shift-phase3',
          paymentMethod: 'split',
          splits: const [
            PaymentSplit(method: 'cash', amountPiasters: 7000),
            PaymentSplit(method: 'card', amountPiasters: 3000),
          ],
        );

        final summary = await shiftDataSource.getShiftSummary('shift-phase3');
        expect(summary.cashSales, equals(7000));
        expect(summary.cardSales, equals(3000));
        // opening 10000 + 7000 cash = 17000 expected in drawer
        expect(summary.expectedCashInDrawer, equals(17000));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Runtime Split + Installment Down Payment (Clarification 3)
    // ─────────────────────────────────────────────────────────────────────────
    group('5. Runtime Split + Installment Down Payment (Clarification 3)', () {
      test('Installment checkout with split down payment: 2 sale_payments, 2 cash_movements (installment_down), no sale movement, 0 installment_payments', () async {
        final now = DateTime.now();

        // 1. Create customer
        await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'cust-split-1',
          branchId: 'branch-1',
          name: 'Ahmed Ali',
          phone: '01012345678',
          createdAt: now,
          updatedAt: now,
        ));

        // 2. Create sale row with paymentMethod = 'installment'
        final saleId = await posDataSource.checkout(
          items: [
            {'variantId': 'var-suit', 'name': 'Suit', 'color': 'Black', 'size': '52', 'qty': 1, 'price': 1000000, 'cost': 600000}
          ],
          total: 1000000, // 10,000 EGP
          cashierId: 'user-1',
          customerId: 'cust-split-1',
          paymentMethod: 'installment',
        );

        // 3. Create installment contract with split down payment: 30,000 cash + 20,000 card = 50,000 down
        final contractResult = await installmentsFacade.createContract(
          saleId: saleId,
          customerId: 'cust-split-1',
          totalPiasters: 1000000,
          downPaymentPiasters: 50000,
          interestBp: 0,
          interestModel: InstallmentInterestModel.percentTotal,
          durationMonths: 10,
          startDate: now,
          pin: '1234',
          downPaymentSplits: const [
            PaymentSplit(method: 'cash', amountPiasters: 30000),
            PaymentSplit(method: 'card', amountPiasters: 20000),
          ],
        );
        expect(contractResult.isRight(), isTrue);
        final contract = contractResult.getOrElse(() => throw Exception());

        // Verify customer_installments
        expect(contract.downPaymentPiasters, equals(50000));
        expect(contract.remainingPiasters, equals(950000));

        // Verify sale_payments: 2 rows for the down payment splits ONLY
        final salePayments = await (db.select(db.salePayments)..where((sp) => sp.saleId.equals(saleId))).get();
        expect(salePayments.length, equals(2));
        final cashSp = salePayments.firstWhere((p) => p.method == 'cash');
        final cardSp = salePayments.firstWhere((p) => p.method == 'card');
        expect(cashSp.amountPiasters, equals(30000));
        expect(cardSp.amountPiasters, equals(20000));

        // Verify cash_movements: 2 rows of type installment_down ONLY
        final movements = await db.select(db.cashMovements).get();
        final downMovements = movements.where((m) => m.type == 'installment_down').toList();
        expect(downMovements.length, equals(2));
        final cashDown = downMovements.firstWhere((m) => m.method == 'cash');
        final cardDown = downMovements.firstWhere((m) => m.method == 'card');
        expect(cashDown.amountPiasters, equals(30000));
        expect(cardDown.amountPiasters, equals(20000));

        // Verify NO cash_movements of type 'sale'
        final saleMovements = movements.where((m) => m.type == 'sale').toList();
        expect(saleMovements, isEmpty);

        // Verify 0 installment_payments rows
        final instPayments = await db.select(db.installmentPayments).get();
        expect(instPayments, isEmpty);
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 6. Returns with Split Refund & Manager Override
    // ─────────────────────────────────────────────────────────────────────────
    group('6. Returns with Split Refund', () {
      test('Return of split sale refunds each payment on original method', () async {
        final now = DateTime.now();

        // Create variant
        await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'prod-ret-1',
          branchId: 'branch-1',
          name: 'Jacket',
          categoryId: 'cat-1',
          createdAt: now,
          updatedAt: now,
        ));
        await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
          id: 'var-ret-1',
          branchId: 'branch-1',
          productId: 'prod-ret-1',
          sku: 'SKU-JCKT',
          color: 'Black',
          size: 'XL',
          costPrice: 6000,
          sellPrice: 10000,
          createdAt: now,
          updatedAt: now,
        ));

        // Create split sale
        final saleId = await posDataSource.checkout(
          items: [
            {'variantId': 'var-ret-1', 'name': 'Jacket', 'color': 'Black', 'size': 'XL', 'qty': 1, 'price': 10000, 'cost': 6000}
          ],
          total: 10000,
          cashierId: 'user-1',
          paymentMethod: 'split',
          splits: const [
            PaymentSplit(method: 'cash', amountPiasters: 6000),
            PaymentSplit(method: 'card', amountPiasters: 4000),
          ],
        );

        final saleItems = await returnsDataSource.getSaleItems(saleId);

        // Process full return without manual override (should refund to original methods)
        await returnsDataSource.processReturn(
          saleId: saleId,
          items: [
            ReturnItemEntity(
              id: 'ret-it-1',
              saleItemId: saleItems.first.id,
              variantId: 'var-ret-1',
              productName: 'Jacket',
              color: 'Black',
              size: 'XL',
              qty: 1,
              refundUnitPrice: 10000,
            ),
          ],
          reason: 'Defective item',
          userId: 'user-1',
        );

        final refundMovements = await (db.select(db.cashMovements)..where((m) => m.type.equals('refund'))).get();
        expect(refundMovements.length, equals(2));
        final cashRefund = refundMovements.firstWhere((m) => m.method == 'cash');
        final cardRefund = refundMovements.firstWhere((m) => m.method == 'card');
        expect(cashRefund.amountPiasters, equals(6000));
        expect(cardRefund.amountPiasters, equals(4000));
        expect(refundMovements.every((m) => m.direction == 'out'), isTrue);
      });

      test('Manager override refund to different method with PIN', () async {
        final now = DateTime.now();

        await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'prod-ovr-1',
          branchId: 'branch-1',
          name: 'Jeans',
          categoryId: 'cat-1',
          createdAt: now,
          updatedAt: now,
        ));
        await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
          id: 'var-ovr-1',
          branchId: 'branch-1',
          productId: 'prod-ovr-1',
          sku: 'SKU-JEANS',
          color: 'Blue',
          size: '32',
          costPrice: 4000,
          sellPrice: 8000,
          createdAt: now,
          updatedAt: now,
        ));

        // Sale paid by card
        final saleId = await posDataSource.checkout(
          items: [
            {'variantId': 'var-ovr-1', 'name': 'Jeans', 'color': 'Blue', 'size': '32', 'qty': 1, 'price': 8000, 'cost': 4000}
          ],
          total: 8000,
          cashierId: 'user-1',
          paymentMethod: 'card',
        );

        final saleItems = await returnsDataSource.getSaleItems(saleId);

        // Manager overrides refund to CASH
        await returnsDataSource.processReturn(
          saleId: saleId,
          items: [
            ReturnItemEntity(
              id: 'ret-it-ovr',
              saleItemId: saleItems.first.id,
              variantId: 'var-ovr-1',
              productName: 'Jeans',
              color: 'Blue',
              size: '32',
              qty: 1,
              refundUnitPrice: 8000,
            ),
          ],
          reason: 'Customer requested cash refund',
          userId: 'user-1',
          isManagerOverride: true,
          overridePin: '1234',
          refunds: const [
            PaymentRefund(salePaymentId: 'sp-1', method: 'cash', amountPiasters: 8000),
          ],
        );

        final refundMovements = await (db.select(db.cashMovements)..where((m) => m.type.equals('refund'))).get();
        expect(refundMovements.length, equals(1));
        expect(refundMovements.first.method, equals('cash'));
        expect(refundMovements.first.amountPiasters, equals(8000));

        // Check audit log contains manager override
        final auditLogs = await (db.select(db.auditLogs)..where((a) => a.action.equals('manager_refund_override'))).get();
        expect(auditLogs.length, equals(1));
      });

      test('Refund cash movement records shift_id = current active shift', () async {
        final now = DateTime.now();

        await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'prod-sft-1',
          branchId: 'branch-1',
          name: 'Cap',
          categoryId: 'cat-1',
          createdAt: now,
          updatedAt: now,
        ));
        await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
          id: 'var-sft-1',
          branchId: 'branch-1',
          productId: 'prod-sft-1',
          sku: 'SKU-CAP',
          color: 'Black',
          size: 'OneSize',
          costPrice: 1500,
          sellPrice: 3000,
          createdAt: now,
          updatedAt: now,
        ));

        final saleId = await posDataSource.checkout(
          items: [
            {'variantId': 'var-sft-1', 'name': 'Cap', 'color': 'Black', 'size': 'OneSize', 'qty': 1, 'price': 3000, 'cost': 1500}
          ],
          total: 3000,
          cashierId: 'user-1',
          paymentMethod: 'cash',
        );

        final saleItems = await returnsDataSource.getSaleItems(saleId);

        await returnsDataSource.processReturn(
          saleId: saleId,
          items: [
            ReturnItemEntity(
              id: 'ret-it-sft',
              saleItemId: saleItems.first.id,
              variantId: 'var-sft-1',
              productName: 'Cap',
              color: 'Black',
              size: 'OneSize',
              qty: 1,
              refundUnitPrice: 3000,
            ),
          ],
          reason: 'Wrong fit',
          userId: 'user-1',
        );

        final refundMovements = await (db.select(db.cashMovements)..where((m) => m.type.equals('refund'))).get();
        expect(refundMovements.first.shiftId, equals('shift-phase3'));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 7. Two-Section Financial Report (P&L and Cash Flow)
    // ─────────────────────────────────────────────────────────────────────────
    group('7. Two-Section Financial Report', () {
      test('P&L: revenue - COGS - opex = net profit', () async {
        final now = DateTime.now();

        // 1. Create product & variant with cost 3000 and price 10000
        await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'prod-pl-1',
          branchId: 'branch-1',
          name: 'Coat',
          categoryId: 'cat-1',
          createdAt: now,
          updatedAt: now,
        ));
        await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
          id: 'var-pl-1',
          branchId: 'branch-1',
          productId: 'prod-pl-1',
          sku: 'SKU-COAT',
          color: 'Brown',
          size: 'L',
          costPrice: 3000,
          sellPrice: 10000,
          createdAt: now,
          updatedAt: now,
        ));

        // 2. Sale of 2 coats = Revenue 20,000, COGS = 6,000
        await posDataSource.checkout(
          items: [
            {'variantId': 'var-pl-1', 'name': 'Coat', 'color': 'Brown', 'size': 'L', 'qty': 2, 'price': 10000, 'cost': 3000}
          ],
          total: 20000,
          cashierId: 'user-1',
          paymentMethod: 'cash',
        );

        // 3. Operating expense = 4,000
        await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: 'exp-op-1',
          branchId: 'branch-1',
          userId: 'user-1',
          category: 'كهرباء',
          amount: 4000,
          kind: const Value('operating'),
          expenseDate: now,
          createdAt: now,
          updatedAt: now,
        ));

        // 4. Non-operating supplier payment = 5,000 (must be ignored in P&L)
        await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: 'exp-sup-1',
          branchId: 'branch-1',
          userId: 'user-1',
          category: 'سداد موردين',
          amount: 5000,
          kind: const Value('supplier_payment'),
          expenseDate: now,
          createdAt: now,
          updatedAt: now,
        ));

        final report = await reportsDataSource.getSalesReport(
          startDate: DateTime(now.year, now.month, 1),
          endDate: now.add(const Duration(days: 1)),
        );

        expect(report.totalRevenue, equals(20000));
        expect(report.totalCost, equals(6000));
        expect(report.totalProfit, equals(14000)); // Gross profit = 20000 - 6000
        expect(report.totalExpenses, equals(4000)); // Only operating
        expect(report.netProfit, equals(10000)); // 14000 - 4000
      });

      test('Revenue in P&L excludes installment-contract sales', () async {
        final now = DateTime.now();

        // Normal cash sale = 15,000
        await posDataSource.checkout(
          items: [
            {'variantId': 'var-1', 'name': 'Item', 'color': 'Red', 'size': 'M', 'qty': 1, 'price': 15000, 'cost': 5000}
          ],
          total: 15000,
          cashierId: 'user-1',
          paymentMethod: 'cash',
        );

        // Installment sale = 100,000 (must be excluded from P&L revenue)
        await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'cust-pl-inst',
          branchId: 'branch-1',
          name: 'Khaled',
          phone: '01099999999',
          createdAt: now,
          updatedAt: now,
        ));
        final instSaleId = await posDataSource.checkout(
          items: [
            {'variantId': 'var-1', 'name': 'Item', 'color': 'Red', 'size': 'M', 'qty': 1, 'price': 100000, 'cost': 40000}
          ],
          total: 100000,
          cashierId: 'user-1',
          customerId: 'cust-pl-inst',
          paymentMethod: 'installment',
        );
        await installmentsFacade.createContract(
          saleId: instSaleId,
          customerId: 'cust-pl-inst',
          totalPiasters: 100000,
          downPaymentPiasters: 10000,
          interestBp: 0,
          interestModel: InstallmentInterestModel.percentTotal,
          durationMonths: 6,
          startDate: now,
          pin: '1234',
        );

        final report = await reportsDataSource.getSalesReport(
          startDate: DateTime(now.year, now.month, 1),
          endDate: now.add(const Duration(days: 1)),
        );

        // Revenue should only reflect the 15,000 normal sale, not the 100,000 installment sale
        expect(report.totalRevenue, equals(15000));
      });

      test('Cash Flow totals in/out by method and reversals reduce net cash out', () async {
        final now = DateTime.now();
        final nowSec = now.millisecondsSinceEpoch ~/ 1000;

        // Cash In: 25,000 cash, 15,000 card
        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-in-1',
          branchId: 'branch-1',
          type: 'sale',
          method: 'cash',
          direction: 'in',
          amountPiasters: 25000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));
        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-in-2',
          branchId: 'branch-1',
          type: 'sale',
          method: 'card',
          direction: 'in',
          amountPiasters: 15000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));

        // Cash Out: 10,000 expense cash
        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-out-1',
          branchId: 'branch-1',
          type: 'expense',
          method: 'cash',
          direction: 'out',
          amountPiasters: 10000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));

        // Reversal (cash in): 2,000 expense reversal (reduces net cash out)
        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-rev-1',
          branchId: 'branch-1',
          type: 'expense_reversal',
          method: 'cash',
          direction: 'in',
          amountPiasters: 2000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));

        final report = await reportsDataSource.getSalesReport(
          startDate: DateTime(now.year, now.month, 1),
          endDate: now.add(const Duration(days: 1)),
        );

        expect(report.cashFlowIn, equals(42000)); // 25000 + 15000 + 2000
        expect(report.cashFlowOut, equals(10000));
        expect(report.netCashFlow, equals(32000)); // 42000 - 10000
        expect(report.cashFlowInByMethod['cash'], equals(27000)); // 25000 + 2000
        expect(report.cashFlowInByMethod['card'], equals(15000));
        expect(report.cashFlowOutByMethod['cash'], equals(10000));
      });
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 8. Source of Truth Verification
    // ─────────────────────────────────────────────────────────────────────────
    group('8. Source of Truth Verification', () {
      test('sale_payments sum per sale == sale.total (for non-installment sales)', () async {
        final saleId = await posDataSource.checkout(
          items: [
            {'variantId': 'var-1', 'name': 'Item', 'color': 'Blue', 'size': 'M', 'qty': 3, 'price': 10000, 'cost': 5000}
          ],
          total: 30000,
          cashierId: 'user-1',
          paymentMethod: 'split',
          splits: const [
            PaymentSplit(method: 'cash', amountPiasters: 18000),
            PaymentSplit(method: 'card', amountPiasters: 12000),
          ],
        );

        final sale = await (db.select(db.sales)..where((s) => s.id.equals(saleId))).getSingle();
        final payments = await (db.select(db.salePayments)..where((sp) => sp.saleId.equals(saleId))).get();
        final totalPayments = payments.fold<int>(0, (s, p) => s + p.amountPiasters);

        expect(totalPayments, equals(sale.total));
      });

      test('cash_movements total in == sales + installment_down + installment_payments', () async {
        final now = DateTime.now();
        final nowSec = now.millisecondsSinceEpoch ~/ 1000;

        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-s1',
          branchId: 'branch-1',
          type: 'sale',
          method: 'cash',
          direction: 'in',
          amountPiasters: 10000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));
        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-id1',
          branchId: 'branch-1',
          type: 'installment_down',
          method: 'cash',
          direction: 'in',
          amountPiasters: 5000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));
        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-ip1',
          branchId: 'branch-1',
          type: 'installment_payment',
          method: 'card',
          direction: 'in',
          amountPiasters: 3000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));

        final allIn = await (db.select(db.cashMovements)..where((m) => m.direction.equals('in'))).get();
        final sumIn = allIn.fold<int>(0, (s, m) => s + m.amountPiasters);
        expect(sumIn, equals(18000)); // 10000 + 5000 + 3000
      });

      test('cash_movements total out == purchases + supplier_payments + opex + refunds', () async {
        final now = DateTime.now();
        final nowSec = now.millisecondsSinceEpoch ~/ 1000;

        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-pur1',
          branchId: 'branch-1',
          type: 'purchase_payment',
          method: 'cash',
          direction: 'out',
          amountPiasters: 50000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));
        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-sup1',
          branchId: 'branch-1',
          type: 'supplier_payment',
          method: 'cash',
          direction: 'out',
          amountPiasters: 20000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));
        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-exp1',
          branchId: 'branch-1',
          type: 'expense',
          method: 'cash',
          direction: 'out',
          amountPiasters: 5000,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));
        await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          id: 'cm-ref1',
          branchId: 'branch-1',
          type: 'refund',
          method: 'card',
          direction: 'out',
          amountPiasters: 2500,
          createdAt: nowSec,
          updatedAt: nowSec,
        ));

        final allOut = await (db.select(db.cashMovements)..where((m) => m.direction.equals('out'))).get();
        final sumOut = allOut.fold<int>(0, (s, m) => s + m.amountPiasters);
        expect(sumOut, equals(77500)); // 50000 + 20000 + 5000 + 2500
      });
    });
  });
}
