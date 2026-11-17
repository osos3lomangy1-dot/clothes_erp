# Project Roadmap — Orkeed Clothes ERP

## ✅ COMPLETED MILESTONES

### Core Foundation & Offline-First Migration
- **Phase 0:** Auth, RBAC, Clean Architecture stabilization.
- **Phase 1:** Drift Local SQLite Database, `Money` (integer piasters), `BranchProvider`, `TxWriter` atomic transactions, `audit_logs`, `sync_queue`.
- **Phase 2:** Categories, Products, and Product Variants (Color/Size matrix) on Drift.
- **Phase 3:** Inventory Management & `inventory_logs` (`applyStockMovement` single path).
- **Phase 4:** Complete POS Checkout, Split Payments (`sale_payments`), Customer Returns, Thermal Receipts.
- **Phase 5:** Customers, Suppliers, Employees, Payroll/Advances/Bonuses, Expenses, and Comprehensive Reports on Drift.
- **Phase 6:** Shifts & Cash Drawer Integrity (`cash_movements` linked to `shiftId`, shift open/close reconciliation).
- **Phase 7:** Full Installments Module (Plans, Contracts, Manager PIN, Grouped Customer View, Overdue Tracking, Shift Installments Display).
- **Phase 8:** Promotions & Discounts Engine (Product/Category targeted promos, BOGO, fixed/percentage discounts, coupon & report integration).

### Recent Production Upgrades (November 2026)
- **Shift Installments Display (`abde249`):** Detailed breakdown of installment down payments and collections inside shift summary and closing reports.
- **Executive Dashboard Upgrade (`c32c277`):** Real-time KPIs, daily/monthly revenue, net profit, installment collections, low-stock alerts, and top-selling items.
- **Barcode Label Printing (`f18ef12`):** Thermal label rolls (50×30mm, 38×25mm) and A4 multi-label sheets directly from product variants.
- **Supplier Purchase Returns (`befbd51`):** Return goods to suppliers with automatic stock deduction, `inventory_logs`, supplier balance reconciliation, and cash drawer refund sync.
- **POS Hardware Barcode Scanner Listener (`46c0fb9`):** Global hardware keyboard listener and smart autofocus for seamless barcode scanning at checkout.
- **Product Duplicate Prevention & Arabic Similarity Warning (`a8cf1eb`):** Real-time Arabic normalization (`ArabicTextHelper`), live similar-product warning chips while typing, confirmation barrier on similar names, and strict UI + DB blocking on exact/normalized duplicates.
- **Bulk Customer Installment Payment with FIFO Allocation (`f767d26`):** Inline quick-payment field right next to each customer's name in Installments screen; validates against total customer debt, allocates automatically FIFO across active contracts (oldest first), enforces Manager PIN when enabled, and syncs all payments to `cash_movements` and the active shift drawer.

## 🚀 FUTURE OPTIONAL ENHANCEMENTS
- Cloud Multi-Branch Synchronization (REST / Cloud sync worker draining `sync_queue`)
- Held Sales / Cart Parking & Resume
- WhatsApp / SMS automated installment due reminders
