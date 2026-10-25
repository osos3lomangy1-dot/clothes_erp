# Clothes ERP — Architecture

## Clean Architecture (Feature-First)

Every feature follows a strict 3-layer structure:

```
features/<feature>/
├── data/
│   ├── models/          # Data models (extend entities, handle JSON/Firestore)
│   ├── datasources/     # Remote (Firestore) and local (secure storage) data sources
│   └── repositories/    # Repository implementations (map exceptions → Failures)
├── domain/
│   ├── entities/        # Pure business objects (Equatable, no framework deps)
│   ├── repositories/     # Abstract repository contracts (interfaces)
│   └── usecases/        # Single-responsibility use cases (call repository)
└── presentation/
    ├── cubits/          # State management (Cubit + State)
    ├── screens/         # UI screens
    └── widgets/        # Feature-specific widgets
```

### Layer Rules
- **Domain** depends on nothing (pure Dart, no Flutter/Firebase imports).
- **Data** depends on Domain (implements repository contracts).
- **Presentation** depends on Domain (uses entities and use cases).
- No layer skips another. Presentation never talks directly to Data.

## State Management

- **Bloc/Cubit only.** No Riverpod, no GetX, no Provider.
- Cubits are `@injectable` and registered in GetIt via `injectable`.
- State classes use `Equatable` for efficient rebuilds.
- `BlocListener` for side effects (navigation, SnackBars). `BlocBuilder` for UI rendering.

## Error Handling Pattern

```
Data Source → throws ServerException / CacheException
Repository  → catches ServerException → Left(ServerFailure(e.message))
             → catches generic   → Left(ServerFailure(e.toString()))
Use Case    → returns Either<Failure, T>
Cubit       → result.fold((failure) => emit(Error), (data) => emit(Success))
UI          → BlocListener reacts to Error/Success states
```

All repository methods return `Future<Either<Failure, T>>` (or `Stream` for real-time data).

## Dependency Injection

- `get_it` as the service locator.
- `injectable` for code generation (`@injectable`, `@lazySingleton`, `@module`).
- Firebase instances (`FirebaseAuth`, `FirebaseFirestore`) registered in `RegisterModule`.
- Run `dart run build_runner build` after adding new injectable classes.

## Navigation Strategy

### Why we bypassed `go_router` stream listeners

`go_router`'s `refreshListenable` reacts to stream emissions. On **Windows** and **Web**, Firebase Auth's `authStateChanges()` stream can fire on a non-platform thread, causing silent failures where the redirect never triggers.

### Solution

1. **Removed** `refreshListenable: GoRouterRefreshStream(getIt<AuthCubit>().stream)` from `GoRouter`.
2. `AuthCubit.login()` emits `AuthAuthenticated(user)` directly after a successful login.
3. `LoginScreen`'s `BlocListener` catches `AuthAuthenticated` and calls `Navigator.of(context).pushReplacement(...)` to the appropriate dashboard.
4. `go_router` is still used for route definitions and initial routing, but navigation after login is manual via `Navigator`.

### Route Table

| Path | Screen | Access |
|------|--------|--------|
| `/login` | LoginScreen | All (unauthenticated) |
| `/admin` | AdminDashboardScreen | Admin only |
| `/cashier` | CashierDashboardScreen | Cashier only |
| `/categories` | CategoryListScreen | Admin, Manager |
| `/products` | ProductListScreen | Admin, Manager, Cashier (read) |
| `/variants` | VariantListScreen | Admin, Manager, Cashier (read) |
| `/inventory` | InventoryScreen | Admin, Manager, Cashier (read) |
| `/pos` | PosScreen | Admin, Manager, Cashier |

## Firestore Offline Persistence

Enabled in `FirebaseService.init()` with `persistenceEnabled: true`. No conflict resolution UI. Server is authoritative for stock and money. Offline writes are queued by the SDK and flushed on reconnect.
