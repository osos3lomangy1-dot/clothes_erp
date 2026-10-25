# Clothes ERP — Testing Guide

## How to Run the App

```powershell
# Clean build cache
flutter clean

# Run on Chrome (Web)
flutter run -d chrome

# Run on Windows desktop
flutter run -d windows

# Run on Android emulator
flutter emulators --launch <emulator_name>
flutter run
```

## Test 1: Login (Admin vs Cashier)

### Admin Login
1. Launch the app → should show Login screen.
2. Enter admin email and password → click Login.
3. **Expected:** Navigates to Admin Dashboard. Shows "Welcome, Admin!" and "Open POS" button.
4. Click logout (top-right icon) → returns to Login screen.

### Cashier Login
1. Enter cashier email and password → click Login.
2. **Expected:** Navigates to Cashier Dashboard. Shows "Welcome, Cashier!" and "Open POS" button.
3. Click logout → returns to Login screen.

### Invalid Login
1. Enter wrong credentials → click Login.
2. **Expected:** SnackBar shows error message. Stays on Login screen. No crash.

### Auth Persistence
1. Login as admin → close app → reopen.
2. **Expected:** App skips login, goes directly to Admin Dashboard (cached auth state).

## Test 2: POS (Point of Sale)

### Add to Cart
1. Login as cashier → click "Open POS".
2. **Expected:** POS screen opens with search panel (left) and cart panel (right).
3. Type a product code in the search field → matching variants appear.
4. Click "Add to Cart" (cart icon) on a variant.
5. **Expected:** Item appears in cart with quantity 1. Total updates.

### Quantity Adjustments
1. Click "+" on a cart item → quantity increases, total updates.
2. Click "-" → quantity decreases. At quantity 1, clicking "-" removes the item.
3. Click trash icon → item removed from cart.

### Payment Method
1. Use the dropdown to select: Cash, Card, Wallet, or Credit.
2. **Expected:** Selection persists. No errors.

### Checkout
1. Add 2-3 items to cart → select payment method → click "Checkout".
2. **Expected:** Button shows loading spinner. On success: SnackBar "Sale completed successfully!", cart clears.
3. **Verify in Firestore Console:**
   - New document in `sales` collection with correct items, total, paymentMethod, cashierId.
   - Corresponding `product_variants` documents have decremented `quantity`.
   - New entries in `inventory_logs` collection (type: "out", quantity matches sold).

### Empty Cart Checkout
1. Click "Checkout" with empty cart.
2. **Expected:** SnackBar shows "Cart is empty". No Firestore write.

### Clear Cart
1. Add items → click "Clear All" (top-right icon).
2. **Expected:** Cart empties. Total resets to 0.

## Test 3: Security Rules

### Test as Cashier
1. Sign in as cashier.
2. Open browser DevTools → Console.
3. Try to read `users` collection via Firestore SDK (if exposed) or verify UI doesn't show user management.
4. **Expected:** Permission denied for `users` collection.

### Test as Admin
1. Sign in as admin.
2. **Expected:** Can read/write all collections. User management accessible.

### Test Deactivated User
1. In Firestore Console, set a user's `isActive` to `false`.
2. Try to sign in with that user's credentials.
3. **Expected:** Login fails or access denied. All Firestore reads/writes blocked.

### Test Cashier Sales Isolation
1. Sign in as Cashier A → create a sale.
2. Sign in as Cashier B → query sales.
3. **Expected:** Cashier B cannot see Cashier A's sales. Only their own.

## Test 4: Flutter Analyze

```powershell
flutter analyze
```

**Expected:** 0 errors. Only deprecation info warnings (pre-existing, unrelated).

## Test 5: Build

```powershell
# Windows
flutter build windows

# Android APK
flutter build apk --debug

# Web
flutter build web
```

**Expected:** All builds succeed without errors.
