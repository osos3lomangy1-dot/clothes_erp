# Clothes ERP — Project Overview

## What is this project?

**Clothes ERP** is a complete Enterprise Resource Planning (ERP) system built for a clothing store. It manages the full lifecycle of store operations: employee management, inventory tracking, point-of-sale (POS) transactions, customer profiles, suppliers, purchase orders, expenses, and reporting.

## Target Platforms

- **Web** (Chrome) — primary development and admin interface
- **Windows** (Desktop) — stable runtime platform for production use
- **Android** — mobile POS and inventory management

> **Note:** Flutter Web and Windows Firebase Auth have known stream/threading issues. The app uses `Navigator.push` for navigation instead of `go_router` stream-based redirect to work around this.

## Business Goals

- **Point of Sale (POS):** Fast checkout with cart management, barcode search, quantity tracking, and stock decrement via Firestore transactions.
- **Inventory Management:** Product catalog with size/color variants, stock levels, low-stock alerts, and inventory movement logs.
- **Employee Management:** Profiles, roles (Admin/Manager/Cashier), attendance, status tracking.
- **Customer Management:** Profiles, purchase history, loyalty points.
- **Suppliers & Purchase Orders:** Supplier records, product sourcing, balance tracking.
- **Expenses:** Record operational expenses by type and amount.
- **Reports & Analytics:** Sales aggregation by payment method, stock reports, employee performance.
- **Role-Based Access Control (RBAC):** Three roles — Admin (full access), Manager (read/write inventory + employees), Cashier (POS + read-only inventory).

## Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Framework | Flutter | 3.41+ |
| Language | Dart | 3.11+ |
| State Management | Bloc/Cubit (`flutter_bloc`) | 8.1+ |
| Navigation | `go_router` + `Navigator.push` | 14.7+ |
| Dependency Injection | `get_it` + `injectable` | 8.0+ / 2.5+ |
| Error Handling | `dartz` (`Either<Failure, T>`) | 0.10+ |
| Backend | Firebase (Auth, Firestore, Storage) | 3.10+ |
| Models | Equatable (manual) | 2.0+ |
| Utilities | `flutter_secure_storage` | 9.2+ |

## Project Structure

```
lib/
├── main.dart
├── app.dart
├── core/           (theme, router, errors, utils, services, di)
├── features/       (auth, employees, inventory, pos, customers, suppliers, ...)
│   └── <feature>/
│       ├── data/       (models, datasources, repositories)
│       ├── domain/     (entities, usecases, repo contracts)
│       └── presentation/(screens, widgets, cubits)
└── shared/         (widgets, models, extensions)
```
