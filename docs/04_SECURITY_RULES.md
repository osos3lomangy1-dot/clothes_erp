# Clothes ERP — Security Rules

## Firestore Rules

```firestore
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    // --- Helper functions ---

    function isSignedIn() {
      return request.auth != null;
    }

    function getUserRole() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role;
    }

    function isActive() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isActive == true;
    }

    function isAdmin() {
      return isSignedIn() && isActive() && getUserRole() == 'admin';
    }

    function isManager() {
      return isSignedIn() && isActive() && getUserRole() == 'manager';
    }

    function isCashier() {
      return isSignedIn() && isActive() && getUserRole() == 'cashier';
    }

    function isAdminOrManager() {
      return isAdmin() || isManager();
    }

    // --- Collection rules ---

    // users: Admin full CRUD. Manager read all, write own. Cashier read own only.
    match /users/{userId} {
      allow read: if isAdmin() || isManager() || (isCashier() && request.auth.uid == userId);
      allow create: if isAdmin();
      allow update: if isAdmin() || (isManager() && request.auth.uid == userId);
      allow delete: if isAdmin();
    }

    // categories: Admin + Manager read/write. Cashier read only.
    match /categories/{categoryId} {
      allow read: if isAdminOrManager() || isCashier();
      allow create, update, delete: if isAdminOrManager();
    }

    // products: Admin + Manager read/write. Cashier read only.
    match /products/{productId} {
      allow read: if isAdminOrManager() || isCashier();
      allow create, update, delete: if isAdminOrManager();
    }

    // product_variants: Admin + Manager read/write. Cashier read only.
    match /product_variants/{variantId} {
      allow read: if isAdminOrManager() || isCashier();
      allow create, update, delete: if isAdminOrManager();
    }

    // sales: Admin + Manager read all. Cashier read own + create.
    match /sales/{saleId} {
      allow read: if isAdminOrManager() || (isCashier() && resource.data.cashierId == request.auth.uid);
      allow create: if isAdminOrManager() || isCashier();
      allow update, delete: if isAdminOrManager();
    }

    // inventory_logs: Admin + Manager read/write. Cashier read only.
    match /inventory_logs/{logId} {
      allow read: if isAdminOrManager() || isCashier();
      allow create: if isAdminOrManager();
      allow update, delete: if isAdmin();
    }

    // Deny everything else by default
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

## Roles & Permissions

| Collection | Admin | Manager | Cashier |
|-----------|-------|---------|---------|
| `users` | Full CRUD | Read all, write own | Read own only |
| `categories` | Read/Write | Read/Write | Read only |
| `products` | Read/Write | Read/Write | Read only |
| `product_variants` | Read/Write | Read/Write | Read only |
| `sales` | Read all, Create, Update, Delete | Read all, Create, Update, Delete | Read own, Create |
| `inventory_logs` | Read/Write/Delete | Read/Create | Read only |
| Everything else | Denied | Denied | Denied |

## Key Security Principles

1. **Deny by default** — any collection not explicitly listed is denied.
2. **isActive check** — every role function verifies `isActive == true` before granting access. Deactivated users are locked out immediately.
3. **Role from Firestore** — the user's role is read from the `users` collection, not from custom claims. This ensures the role is always current.
4. **Cashier isolation** — cashiers can only read their own sales (`cashierId == auth.uid`). They cannot see other cashiers' sales.
5. **No client-side trust** — all authorization is enforced server-side by these rules. The Flutter app's UI checks are for UX only.

## Deployment

### Option A: Firebase Console (recommended for quick updates)
1. Open [Firebase Console](https://console.firebase.google.com)
2. Select project `app1-ca2709ac`
3. Left sidebar → **Firestore Database** → **Rules** tab
4. Paste the rules above into the editor
5. Click **Publish**

### Option B: Firebase CLI
```powershell
# Install (if not already)
npm install -g firebase-tools

# Login
firebase login

# Initialize (select Firestore, use existing rules file)
firebase init firestore

# Deploy rules only
firebase deploy --only firestore:rules
```

### Verify After Deploy
- Sign in as admin → can read/write all collections
- Sign in as cashier → can read products/variants, create sales, read own sales only
- Sign in as cashier → cannot read users collection (should get permission denied)
- Deactivate a user (set `isActive: false`) → all access denied immediately
