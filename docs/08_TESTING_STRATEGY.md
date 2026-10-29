# Testing Strategy

## Philosophy
- Schema tests: CHECK constraints, unique indexes, foreign keys
- Atomicity tests: inject failure via beforeAuditWrite hook, assert all tables unchanged
- Negative tests: invalid data rejected, insufficient stock
- Use `await expectLater(..., throwsA(...))` — never `expect(() async => ..., throwsA(...))`

## How to Run
```
flutter test
flutter test --reporter expanded
```

## Adding a New Test
1. Use in-memory DB: `AppDatabase(NativeDatabase.memory())`
2. Set up BranchProvider, TxWriter, DataSource
3. tearDown: clear hook, close db
4. Snapshot before, assert after failure
EOF