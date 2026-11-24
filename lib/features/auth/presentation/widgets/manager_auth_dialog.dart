import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';

class ManagerAuthHelper {
  static const String superAdminPinMetaKey = 'security.super_admin_pin';

  /// Returns true if at least one active admin user exists in [AppDatabase].
  static Future<bool> hasActiveAdminUser({AppDatabase? db}) async {
    final database =
        db ?? (getIt.isRegistered<AppDatabase>() ? getIt<AppDatabase>() : null);
    if (database == null) return false;
    final admins = await (database.select(database.users)
          ..where((u) =>
              u.role.lower().equals('admin') &
              u.isActive.equals(true) &
              u.deletedAt.isNull()))
        .get();
    return admins.isNotEmpty;
  }

  /// Verifies [passwordOrPin] against active admin/manager accounts in [AppDatabase].
  /// When [requireAdminOnly] is true, only accounts with role `'admin'` are accepted.
  static Future<bool> verifyManagerCredentials(
    String passwordOrPin, {
    AppDatabase? db,
    bool requireAdminOnly = false,
  }) async {
    final clean = passwordOrPin.trim();
    if (clean.isEmpty) return false;

    final database = db ?? (getIt.isRegistered<AppDatabase>() ? getIt<AppDatabase>() : null);
    if (database == null) return false;

    final managers = await (database.select(database.users)
          ..where((u) =>
              (requireAdminOnly
                  ? u.role.lower().equals('admin')
                  : (u.role.lower().equals('admin') | u.role.lower().equals('manager'))) &
              u.isActive.equals(true) &
              u.deletedAt.isNull()))
        .get();

    final expectedHash = 'hash_$clean';
    for (final m in managers) {
      final matchesPassword = m.passwordHash == expectedHash ||
          m.passwordHash == clean ||
          (m.passwordHash == 'admin123' && (clean == 'admin' || clean == 'admin123')) ||
          (m.passwordHash == 'hash_admin123' && (clean == 'admin' || clean == 'admin123'));
      final matchesPin = m.pinHash != null &&
          (m.pinHash == clean || m.pinHash == expectedHash);
      if (matchesPassword || matchesPin) {
        return true;
      }
    }
    return false;
  }

  /// Returns true if a Super Admin / Support PIN has been configured.
  static Future<bool> isSuperAdminPinConfigured(FeatureGate gate) async {
    final raw = await gate.getMeta(superAdminPinMetaKey);
    return raw != null && raw.trim().isNotEmpty;
  }

  /// Verifies [pin] against the configured Super Admin / Support PIN.
  static Future<bool> verifySuperAdminPin(FeatureGate gate, String pin) async {
    final stored = await gate.getMeta(superAdminPinMetaKey);
    if (stored == null || stored.trim().isEmpty) return false;
    return stored.trim() == pin.trim();
  }

  /// If a Super Admin PIN is configured, prompts the user to enter it.
  /// If none is configured, returns `true` immediately.
  static Future<bool> ensureSuperAdminUnlocked(
    BuildContext context, {
    required FeatureGate gate,
    required String actionLabel,
  }) async {
    if (!await isSuperAdminPinConfigured(gate)) return true;
    if (!context.mounted) return false;

    final pinCtrl = TextEditingController();
    String? errorText;
    bool isChecking = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          key: const Key('super_admin_pin_dialog'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Icon(Icons.admin_panel_settings_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'بوابة المزود / الدعم الفني (Super Admin PIN)',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'هذا الإجراء ($actionLabel) محمي برمز المزود / الدعم الفني لمنع التعديل العرضي في إعدادات الباقة أو قطاع النشاط.',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('super_admin_pin_field'),
                  controller: pinCtrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'رمز المزود / الدعم الفني (PIN) *',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isChecking ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              key: const Key('super_admin_pin_confirm_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: isChecking
                  ? null
                  : () async {
                      final pin = pinCtrl.text.trim();
                      if (pin.isEmpty) {
                        setDialogState(() => errorText = 'يرجى إدخال رمز الدعم الفني');
                        return;
                      }
                      setDialogState(() {
                        isChecking = true;
                        errorText = null;
                      });
                      final valid = await verifySuperAdminPin(gate, pin);
                      if (!ctx.mounted) return;
                      if (!valid) {
                        setDialogState(() {
                          isChecking = false;
                          errorText = 'رمز المزود / الدعم الفني غير صحيح';
                        });
                        return;
                      }
                      Navigator.of(ctx).pop(true);
                    },
              child: const Text('فتح القفل'),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  /// Prompts for actual manager/admin password or PIN approval.
  /// Returns `true` if approved, `false` if cancelled.
  static Future<bool> requestManagerApproval(
    BuildContext context, {
    required String title,
    required String message,
    bool requireReason = false,
    bool requireAdminOnly = false,
    void Function(String reason)? onReasonCaptured,
    AppDatabase? db,
  }) async {
    final passCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String? errorText;
    bool isChecking = false;

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            key: const Key('manager_void_dialog'),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                const Icon(Icons.security_rounded, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('manager_void_password_field'),
                    controller: passCtrl,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'كلمة مرور / PIN المدير *',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (requireReason) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('manager_void_reason_field'),
                      controller: reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'سبب الإلغاء *',
                        hintText: 'مثال: خطأ بالطلب، زبون غير رأيه...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isChecking ? null : () => Navigator.of(ctx).pop(false),
                child: const Text('رجوع'),
              ),
              ElevatedButton(
                key: const Key('manager_void_confirm_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: isChecking
                    ? null
                    : () async {
                        final pass = passCtrl.text.trim();
                        final reason = reasonCtrl.text.trim();
                        if (pass.isEmpty) {
                          setDialogState(() => errorText = 'يرجى إدخال كلمة مرور المشرف');
                          return;
                        }
                        if (requireReason && reason.isEmpty) {
                          setDialogState(() => errorText = 'يرجى إدخال سبب الإلغاء');
                          return;
                        }
                        setDialogState(() {
                          isChecking = true;
                          errorText = null;
                        });
                        final isValid = await verifyManagerCredentials(
                          pass,
                          db: db,
                          requireAdminOnly: requireAdminOnly,
                        );
                        if (!ctx.mounted) return;
                        if (!isValid) {
                          setDialogState(() {
                            isChecking = false;
                            errorText = 'كلمة المرور أو رمز PIN غير صحيح';
                          });
                          return;
                        }
                        if (requireReason && onReasonCaptured != null) {
                          onReasonCaptured(reason);
                        }
                        Navigator.of(ctx).pop(true);
                      },
                child: const Text('اعتماد وتنفيذ'),
              ),
            ],
          );
        },
      ),
    );
    return approved == true;
  }
}

