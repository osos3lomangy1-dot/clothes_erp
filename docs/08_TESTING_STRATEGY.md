# Testing Strategy — Orkeed Clothes ERP

## Current Test Suite Status
- **Total Passing Tests:** **474** automated tests across **60+ test files**.
- **Static Analysis:** **0 issues** (`flutter analyze`).

## Test Categories
1. **Schema & Migration Safety Tests (`schema_test.dart`, `migration_safety_test.dart`, `schema_migration_test.dart`, `promotions_migration_v10_test.dart`):**
   - CHECK constraints, unique indexes, foreign keys, and idempotent schema upgrades.
2. **Atomicity & Transaction Tests (`cash_movements_test.dart`, `inventory_local_test.dart`, `pos_local_test.dart`):**
   - Inject failures via `beforeAuditWrite` hook and verify full rollback across all tables.
3. **Domain & Business Logic Tests:**
   - **Product Duplicate Prevention (`product_duplicate_prevention_test.dart`):** 13 tests verifying `ArabicTextHelper` normalization, DB duplicate blocking (`createProduct`, `createProductWithVariants`, `updateProduct`), and `ProductFormCubit` real-time similarity & duplicate states.
   - **Bulk Installment FIFO Payment (`bulk_installment_payment_test.dart`):** 5 tests verifying FIFO allocation across multiple contracts, exact total completion, overpayment rejection, zero/negative rejection, wrong Manager PIN rejection, and `cash_movements` / `shiftId` drawer sync.
   - **Installments & PIN (`installments_facade_test.dart`, `installments_cash_movement_test.dart`, `manager_pin_service_test.dart`, `installment_calculator_test.dart`):** Full lifecycle, schedule math, overdue detection, and PIN lockout.
   - **Purchases & Returns (`purchase_returns_test.dart`, `supplier_payment_logic_test.dart`, `goods_receipt_cycle_test.dart`):** Stock movements, FIFO supplier payments, purchase returns & balance reconciliation.
   - **Promotions & POS (`promotion_engine_test.dart`, `pos_promotions_integration_test.dart`, `phase3_split_payment_test.dart`, `barcode_search_test.dart`, `barcode_label_printing_test.dart`):** Split payments, promo evaluation, barcode search, and label printing.
   - **Dashboard, Shifts, Payroll & Security (`dashboard_local_test.dart`, `shift_local_test.dart`, `cashier_payroll_test.dart`, `purchases_role_security_test.dart`, `feature_gate_test.dart`).**
4. **Widget Tests (`installments_grouped_widget_test.dart`, `installments_list_screen_test.dart`, `record_payment_screen_test.dart`, `promotions_admin_ui_test.dart`, `main_layout_sidebar_test.dart`).**

## How to Run
```bash
flutter analyze
flutter test
flutter test --reporter expanded
```

## Guidelines for Adding New Tests
1. Use in-memory Drift DB: `AppDatabase(NativeDatabase.memory())`.
2. Initialize `BranchProvider`, `TxWriter`, `FeatureGate`, and DataSource/Facade.
3. Clean up hooks and close DB in `tearDown(() async => await db.close())`.
4. Use `await expectLater(..., throwsA(...))` for async exception assertions.
5. Never depend on external mocking libraries not listed in `pubspec.yaml`; use clean lightweight Fakes.
