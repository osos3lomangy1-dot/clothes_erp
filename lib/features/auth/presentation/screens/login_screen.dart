import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/services/license_activation_service.dart';
import '../../../../core/services/store_profile_service.dart';
import '../../../../core/theme/app_branding.dart';
import '../cubits/auth_cubit.dart';
import '../cubits/auth_state.dart';
import '../cubits/login_form_cubit.dart';
import '../cubits/login_state.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LoginFormCubit(context.read<AuthCubit>()),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  bool _isPinMode = false;
  List<User>? _activeUsers;
  User? _selectedUser;
  String _pinInput = '';
  bool _isPinLoading = false;
  String? _pinError;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      if (getIt.isRegistered<AppDatabase>()) {
        final db = getIt<AppDatabase>();
        final users = await (db.select(db.users)
              ..where((u) => u.isActive.equals(true))
              ..where((u) => u.deletedAt.isNull()))
            .get();
        if (mounted) {
          setState(() {
            _activeUsers = users;
            if (users.isNotEmpty && _selectedUser == null) {
              _selectedUser = users.first;
            }
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitPinLogin() async {
    if (_selectedUser == null || _pinInput.isEmpty) return;
    setState(() {
      _isPinLoading = true;
      _pinError = null;
    });
    final success = await context.read<AuthCubit>().switchCashierWithPin(
          usernameOrId: _selectedUser!.id,
          pin: _pinInput,
        );
    if (mounted) {
      setState(() {
        _isPinLoading = false;
      });
      if (!success) {
        setState(() {
          _pinError = 'رمز PIN غير صحيح للمستخدم المحدد';
          _pinInput = '';
        });
      }
    }
  }

  Future<void> _showMasterRescueDialog(BuildContext context) async {
    String challenge = 'RESCUE-WAIT-AUTH';
    try {
      if (getIt.isRegistered<LicenseActivationService>()) {
        challenge = await getIt<LicenseActivationService>().getRescueChallenge();
      }
    } catch (e) {
      challenge = 'RESCUE-DEMO-0000';
    }

    if (!context.mounted) return;

    final pinCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    String? errorMsg;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.security_rounded, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'طوارئ الحساب واستعادة كلمة المرور',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'إذا نسيت كلمة مرور الآدمن، يمكنك التواصل مع الدعم الفني وتزويدهم بكود الطوارئ التالي للحصول على رمز الإنقاذ المؤقت (Master Rescue PIN) لإعادة تعيين كلمة المرور أوفلاين.',
                        style: TextStyle(fontSize: 12.5, height: 1.5, color: AppColors.onSurface),
                      ),
                      const SizedBox(height: 14),
                      // Challenge Box
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.vpn_key_rounded, size: 20, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'كود الطوارئ لليوم:',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                  SelectableText(
                                    challenge,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              tooltip: 'نسخ كود الطوارئ',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: challenge));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم نسخ كود الطوارئ إلى الحافظة'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('rescue_pin_field'),
                        controller: pinCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'رمز الإنقاذ (6 أرقام) *',
                          prefixIcon: Icon(Icons.pin_outlined),
                          counterText: '',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('rescue_new_password_field'),
                        controller: newPassCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'كلمة المرور الجديدة للآدمن *',
                          prefixIcon: Icon(Icons.lock_reset_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('rescue_confirm_password_field'),
                        controller: confirmPassCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'تأكيد كلمة المرور الجديدة *',
                          prefixIcon: Icon(Icons.check_circle_outline_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (errorMsg != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          errorMsg!,
                          style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  key: const Key('rescue_submit_button'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final pin = pinCtrl.text.trim();
                          final newPass = newPassCtrl.text.trim();
                          final confirmPass = confirmPassCtrl.text.trim();

                          if (pin.length != 6) {
                            setDialogState(() => errorMsg = 'رمز الإنقاذ يجب أن يتكون من 6 أرقام.');
                            return;
                          }
                          if (newPass.length < 4) {
                            setDialogState(() => errorMsg = 'كلمة المرور يجب ألا تقل عن 4 محارف.');
                            return;
                          }
                          if (newPass != confirmPass) {
                            setDialogState(() => errorMsg = 'كلمتا المرور غير متطابقتين.');
                            return;
                          }

                          setDialogState(() {
                            isSubmitting = true;
                            errorMsg = null;
                          });

                          try {
                            if (getIt.isRegistered<LicenseActivationService>()) {
                              await getIt<LicenseActivationService>().resetAdminPassword(
                                newPassword: newPass,
                                rescuePin: pin,
                              );
                            }
                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تمت استعادة حساب الآدمن وتحديث كلمة المرور بنجاح'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              _emailController.text = 'admin';
                              _passwordController.text = newPass;
                              context.read<LoginFormCubit>().onEmailChanged('admin');
                              context.read<LoginFormCubit>().onPasswordChanged(newPass);
                            }
                          } catch (e) {
                            setDialogState(() {
                              isSubmitting = false;
                              errorMsg = e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('إعادة تعيين كلمة المرور والدخول'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildNumpad() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_buildNumpadBtn('1'), _buildNumpadBtn('2'), _buildNumpadBtn('3')],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_buildNumpadBtn('4'), _buildNumpadBtn('5'), _buildNumpadBtn('6')],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_buildNumpadBtn('7'), _buildNumpadBtn('8'), _buildNumpadBtn('9')],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildActionBtn(
              key: const Key('pin_key_clear'),
              label: 'مسح',
              icon: Icons.clear_all_rounded,
              onTap: () {
                setState(() {
                  _pinInput = '';
                  _pinError = null;
                });
              },
            ),
            _buildNumpadBtn('0'),
            _buildActionBtn(
              key: const Key('pin_key_backspace'),
              label: 'حذف',
              icon: Icons.backspace_outlined,
              onTap: () {
                if (_pinInput.isNotEmpty) {
                  setState(() {
                    _pinInput = _pinInput.substring(0, _pinInput.length - 1);
                    _pinError = null;
                  });
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNumpadBtn(String digit) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        key: Key('pin_key_$digit'),
        borderRadius: BorderRadius.circular(28),
        onTap: () {
          if (_pinInput.length < 6) {
            setState(() {
              _pinInput += digit;
              _pinError = null;
            });
            if (_pinInput.length >= 4) {
              _submitPinLogin();
            }
          }
        },
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Text(
            digit,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionBtn({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.outlineVariant),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: Colors.grey.shade700),
        ),
      ),
    );
  }

  Future<void> _showStoreProfilesDialog(BuildContext context) async {
    final profileService = StoreProfileService.instance;
    await showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) {
          final profiles = profileService.profiles;
          final activeId = profileService.activeProfileId;
          return AlertDialog(
            key: const Key('store_profiles_dialog'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.workspaces_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'إدارة المتاجر والأنشطة المستقلة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'كل متجر أو نشاط يمتلك قاعدة بيانات ونسخ احتياطي وحسابات وإعدادات معزولة تماماً.',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: profiles.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, idx) {
                        final p = profiles[idx];
                        final isActive = p.id == activeId;
                        return InkWell(
                          key: Key('store_profile_item_${p.id}'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: isActive
                              ? null
                              : () async {
                                  Navigator.of(dlgCtx).pop();
                                  if (StoreProfileService
                                          .onSwitchProfileRequested !=
                                      null) {
                                    await StoreProfileService
                                        .onSwitchProfileRequested!(p.id);
                                  } else {
                                    await profileService.setActiveProfile(p.id);
                                    if (mounted) setState(() {});
                                  }
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? AppColors.primary.withValues(alpha: 0.08)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isActive
                                    ? AppColors.primary
                                    : AppColors.outlineVariant,
                                width: isActive ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isActive
                                      ? Icons.check_circle_rounded
                                      : Icons.storefront_rounded,
                                  color: isActive
                                      ? AppColors.primary
                                      : AppColors.secondary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                          color: isActive
                                              ? AppColors.primary
                                              : AppColors.onSurface,
                                        ),
                                      ),
                                      if (p.activityLabel.isNotEmpty)
                                        Text(
                                          p.activityLabel,
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 11,
                                            color: AppColors.onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.secondary,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'نشط',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dlgCtx).pop(),
                child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
              ),
              ElevatedButton.icon(
                key: const Key('add_new_store_profile_btn'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_business_rounded, size: 18),
                label: const Text(
                  'إضافة نشاط / متجر جديد',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () async {
                  Navigator.of(dlgCtx).pop();
                  await _showCreateStoreProfileDialog(context);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCreateStoreProfileDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final activityCtrl = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          key: const Key('create_store_profile_dialog'),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.add_business_rounded, color: AppColors.secondary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'إنشاء متجر / نشاط مستقل جديد',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15.5,
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
              children: [
                TextField(
                  key: const Key('new_store_name_field'),
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'اسم المتجر / النشاط *',
                    hintText: 'مثال: مطعم البركة أو فرع الملابس',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('new_store_activity_field'),
                  controller: activityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'وصف النشاط (اختياري)',
                    hintText: 'مثال: مطاعم وكافيهات / أدوات منزلية',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              key: const Key('confirm_create_store_btn'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setDlgState(() => errorText = 'يرجى إدخال اسم المتجر');
                  return;
                }
                final created = await StoreProfileService.instance.createProfile(
                  name: name,
                  activityLabel: activityCtrl.text.trim(),
                );
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                if (StoreProfileService.onSwitchProfileRequested != null) {
                  await StoreProfileService.onSwitchProfileRequested!(created.id);
                } else {
                  await StoreProfileService.instance.setActiveProfile(created.id);
                  if (mounted) setState(() {});
                }
              },
              child: const Text(
                'إنشاء والبدء الآن',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: MultiBlocListener(
        listeners: [
          BlocListener<AuthCubit, AuthState>(
            listener: (context, state) {
              if (state is AuthError) {
                showDialog(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'تعذر تسجيل الدخول',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    content: Text(
                      state.message,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    actions: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text(
                          'المحاولة مجدداً',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.message,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          BlocListener<LoginFormCubit, LoginFormState>(
            listenWhen: (p, c) =>
                p.errorMessage != c.errorMessage && c.errorMessage != null,
            listener: (context, state) {
              if (state.errorMessage != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      state.errorMessage!,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Active Store Profile Badge & Switcher
                      Container(
                        key: const Key('login_active_profile_badge'),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.store_mall_directory_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'النشاط / المتجر النشط',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    StoreProfileService.instance.activeProfile.name,
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: TextButton(
                                key: const Key('login_switch_profile_btn'),
                                onPressed: () => _showStoreProfilesDialog(context),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.secondary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'تبديل المتجر / إضافة نشاط جديد',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/icons/bay3ah-256.png',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.storefront_rounded,
                                size: 48,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'مرحباً بك في ${AppBranding.current.appName}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'منظومة سحابية ومحلية لإدارة المبيعات والمخزون',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // Segmented Mode Toggle (Password vs PIN) [Task 14.3]
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.outlineVariant),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                key: const Key('login_mode_password_button'),
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setState(() => _isPinMode = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: !_isPinMode ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: !_isPinMode
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.password_rounded,
                                        size: 16,
                                        color: !_isPinMode ? AppColors.primary : Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'تسجيل الدخول بكلمة المرور',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: !_isPinMode ? FontWeight.bold : FontWeight.w500,
                                            color: !_isPinMode ? AppColors.primary : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: InkWell(
                                key: const Key('login_mode_pin_button'),
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  setState(() => _isPinMode = true);
                                  if (_activeUsers == null) _loadUsers();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _isPinMode ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: _isPinMode
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.pin_rounded,
                                        size: 16,
                                        color: _isPinMode ? AppColors.primary : Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'الدخول السريع بالـ PIN',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: _isPinMode ? FontWeight.bold : FontWeight.w500,
                                            color: _isPinMode ? AppColors.primary : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Mode Content
                      if (!_isPinMode) ...[
                        BlocBuilder<LoginFormCubit, LoginFormState>(
                          buildWhen: (p, c) => p.email != c.email,
                          builder: (context, state) {
                            return TextField(
                              controller: _emailController,
                              onChanged: (val) => context
                                  .read<LoginFormCubit>()
                                  .onEmailChanged(val),
                              decoration: InputDecoration(
                                labelText: 'اسم المستخدم أو البريد الإلكتروني',
                                hintText: 'مثال: admin أو كود الموظف',
                                prefixIcon: Icon(
                                  Icons.person_outline_rounded,
                                  color: AppColors.primary,
                                ),
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        BlocBuilder<LoginFormCubit, LoginFormState>(
                          buildWhen: (p, c) => p.password != c.password,
                          builder: (context, state) {
                            return TextField(
                              controller: _passwordController,
                              onChanged: (val) => context
                                  .read<LoginFormCubit>()
                                  .onPasswordChanged(val),
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'كلمة المرور',
                                prefixIcon: Icon(
                                  Icons.lock_outlined,
                                  color: AppColors.primary,
                                ),
                                filled: true,
                                fillColor: AppColors.surfaceContainerLow,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        BlocBuilder<LoginFormCubit, LoginFormState>(
                          builder: (context, state) {
                            return SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: state.isSubmitting
                                    ? null
                                    : () =>
                                          context.read<LoginFormCubit>().submit(),
                                child: state.isSubmitting
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Text(
                                        'تسجيل الدخول',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                      ] else ...[
                        // PIN Mode UI
                        if (_activeUsers != null && _activeUsers!.isNotEmpty) ...[
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'اختر المستخدم:',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: _activeUsers!.map((u) {
                              final isSelected = _selectedUser?.id == u.id;
                              return InkWell(
                                key: Key('pin_user_${u.username}'),
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  setState(() {
                                    _selectedUser = u;
                                    _pinInput = '';
                                    _pinError = null;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary.withValues(alpha: 0.1)
                                        : AppColors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? AppColors.primary : AppColors.outlineVariant,
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        u.role == 'admin'
                                            ? Icons.admin_panel_settings_rounded
                                            : Icons.person_rounded,
                                        size: 16,
                                        color: isSelected ? AppColors.primary : Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        u.displayName.isNotEmpty ? u.displayName : u.username,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected ? AppColors.primary : AppColors.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // PIN Dots Indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (index) {
                            final isFilled = index < _pinInput.length;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isFilled ? AppColors.primary : Colors.transparent,
                                border: Border.all(
                                  color: isFilled ? AppColors.primary : Colors.grey.shade400,
                                  width: 2,
                                ),
                              ),
                            );
                          }),
                        ),
                        if (_pinError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _pinError!,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 16),

                        // Numpad
                        _buildNumpad(),
                        const SizedBox(height: 14),

                        // PIN Submit Button
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton(
                            key: const Key('pin_submit_button'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _isPinLoading ? null : _submitPinLogin,
                            child: _isPinLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'تسجيل الدخول بالـ PIN',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Emergency / Master Rescue Key Button [Task 14.4]
                      TextButton.icon(
                        key: const Key('forgot_password_button'),
                        onPressed: () => _showMasterRescueDialog(context),
                        icon: Icon(
                          Icons.health_and_safety_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          'طوارئ الحساب / استعادة كلمة المرور',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),

                      if (kDebugMode && !_isPinMode) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.vpn_key_outlined,
                                    size: 15,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      'الحسابات الافتراضية للنظام (انقر للتعبئة السريعة):',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                          horizontal: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () {
                                        _emailController.text = 'admin';
                                        _passwordController.text = 'admin123';
                                        final cubit = context
                                            .read<LoginFormCubit>();
                                        cubit.onEmailChanged('admin');
                                        cubit.onPasswordChanged('admin123');
                                        cubit.submit();
                                      },
                                      icon: Icon(
                                        Icons.admin_panel_settings_rounded,
                                        size: 15,
                                        color: AppColors.primary,
                                      ),
                                      label: const Text(
                                        'المدير: admin',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                          horizontal: 6,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () {
                                        _emailController.text = 'cashier';
                                        _passwordController.text = '123456';
                                        final cubit = context
                                            .read<LoginFormCubit>();
                                        cubit.onEmailChanged('cashier');
                                        cubit.onPasswordChanged('123456');
                                        cubit.submit();
                                      },
                                      icon: const Icon(
                                        Icons.point_of_sale_rounded,
                                        size: 15,
                                        color: Colors.green,
                                      ),
                                      label: const Text(
                                        'كاشير: cashier',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        '© 2026 جميع الحقوق محفوظة - ${AppBranding.current.appName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
