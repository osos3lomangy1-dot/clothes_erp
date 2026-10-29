# Architecture

## Clean Architecture Layers
- Presentation: Screens, Cubits, Widgets
- Domain: Entities, Repositories (interfaces), Use Cases
- Data: Data Sources (Drift), Repository Implementations, Models

## TxWriter Pattern (Atomic Transactions)
Every write goes through `TxWriter.write()` which runs inside a single Drift
transaction:
1. writeFn() — the actual data change
2. beforeAuditWrite hook (test injection point)
3. Insert into sync_queue
4. Insert into audit_logs

If any step throws, the whole transaction rolls back.

## Single Quantity Path Rule
`product_variants.quantity` is ONLY ever changed via
`InventoryLocalDataSource.applyStockMovement()`. No other code may update quantity
directly. This guarantees every stock change writes an inventory_logs row and is
auditable.

Movement types (enum): sale, return, receive, adjustment, stocktake.
- receive/adjustment require a reason and admin role (enforced in use case).

## Navigation Strategy
`MainLayout` is a StatefulWidget with a persistent Sidebar (collapsible).
Clicking a sidebar item swaps the `currentScreen` via setState (right side only).
POS is pushed as a full-screen route (Navigator.push) to hide the sidebar.
EOF