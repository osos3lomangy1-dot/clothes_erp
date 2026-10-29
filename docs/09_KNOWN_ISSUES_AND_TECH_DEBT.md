# Known Issues & Tech Debt

## Tech Debt
- Returns, Reports, Customers, Employees still use Firebase; need migration to Drift
- Navigation patched multiple times; needs final review
- Barcode/scanner feature removed; replaced with SKU
- VariantLocalDataSource beforeAuditWrite injection pattern (works but could be cleaner)

## Future Enhancements
- Receipt printing
- Cloud sync (Firebase)
- Held sales / resume
- Multi-branch support
- Role-based price editing (admin only)
EOF