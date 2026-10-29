# Clothing Store ERP — Project Overview

## Project Name
Clothing Store ERP (clothes_erp)

## Business Goal
An offline-first Point-of-Sale and inventory management system for a clothing store.
The app must work fully without internet: cashiers sell, stock is deducted, and all
writes are queued for later cloud sync.

## Tech Stack
- Flutter (Windows desktop target)
- Drift (local SQLite, offline-first)
- Bloc/Cubit for state management
- GetIt + Injectable for dependency injection
- dartz Either<Failure, T> for functional error handling
- Material 3 with a Purple theme (0xFF673AB7)

## Transition from Firebase to Drift
The app originally used Firebase Auth + Firestore. Due to platform issues (Firestore
channel 400 on Web, Auth "non-platform thread" on Windows) and the offline-first
requirement, the data layer was migrated to Drift. Auth and some legacy screens still
touch Firebase, but Products, Variants, Categories, Inventory, and POS are fully on
Drift. Returns, Reports, Customers, and Employees are pending migration.
EOF