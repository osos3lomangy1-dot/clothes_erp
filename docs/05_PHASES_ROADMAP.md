# Clothes ERP — Phases Roadmap

## Completed Phases

### Phase 0: Stabilization
Audited the existing codebase (Bloc/Cubit, go_router, get_it + injectable, dartz). Identified architecture gaps, unused dependencies, missing features, and RBAC deficiencies. Established the hybrid Product/Variant schema, single-branch strategy, and online-first with offline persistence.

### Phase 1a: Auth Stabilization
Fixed the unsafe `user as UserModel` cast in `auth_repository_impl.dart`. Normalized exception → Failure mapping across auth data sources and repository. Enabled Firestore offline persistence with a static guard. Fixed `authStateChanges()` stream to never throw (broad catch, return null on failure).

### Phase 1b-1: Exception Mapping (Categories + Products)
Applied the same exception → Failure mapping pattern to `category_remote_data_source`, `category_repository_impl`, `product_remote_data_source`, and `product_repository_impl`. Standardized `ServerException` → `ServerFailure` in all repos.

### Phase 1b-2/1b-3: Exception Mapping (Variants, Employees, Inventory, POS)
Extended the pattern to 8 more files: variant, employee, inventory, and POS data sources and repositories. All data sources now throw `ServerException` instead of raw `Exception`. All repos now use `on ServerException catch` before generic `catch`.

### Phase 1.5: Security Rules
Created `firestore.rules` with role-based access control. Admin (full CRUD), Manager (read/write inventory + employees), Cashier (POS + read-only). Deny by default. `isActive` check enforced on every request. Deployed to Firebase.

### Phase 2: Schema Alignment
Aligned Product and Variant models to the hybrid schema. Product (catalog): `id, name, description, categoryId, categoryName, images, barcode, createdAt`. Variant (SKU): `id, productId, productCode, color, size, quantity, costPrice, salePrice, minStock, barcode, createdAt`. Confirmed `paymentMethod` field already exists in `SaleModel`.

### Phase 3: POS Core
Built the complete POS feature: domain entities (`SaleEntity`, `SaleItemEntity`), `CreateSaleUseCase`, repository with Firestore `WriteBatch` (sale creation + variant quantity decrement + inventory_logs), `PosCubit` with cart management, `PosScreen` with split layout (search + cart), payment method dropdown, checkout with loading state. Added `/pos` route and "Open POS" buttons on both dashboards.

## Upcoming Phases

### Phase 4: Dashboard & Reports
- Dashboard screens with real data (sales summary, low-stock alerts, recent transactions).
- Reports: sales by payment method, by date range, by cashier. Inventory reports. Employee attendance reports.

### Phase 5: Inventory Logs & Stock Management
- Inventory adjustment UI (add/remove stock with reason).
- Full inventory_logs viewer with filtering by date, type, product.
- Low-stock notifications.

### Phase 6: Customers, Returns & Expenses
- Customer management (CRUD, purchase history, loyalty points).
- Sales returns (reverse sale, restore stock, refund method).
- Expenses tracking (amount, type, payment method, date).

### Phase 7: Reports & Analytics
- Sales reports (daily, weekly, monthly, by payment method, by cashier).
- Inventory reports (stock levels, turnover, low stock).
- Employee reports (attendance, sales performance).
- Export to PDF/CSV.
