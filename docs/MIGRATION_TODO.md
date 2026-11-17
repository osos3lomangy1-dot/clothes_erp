# Migration Status

- [x] Categories, Products, Variants migrated to Drift
- [x] Inventory (`applyStockMovement`) migrated to Drift
- [x] POS & Split Payments migrated to Drift (uses `applyStockMovement`)
- [x] Customer Returns migrated to Drift (uses `applyStockMovement`)
- [x] Purchases, Suppliers & Supplier Purchase Returns migrated to Drift
- [x] Installments & Bulk FIFO Payments migrated to Drift
- [x] Shifts & Cash Movements (`cash_movements`) migrated to Drift
- [x] Promotions Engine migrated to Drift
- [x] Customers, Employees, Payroll, Expenses & Reports migrated to Drift

**Status:** 100% Migrated to Offline-First Drift SQLite (474 passing tests, 0 analyzer issues).
