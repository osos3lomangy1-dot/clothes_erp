# Known Issues, Resolved Debt & Future Enhancements

## ✅ Resolved Technical Debt
- ~~Returns, Reports, Customers, Employees still use Firebase~~ — **100% migrated to offline-first Drift SQLite.**
- ~~Barcode/scanner feature removed~~ — **Restored & upgraded:** Global hardware barcode scanner listener in POS (`46c0fb9`) + Barcode label printing for thermal rolls (50×30mm, 38×25mm) and A4 sheets (`f18ef12`).
- ~~Receipt printing missing~~ — **Implemented** with thermal PDF receipts including promotion breakdowns.
- ~~Duplicate product entry risk~~ — **Resolved** with Arabic normalization duplicate prevention & real-time similarity warnings (`a8cf1eb`).
- ~~Manual per-contract installment payment friction~~ — **Resolved** with inline Bulk Customer FIFO Payment + drawer sync (`f767d26`).
- ~~Supplier purchase returns missing~~ — **Implemented** with stock deduction, supplier balance reconciliation, and cash refund sync (`befbd51`).

## Remaining Low-Priority Tech Debt
- `VariantLocalDataSource` `beforeAuditWrite` test hook pattern works reliably but could eventually be unified behind a shared test helper.

## Optional Future Enhancements (Post-v1.0)
- Cloud Multi-Branch Sync Worker consuming `sync_queue`.
- Held/Parked POS Carts (save & resume).
- Automated WhatsApp/SMS reminders for upcoming/overdue installments.
