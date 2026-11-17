# Orkeed Clothes ERP — Project Overview

## Project Name
Orkeed Clothes ERP (`clothes_erp`)

## Business Goal
A production-grade, offline-first Point-of-Sale (POS), Inventory, Installments, Purchases, and Accounting ERP system built specifically for clothing retail stores. The application works 100% offline with local SQLite persistence via Drift, atomic transaction guarantees (`TxWriter`), comprehensive audit logging, and sync queue support.

## Tech Stack
- **Framework:** Flutter (Windows Desktop primary target, RTL Arabic UI with Cairo font)
- **Database:** Drift (local SQLite, offline-first, versioned migrations)
- **State Management:** Bloc / Cubit (`flutter_bloc`)
- **Dependency Injection:** GetIt + Injectable
- **Functional Error Handling:** `dartz` (`Either<Failure, T>`)
- **Printing & Barcodes:** `pdf`, `printing`, `barcode` (thermal roll 50×30mm, 38×25mm, A4 label sheets, thermal receipts)
- **Design System:** Material 3 with Purple primary theme (`#673AB7`)

## Completed Full Drift Migration
All operational modules have been fully migrated to Drift (local SQLite) with zero reliance on Firebase for core operations:
- **Catalog & Inventory:** Categories, Products (with Arabic duplicate prevention & real-time similarity warnings), Product Variants (Color/Size matrix), Inventory Logs (`applyStockMovement`), Barcode Label Printing.
- **POS & Sales:** Hardware Barcode Scanner Listener, Split Payments, Installment Sales, Promotions Engine, Returns & Exchanges, Thermal Receipts.
- **Installments:** Grouped Customer View, Individual & Bulk FIFO Quick Payments, Manager PIN Protection, Overdue Tracking, Shift Cash Drawer Sync.
- **Purchases & Suppliers:** Purchase Invoices, Goods Receipt, Supplier FIFO Payments, Supplier Purchase Returns with stock & drawer reconciliation.
- **Finance & HR:** Executive Dashboard, Shift Management & Drawer Reconciliation (`cash_movements`), Expenses, Employees, Payroll/Advances/Bonuses, Audit Logs, Feature Gates, and RBAC.
