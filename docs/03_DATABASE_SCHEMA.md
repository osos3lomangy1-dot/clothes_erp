# Database Schema

## Tables
- users, branches, app_meta
- products (catalog), product_variants (SKU/stock)
- categories, customers, employees
- sales, sale_items, returns, return_items
- expenses, shifts, inventory_logs
- sync_queue, audit_logs, daily_stats

## Product vs Variant (Hybrid Model)
- Product = catalog entry (name, category, description, minStock, isActive)
- Variant = SKU (sku, color, size, quantity, costPrice, sellPrice)
- A product can have many variants; soft-delete cascades to variants.

## sync_queue
Queues every write operation for cloud sync (entity, entityId, operation, payload).

## audit_logs
Records every write with oldValue/newValue, userId, timestamp for auditability.

## Money
Stored as int minor units (piasters) via `Money` class. No floating point in DB.
EOF