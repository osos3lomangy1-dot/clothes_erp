# Clothes ERP — Database Schema

## Firestore Collections

### `users`
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `uid` | String | Firebase Auth UID (document ID) | Yes |
| `name` | String | Full name | Yes |
| `email` | String | Email address | Yes |
| `role` | String | `admin`, `manager`, or `cashier` | Yes |
| `phone` | String | Phone number | No |
| `salary` | Number | Monthly salary | No |
| `hireDate` | Timestamp | Date of hire | No |
| `active` | Boolean | Account active status | Yes |

### `categories`
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `id` | String | Auto-generated (document ID) | Yes |
| `name` | String | Category name | Yes |
| `description` | String | Category description | No |
| `createdAt` | Timestamp | Creation timestamp | Yes |

### `products` (Catalog — master record)
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `id` | String | Auto-generated (document ID) | Yes |
| `name` | String | Product name | Yes |
| `description` | String | Product description | No |
| `categoryId` | String | Reference to categories collection | Yes |
| `categoryName` | String | Denormalized category name | Yes |
| `images` | Array\<String\> | List of image URLs (Firebase Storage) | No |
| `barcode` | String | Catalog-level barcode | No |
| `createdAt` | Timestamp | Creation timestamp | Yes |

### `product_variants` (SKU — stock and pricing)
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `id` | String | Auto-generated (document ID) | Yes |
| `productId` | String | Reference to products collection | Yes |
| `productCode` | String | Unique SKU code | Yes |
| `color` | String | Variant color | Yes |
| `size` | String | Variant size | Yes |
| `quantity` | Number | Current stock quantity | Yes |
| `costPrice` | Number | Cost price per unit | Yes |
| `salePrice` | Number | Sale price per unit | Yes |
| `minStock` | Number | Minimum stock threshold (low-stock alert) | Yes |
| `barcode` | String | Variant-level barcode | No |
| `createdAt` | Timestamp | Creation timestamp | Yes |

### `sales`
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `id` | String | Auto-generated (document ID) | Yes |
| `date` | Timestamp | Sale date/time | Yes |
| `cashierId` | String | UID of cashier who made the sale | Yes |
| `cashierName` | String | Cashier name (denormalized) | Yes |
| `items` | Array | List of SaleItem objects (see below) | Yes |
| `subtotal` | Number | Sum of item totals before discount | Yes |
| `discount` | Number | Discount amount | Yes |
| `total` | Number | Final total after discount | Yes |
| `paymentMethod` | String | `cash`, `card`, `wallet`, or `credit` | Yes |
| `customerId` | String | Reference to customers collection | No |
| `syncStatus` | String | `synced` or `pendingSync` | Yes |

**SaleItem (nested in `items` array):**
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `variantId` | String | Reference to product_variants | Yes |
| `productName` | String | Product name (denormalized) | Yes |
| `size` | String | Variant size | Yes |
| `color` | String | Variant color | Yes |
| `price` | Number | Unit sale price | Yes |
| `quantity` | Number | Quantity sold | Yes |

### `inventory_logs`
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `id` | String | Auto-generated (document ID) | Yes |
| `productId` | String | Reference to product_variants | Yes |
| `type` | String | `in` (stock added) or `out` (stock removed) | Yes |
| `quantity` | Number | Quantity changed | Yes |
| `date` | Timestamp | When the change occurred | Yes |
| `userId` | String | UID of user who made the change | Yes |

### `expenses` (future)
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `id` | String | Auto-generated (document ID) | Yes |
| `type` | String | Expense category | Yes |
| `amount` | Number | Expense amount | Yes |
| `date` | Timestamp | Expense date | Yes |
| `description` | String | Description | No |
| `paymentMethod` | String | `cash`, `card`, `wallet`, `credit` | Yes |

### `customers` (future)
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `id` | String | Auto-generated (document ID) | Yes |
| `name` | String | Customer name | Yes |
| `phone` | String | Phone number | No |
| `email` | String | Email address | No |
| `points` | Number | Loyalty points | Yes |
| `totalPurchases` | Number | Lifetime purchase total | Yes |
| `createdAt` | Timestamp | Creation timestamp | Yes |

### `suppliers` (future)
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `id` | String | Auto-generated (document ID) | Yes |
| `name` | String | Supplier name | Yes |
| `phone` | String | Phone number | No |
| `products` | Array\<String\> | List of product IDs supplied | No |
| `balance` | Number | Outstanding balance | Yes |

### `attendance` (future)
| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `employeeId` | String | Reference to users collection | Yes |
| `date` | Timestamp | Attendance date | Yes |
| `checkIn` | Timestamp | Check-in time | No |
| `checkOut` | Timestamp | Check-out time | No |
| `status` | String | `present`, `absent`, `late`, `leave` | Yes |

## Hybrid Product/Variant Model

Products and Variants are split into two collections:

- **Product** = catalog/master record (name, description, category, images, barcode). No stock or pricing.
- **Variant** = SKU-level record (color, size, quantity, costPrice, salePrice, minStock, barcode). Each variant belongs to one Product via `productId`.

This allows:
- A single product (e.g., "T-Shirt") to have multiple variants (Red/S, Red/M, Blue/L, etc.)
- Each variant to have its own stock, price, and barcode
- POS to decrement stock per-variant via Firestore transactions

## Payment Method

All sales record a `paymentMethod` field (String). Allowed values:
- `cash` — Cash payment
- `card` — Card payment
- `wallet` — Digital wallet
- `credit` — Store credit

No online payment gateway integration. The field is for reporting and cashier reference only.
