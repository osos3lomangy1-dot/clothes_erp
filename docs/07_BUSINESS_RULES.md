# Business Rules

## Product vs Variant
- Product = catalog (name, category, minStock)
- Variant = SKU (sku, color, size, quantity, costPrice, sellPrice)
- Deleting a product soft-deletes its variants in the same transaction
- A product with sale_items can only be deactivated, never deleted

## POS Behavior
- Checkout creates a Sale + SaleItems in one transaction
- Each item calls applyStockMovement(type: sale, qtyDelta: -qty)
- If stock insufficient, transaction rolls back
- Cashier projection never exposes costPrice

## Returns
- Refund calculated from original sale price
- Stock restored via applyStockMovement(type: return)

## Price Editing
- Admin can edit sellPrice/costPrice; audit_logs records oldValue/newValue
- Cashier can override unit price per line during sale (no audit)
EOF