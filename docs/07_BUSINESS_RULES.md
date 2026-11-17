# Business Rules — Orkeed Clothes ERP

## 1. Products, Variants & Duplicate Prevention
- **Product vs Variant:**
  - `Product` = catalog entity (`name`, `categoryId`, `description`, `minStock`).
  - `ProductVariant` = SKU entity (`sku`, `color`, `size`, `quantity`, `costPrice`, `sellPrice`).
  - Soft-deleting a product soft-deletes its variants in the same atomic transaction.
  - A product with existing `sale_items` cannot be deleted; it may only be deactivated.
- **Duplicate Product Prevention (Strict UI + Cubit + DB Enforcement):**
  - All product names are normalized via `ArabicTextHelper.normalize()`:
    - Strips Arabic diacritics / Tashkeel (`[\u064B-\u065F\u0670]`).
    - Unifies Alef variants (`أ`, `إ`, `آ`, `ٱ` -> `ا`).
    - Unifies Yaa (`ى` -> `ي`) and Taa Marbuta (`ة` -> `ه`).
    - Collapses multiple spaces and trims boundaries.
  - **Exact / Normalized Duplicate:** Strictly **BLOCKED** from saving at all three layers (`ProductFormScreen`, `ProductFormCubit`, and `ProductLocalDataSource.createProduct`, `createProductWithVariants`, `updateProduct`). Editing a product ignores its own ID during duplicate checks.
  - **Real-Time Similarity Warning:** While typing a product name, any existing products matching by substring or word overlap (`ArabicTextHelper.isSimilar`) are immediately displayed as warning chips under the name field.
  - **Accidental Save Protection:** If similar products exist when clicking Save, an explicit confirmation dialog intercepts the save listing the similar products so accidental duplicate creation is prevented.
- **Duplicate SKU / Code Prevention (Strict UI + Cubit + DB Enforcement):**
  - Variant SKUs are compared case-insensitively and trimmed (`sku.trim().toLowerCase()`).
  - Duplicate SKUs are blocked in real-time inside `ProductFormScreen` (both within the variants table and against existing active DB SKUs) and `VariantFormScreen`, as well as enforced at the database layer in `ProductLocalDataSource.createProductWithVariants`, `VariantLocalDataSource.createVariant`, and `VariantLocalDataSource.updateVariant`.
  - Soft-deleted variants free their SKU for reuse.

## 2. POS, Hardware Scanner & Payments
- Checkout creates `Sale` + `SaleItems` + `SalePayments` + `CashMovements` in one atomic transaction.
- Each sold item deducts stock via `applyStockMovement(type: sale, qtyDelta: -qty)`. Insufficient stock rolls back the entire transaction.
- **Split Payments:** Total of payment splits (`cash`, `card`, `wallet`) must match sale total (or down payment for installments).
- **Hardware Barcode Scanner:** Global keyboard listener detects rapid SKU scan bursts terminated by Enter and adds matching variants directly to the POS cart without manual focus switching.
- **Cashier Security:** Cashier projections never expose `costPrice` or net profit margins.
- **Price Editing:** Admin edits to `sellPrice` / `costPrice` are recorded in `audit_logs` with `oldValue`/`newValue`.

## 3. Installments & Bulk Customer FIFO Payment
- **Contract Creation:** Creates `customer_installments` contract with integer-piaster schedule. Any down payment writes `sale_payments` and `cash_movements` (`type: 'installment_down'`, `direction: 'in'`, linked to active `shiftId`).
- **Single Contract Payment (`recordPayment`):** Rejects zero/negative amounts, cancelled/completed contracts, and overpayments exceeding `contract.remainingPiasters`.
- **Bulk Customer Quick Payment (`recordBulkCustomerPayment` — FIFO):**
  - Available directly beside each customer's name on the Installments screen when `totalRemainingPiasters > 0`.
  - **Amount Validation:** Must be `> 0` and `<= totalRemainingPiasters` across all active/overdue contracts for that customer. Overpayments exceeding total customer debt are strictly rejected.
  - **FIFO Allocation Order:** Active/overdue contracts with `remainingPiasters > 0` are ordered ascending by `startDate` then `createdAt` (oldest contract first).
  - **Distribution Loop:** Payment is applied to the oldest contract first; if that contract reaches `0` remaining, its status automatically transitions to `completed`, and any leftover amount cascades to the next oldest contract until fully allocated.
  - **Atomicity & Drawer Sync:** All `installment_payments`, contract balance updates, and `cash_movements` (`type: 'installment_payment'`, `direction: 'in'`, linked to active `shiftId`) execute inside a single `TxWriter` atomic transaction with audit logging.
- **Manager PIN Protection:** Enforced via `ManagerPinService` whenever `installments.pin.require` is enabled (5 failed attempts trigger a 15-minute lockout).

## 4. Customer Returns
- Refund is calculated from the original sale item price (accounting for applied discounts).
- Stock is restored atomically via `applyStockMovement(type: return, qtyDelta: +qty)`.
- Refund cash outflow is recorded in `cash_movements` linked to the active shift.

## 5. Purchases, Supplier Payments & Purchase Returns
- **Supplier Balance Equation:** `supplier_balance = SUM(purchases) - SUM(payments) - SUM(purchase_returns)`.
- **Supplier Payments (FIFO):** General payments allocate automatically to the oldest open purchase invoices first. Overpayment on a specific invoice is rejected.
- **Supplier Purchase Returns:**
  - Deducts returned quantities from `product_variants` and logs `inventory_logs` (`type: 'purchase_return'`).
  - Reconciles supplier balance and updates invoice status.
  - If refunded in cash, records an inflow in `cash_movements` linked to the active `shiftId`.

## 6. Shifts & Drawer Reconciliation
- Expected closing cash = `openingBalance + SUM(cash_movements where method='cash' & direction='in') - SUM(cash_movements where method='cash' & direction='out')`.
- Includes cash sales, installment down payments, individual & bulk installment collections, supplier return cash refunds, minus cash customer returns, expenses, and cash supplier payments.

## 7. Promotions Engine
- Evaluates active, date-valid promotions targeting specific products, categories, or whole orders.
- Discounts are calculated cleanly in integer piasters and printed on thermal receipts.
