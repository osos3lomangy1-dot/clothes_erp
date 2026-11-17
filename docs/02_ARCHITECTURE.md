# Architecture

## Clean Architecture Layers
Each feature under `lib/features/<feature_name>/` is organized into:
- **Presentation:** Screens, Cubits/States, Widgets
- **Domain:** Entities, Repository/Facade Interfaces, Domain Services (e.g., `InstallmentCalculator`, `PromotionEngine`), Use Cases
- **Data:** Drift Local Data Sources, Repository/Facade Implementations, Services (`ManagerPinService`, Printing Services)

## Core Infrastructure (`lib/core/`)
- **`TxWriter` (Atomic Transactions):** Every write operation executes inside a single Drift transaction:
  1. `writeFn()` — the actual database mutations
  2. `beforeAuditWrite` hook (test injection point for atomicity tests)
  3. Insert into `sync_queue`
  4. Insert into `audit_logs`
  If any step throws, the entire transaction rolls back cleanly.
- **`Money` Value Object:** All monetary values are stored strictly as **integer piasters** (1 EGP = 100 piasters) to eliminate floating-point rounding bugs.
- **`FeatureGate`:** Dynamic feature flagging backed by `app_meta` (e.g., `installments`, `promotions`, `loyalty`, `shifts`).
- **`ArabicTextHelper`:** Normalizes Arabic strings (unifying Alef variants `[أإآٱ] -> ا`, Yaa `ى -> ي`, Taa Marbuta `ة -> ه`, stripping Tashkeel, collapsing whitespace) for accurate duplicate detection and real-time similarity matching.
- **`ManagerPinService`:** Salted SHA-256 PIN verification with failed-attempt tracking and 15-minute lockout protection.

## Single Quantity Path Rule
`product_variants.quantity` changes flow through auditable transactional paths (`InventoryLocalDataSource.applyStockMovement()` or atomic variant creation / purchase receipt / supplier return transactions). Every stock delta writes a corresponding `inventory_logs` row with `refType`, `refId`, `reason`, and `userId`.

Movement types: `sale`, `return`, `receive`, `purchase_return`, `adjustment`, `stocktake`.

## Cash Drawer Integrity (`cash_movements`)
Every cash-affecting operation writes an atomic `cash_movements` record linked to the active `shiftId`:
- Sales & Split Payments (`sale`)
- Customer Returns (`return`)
- Installment Down Payments (`installment_down`)
- Individual & Bulk FIFO Installment Payments (`installment_payment`)
- Expenses (`expense`)
- Supplier Payments & Supplier Purchase Return Cash Refunds (`supplier_payment`, `purchase_return`)

## Hardware Integration
- **POS Barcode Scanner:** Global keyboard event listener in `PosScreen` captures rapid hardware scanner keystrokes + Enter terminator and automatically looks up and adds the matching variant SKU to the cart, with smart autofocus management.
- **Label & Receipt Printing:** Dedicated PDF/printing services supporting thermal barcode label rolls (50×30mm, 38×25mm), A4 label grids, and 80mm/58mm thermal receipts.

## Navigation Strategy
`MainLayout` provides a persistent collapsible RTL sidebar with role-based menu filtering. Full-screen operational screens like POS can be launched directly while keeping state clean and responsive.
