import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../../core/services/store_presets_engine.dart';
import '../../../../core/theme/app_branding.dart';
import '../../../../core/utils/phone_validator.dart';
import '../../../../features/auth/presentation/cubits/auth_cubit.dart';
import '../../../../features/dashboard/presentation/screens/admin_dashboard_screen.dart';
import '../../../../features/invoices/data/services/receipt_settings_service.dart';
import '../../../../features/products/domain/entities/activity_type.dart';
import '../../../../features/settings/data/services/activity_settings_service.dart';

class FirstLaunchSetupScreen extends StatefulWidget {
  final VoidCallback? onSetupCompleted;

  const FirstLaunchSetupScreen({super.key, this.onSetupCompleted});

  @override
  State<FirstLaunchSetupScreen> createState() => _FirstLaunchSetupScreenState();
}

class _FirstLaunchSetupScreenState extends State<FirstLaunchSetupScreen> {
  int _currentStep = 0;
  bool _isSubmitting = false;
  String? _stepErrorMessage;

  // Step 1: Store details
  final _storeNameController = TextEditingController();
  final _storePhoneController = TextEditingController();
  final _storeAddressController = TextEditingController();
  String _selectedCurrency = 'ج.م';

  // Step 2: Store Preset & Operational Features
  StorePreset _selectedPreset = StorePreset.fashion;
  bool _enableDelivery = true;
  bool _enablePreOrders = false;
  bool _enableInstallments = false;

  void _selectPreset(StorePreset preset) {
    setState(() {
      _selectedPreset = preset;
      _enableDelivery = (preset == StorePreset.hospitality || preset == StorePreset.fashion);
      _enableInstallments = (preset == StorePreset.electronics);
      _enablePreOrders = false;
    });
  }

  // Step 3: Master Admin
  final _adminUsernameController = TextEditingController(text: 'admin');
  final _adminPasswordController = TextEditingController();
  final _adminConfirmPasswordController = TextEditingController();
  final _adminPinController = TextEditingController();
  bool _obscureAdminPassword = true;

  // Step 4: First Cashier
  bool _createCashier = true;
  final _cashierNameController = TextEditingController(text: 'كاشير 1');
  final _cashierPinController = TextEditingController(text: '1234');

  @override
  void dispose() {
    _storeNameController.dispose();
    _storePhoneController.dispose();
    _storeAddressController.dispose();
    _adminUsernameController.dispose();
    _adminPasswordController.dispose();
    _adminConfirmPasswordController.dispose();
    _adminPinController.dispose();
    _cashierNameController.dispose();
    _cashierPinController.dispose();
    super.dispose();
  }

  void _goToNextStep() {
    setState(() => _stepErrorMessage = null);

    // Validate Step 0
    if (_currentStep == 0) {
      if (_storeNameController.text.trim().isEmpty) {
        setState(() => _stepErrorMessage = 'يرجى إدخال اسم المتجر أو المحل للمتابعة.');
        return;
      }
      final phoneErr = PhoneValidator.validate(
        _storePhoneController.text,
        required: false,
      );
      if (phoneErr != null) {
        setState(() => _stepErrorMessage = phoneErr);
        return;
      }
    }

    // Validate Step 2 (Admin Account)
    if (_currentStep == 2) {
      final username = _adminUsernameController.text.trim();
      final password = _adminPasswordController.text;
      final confirm = _adminConfirmPasswordController.text;
      final adminPin = _adminPinController.text.trim();

      if (username.isEmpty) {
        setState(() => _stepErrorMessage = 'اسم مستخدم الآدمن مطلوب.');
        return;
      }
      if (password.length < 4) {
        setState(() => _stepErrorMessage = 'كلمة مرور الآدمن يجب ألا تقل عن 4 محارف.');
        return;
      }
      if (password != confirm) {
        setState(() => _stepErrorMessage = 'كلمة المرور وتأكيدها غير متطابقين.');
        return;
      }
      if (adminPin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(adminPin)) {
        setState(() => _stepErrorMessage = 'رمز PIN للآدمن يجب أن يتكون من 4 أرقام.');
        return;
      }
    }

    // Validate Step 3 (First Cashier)
    if (_currentStep == 3 && _createCashier) {
      final pin = _cashierPinController.text.trim();
      if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
        setState(() => _stepErrorMessage = 'رمز PIN للكاشير يجب أن يتكون من 4 أرقام.');
        return;
      }
    }

    if (_currentStep < 4) {
      setState(() {
        _currentStep++;
        _stepErrorMessage = null;
      });
    }
  }

  void _goToPrevStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _stepErrorMessage = null;
      });
    }
  }

  Future<void> _finishSetup() async {
    setState(() {
      _isSubmitting = true;
      _stepErrorMessage = null;
    });

    try {
      final db = getIt<AppDatabase>();
      final gate = getIt<FeatureGate>();
      final activityService = getIt<ActivitySettingsService>();

      final storeName = _storeNameController.text.trim();
      final storePhone = PhoneValidator.normalize(_storePhoneController.text);
      final storeAddress = _storeAddressController.text.trim();
      final adminUser = _adminUsernameController.text.trim();
      final adminPass = _adminPasswordController.text.trim();
      final adminPin = _adminPinController.text.trim();
      final cashierName = _cashierNameController.text.trim();
      final cashierPin = _cashierPinController.text.trim();

      final now = DateTime.now();

      // 1. Transaction to write all user accounts atomically
      await db.transaction(() async {
        // Admin user
        await db.into(db.users).insert(
          UsersCompanion.insert(
            id: 'admin_user',
            branchId: 'branch-1',
            username: adminUser,
            displayName: 'المدير العام',
            role: 'admin',
            passwordHash: 'hash_$adminPass',
            passwordSalt: 'salt',
            pinHash: drift.Value(adminPin.length == 4 ? adminPin : null),
            isActive: const drift.Value(true),
            createdAt: now,
            updatedAt: now,
          ),
          mode: drift.InsertMode.insertOrReplace,
        );

        // Cashier user
        if (_createCashier) {
          await db.into(db.users).insert(
            UsersCompanion.insert(
              id: 'cashier_1',
              branchId: 'branch-1',
              username: 'cashier',
              displayName: cashierName.isEmpty ? 'كاشير 1' : cashierName,
              role: 'cashier',
              passwordHash: 'hash_${cashierPin.isEmpty ? '1234' : cashierPin}',
              passwordSalt: 'salt',
              pinHash: drift.Value(cashierPin.isEmpty ? '1234' : cashierPin),
              isActive: const drift.Value(true),
              createdAt: now,
              updatedAt: now,
            ),
            mode: drift.InsertMode.insertOrReplace,
          );
        }
      });

      // 2. Apply store preset features and activities
      await StorePresetsEngine.applyPreset(
        preset: _selectedPreset,
        featureGate: gate,
        activityService: activityService,
        userId: 'system',
      );

      // Save modular operational features chosen by merchant in setup wizard
      await gate.setFeatureEnabled(FeatureKeys.delivery, _enableDelivery, userId: 'system');
      await gate.setFeatureEnabled(FeatureKeys.preOrders, _enablePreOrders, userId: 'system');
      await gate.setFeatureEnabled(FeatureKeys.installments, _enableInstallments, userId: 'system');

      // 3. Save Branding
      await AppBranding.save(
        gate,
        appName: storeName,
        primaryColor: AppBrandingConfig.defaults.primaryColor,
        secondaryColor: AppBrandingConfig.defaults.secondaryColor,
        userId: 'system',
      );

      // 4. Save Receipt Settings
      final currentReceipt = ReceiptSettingsService.current;
      final updatedReceipt = currentReceipt.copyWith(
        storeName: storeName,
        storePhone: storePhone.isNotEmpty ? storePhone : currentReceipt.storePhone,
        storeAddress: storeAddress.isNotEmpty ? storeAddress : currentReceipt.storeAddress,
      );
      await ReceiptSettingsService.save(updatedReceipt, gate, userId: 'system');

      // 5. Mark setup completed in app_meta
      await db.into(db.appMeta).insert(
        AppMetaCompanion.insert(
          key: 'setup.completed',
          value: '1',
          updatedAt: now,
        ),
        mode: drift.InsertMode.insertOrReplace,
      );

      // Save currency
      await db.into(db.appMeta).insert(
        AppMetaCompanion.insert(
          key: 'store.currency',
          value: _selectedCurrency,
          updatedAt: now,
        ),
        mode: drift.InsertMode.insertOrReplace,
      );

      // Save branch name
      await db.into(db.appMeta).insert(
        AppMetaCompanion.insert(
          key: 'branch_name',
          value: storeName.isNotEmpty ? 'الفرع الرئيسي - $storeName' : 'الفرع الرئيسي',
          updatedAt: now,
        ),
        mode: drift.InsertMode.insertOrReplace,
      );

      // 6. Automatic login
      if (getIt.isRegistered<AuthCubit>()) {
        await getIt<AuthCubit>().login(adminUser, adminPass);
      }

      if (mounted) {
        if (widget.onSetupCompleted != null) {
          widget.onSetupCompleted!.call();
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _stepErrorMessage = 'حدث خطأ أثناء حفظ الإعدادات: $e';
          _isSubmitting = false;
        });
      }
    }
  }

  List<String> _presetFeatureChips(StorePreset preset) {
    switch (preset) {
      case StorePreset.fashion:
        return const ['مقاسات وألوان', 'باركود', 'مواسم'];
      case StorePreset.electronics:
        return const ['IMEI', 'ضمان', 'تقسيط وصيانة'];
      case StorePreset.grocery:
        return const ['باركود سريع', 'صلاحية', 'موازين'];
      case StorePreset.hospitality:
        return const ['طاولات', 'مطبخ', 'دليفري'];
      case StorePreset.pharmacy:
        return const ['صلاحية', 'نواقص', 'باركود'];
      case StorePreset.homeTextiles:
        return const ['أمتار', 'تقسيط', 'ضمان'];
      case StorePreset.custom:
        return const ['تخصيص كامل', 'مرن'];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Card(
                elevation: 3,
                shadowColor: Colors.black.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      _buildStepProgress(),
                      const SizedBox(height: 28),
                      if (_stepErrorMessage != null) ...[
                        _buildErrorBanner(_stepErrorMessage!),
                        const SizedBox(height: 20),
                      ],
                      _buildCurrentStepBody(),
                      const SizedBox(height: 32),
                      _buildNavigationRow(),
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

  Widget _buildHeader() {
    return Column(
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.rocket_launch_rounded, color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مرحباً بك في نظام بيعة لإدارة المتاجر (Bay3ah ERP)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'معالج التهيئة والإعداد الأول لتجهيز نظام متجرك والبدء فوراً',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(color: Color(0xFFE2E8F0)),
      ],
    );
  }

  Widget _buildStepProgress() {
    final steps = [
      (title: 'بيانات المتجر', icon: Icons.storefront_rounded),
      (title: 'نوع النشاط', icon: Icons.category_rounded),
      (title: 'حساب الآدمن', icon: Icons.admin_panel_settings_rounded),
      (title: 'أول كاشير', icon: Icons.badge_rounded),
      (title: 'مراجعة وتأكيد', icon: Icons.check_circle_outline_rounded),
    ];

    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: i == _currentStep
                        ? AppColors.primary
                        : (i < _currentStep ? Colors.green.shade700 : const Color(0xFFE2E8F0)),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: i < _currentStep
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: i == _currentStep ? Colors.white : const Color(0xFF64748B),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    steps[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == _currentStep ? FontWeight.bold : FontWeight.w500,
                      color: i == _currentStep ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (i < steps.length - 1)
            Container(
              width: 16,
              height: 2,
              color: i < _currentStep ? Colors.green.shade600 : const Color(0xFFE2E8F0),
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
        ],
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepBody() {
    switch (_currentStep) {
      case 0:
        return _buildStep0StoreDetails();
      case 1:
        return _buildStep1PresetSelection();
      case 2:
        return _buildStep2AdminAccount();
      case 3:
        return _buildStep3FirstCashier();
      case 4:
        return _buildStep4Review();
      default:
        return const SizedBox.shrink();
    }
  }

  // ─── Step 0: Store Details ───
  Widget _buildStep0StoreDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الخطوة 1: أدخل بيانات متجرك الأساسية',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'تظهر هذه البيانات على ترويسة فواتير المبيعات وتقارير النظام الرسمية.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 20),
        const Text('اسم المتجر أو البراند التجاري *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('setup_store_name_field'),
          controller: _storeNameController,
          decoration: InputDecoration(
            hintText: 'مثال: متجر الأناقة للأزياء',
            prefixIcon: const Icon(Icons.storefront_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        const Text('رقم هاتف المتجر (للفواتير)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('setup_store_phone_field'),
          controller: _storePhoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'مثال: 01012345678',
            prefixIcon: const Icon(Icons.phone_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        const Text('العنوان أو المدينة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('setup_store_address_field'),
          controller: _storeAddressController,
          decoration: InputDecoration(
            hintText: 'مثال: القاهرة - مصر الجديدة',
            prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        const Text('العملة الرسمية للمتجر *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const Key('setup_store_currency_dropdown'),
          initialValue: _selectedCurrency,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.monetization_on_outlined, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          items: const [
            DropdownMenuItem(value: 'ج.م', child: Text('ج.م — جنيه مصري')),
            DropdownMenuItem(value: 'ر.س', child: Text('ر.س — ريال سعودي')),
            DropdownMenuItem(value: 'د.إ', child: Text('د.إ — درهم إماراتي')),
            DropdownMenuItem(value: 'د.ك', child: Text('د.ك — دينار كويتي')),
            DropdownMenuItem(value: r'$', child: Text(r'$ — دولار أمريكي')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _selectedCurrency = val);
          },
        ),
      ],
    );
  }

  // ─── Step 1: Preset Selection ───
  Widget _buildStep1PresetSelection() {
    final presets = StorePreset.onboardingPresets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الخطوة 2: اختر نوع النشاط التجاري لمتجرك',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'سيقوم النظام تلقائياً بتكييف شاشات إضافة المنتجات ونقطة البيع وسلوك الماسح الضوئي:',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 580;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: presets.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 3 : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: isWide ? 1.32 : 1.1,
              ),
              itemBuilder: (context, index) {
                final preset = presets[index];
                final isSelected = _selectedPreset == preset;
                final chips = _presetFeatureChips(preset);

                return InkWell(
                  key: Key('preset_card_${preset.code}'),
                  onTap: () => _selectPreset(preset),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                        width: isSelected ? 2 : 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                preset.icon,
                                size: 20,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.primary,
                              ),
                            ),
                            const Spacer(),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              preset.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              preset.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: chips
                              .take(3)
                              .map(
                                (label) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary.withValues(alpha: 0.14)
                                        : AppColors.surfaceContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'الخدمات والأنظمة التشغيلية الإضافية (اختياري):',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'حدد المزايا التشغيلية التي يحتاجها متجرك الآن، ويمكنك دائماً تغييرها لاحقاً من الإعدادات:',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              _buildFeatureToggleTile(
                key: const Key('setup_feature_delivery_switch'),
                title: 'توصيل الطلبات والدليفري (Delivery)',
                subtitle: 'إدارة أوردرات الدليفري وتعيين الطيارين ومصاريف الشحن في نقطة البيع',
                icon: Icons.moped_rounded,
                value: _enableDelivery,
                onChanged: (val) => setState(() => _enableDelivery = val),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 16),
              _buildFeatureToggleTile(
                key: const Key('setup_feature_preorders_switch'),
                title: 'حجز البضائع والعربونات (Pre-Orders)',
                subtitle: 'تسجيل طلبات وحجوزات مسبقة ودفع العربون وتتبع وصول الشحنات',
                icon: Icons.bookmark_added_rounded,
                value: _enablePreOrders,
                onChanged: (val) => setState(() => _enablePreOrders = val),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 16),
              _buildFeatureToggleTile(
                key: const Key('setup_feature_installments_switch'),
                title: 'إدارة التقسيط والبيع الآجل (Installments)',
                subtitle: 'جدولة الأقساط الشهرية وإصدار العقود وإيصالات الأمانة ومتابعة التحصيل',
                icon: Icons.calendar_month_rounded,
                value: _enableInstallments,
                onChanged: (val) => setState(() => _enableInstallments = val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Step 2: Master Admin ───
  Widget _buildStep2AdminAccount() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الخطوة 3: إنشاء حساب مالك ومدير النظام (Master Admin)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'هذا الحساب يتمتع بكافة الصلاحيات الإدارية والمالية وإدارة الإعدادات.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 20),
        const Text('اسم مستخدم الآدمن *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('setup_admin_username_field'),
          controller: _adminUsernameController,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'admin',
            prefixIcon: const Icon(Icons.person_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        const Text('كلمة المرور الجديدة * (4 أحرف على الأقل)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('setup_admin_password_field'),
          controller: _adminPasswordController,
          obscureText: _obscureAdminPassword,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'أدخل كلمة مرور قوية',
            prefixIcon: const Icon(Icons.lock_rounded, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureAdminPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _obscureAdminPassword = !_obscureAdminPassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        const Text('تأكيد كلمة المرور *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('setup_admin_confirm_password_field'),
          controller: _adminConfirmPasswordController,
          obscureText: _obscureAdminPassword,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'أعد إدخال كلمة المرور',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        const Text('رمز PIN السريع للآدمن (4 أرقام - اختياري)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('setup_admin_pin_field'),
          controller: _adminPinController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _goToNextStep(),
          decoration: InputDecoration(
            hintText: 'مثال: 0000 (اختياري للدخول السريع)',
            counterText: '',
            prefixIcon: const Icon(Icons.pin_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  // ─── Step 3: First Cashier ───
  Widget _buildStep3FirstCashier() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الخطوة 4: حساب أول كاشير (اختياري)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'يمكنك إنشاء حساب كاشير فوري لبدء البيع السريع برمز PIN، أو تخطي هذه الخطوة.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          key: const Key('setup_create_cashier_checkbox'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'إنشاء حساب كاشير فوري لبدء عمليات البيع',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            'يتيح للكاشير الدخول السريع برمز PIN دون الوصول للبيانات المحاسبية الحساسة.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          value: _createCashier,
          activeThumbColor: AppColors.primary,
          onChanged: (val) => setState(() => _createCashier = val),
        ),
        if (_createCashier) ...[
          const SizedBox(height: 14),
          const Text('اسم الكاشير', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            key: const Key('setup_cashier_name_field'),
            controller: _cashierNameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'كاشير 1',
              prefixIcon: const Icon(Icons.badge_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          const Text('رمز PIN السريع للدخول (4 أرقام)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            key: const Key('setup_cashier_pin_field'),
            controller: _cashierPinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _goToNextStep(),
            decoration: InputDecoration(
              hintText: '1234',
              counterText: '',
              prefixIcon: const Icon(Icons.pin_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Step 4: Review and Confirm ───
  Widget _buildStep4Review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الخطوة 5: مراجعة وتأكيد إعداد النظام',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        const SizedBox(height: 4),
        const Text(
          'تحقق من تفاصيل متجرك قبل الاعتماد وبدء الاستخدام الفعلي للنظام:',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              _buildReviewRow(
                icon: Icons.storefront_rounded,
                label: 'اسم المتجر:',
                value: _storeNameController.text.trim(),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 18),
              _buildReviewRow(
                icon: _selectedPreset.icon,
                label: 'نوع النشاط التجاري:',
                value: _selectedPreset.title,
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 18),
              _buildReviewRow(
                icon: Icons.tune_rounded,
                label: 'الخدمات التشغيلية:',
                value: [
                  if (_enableDelivery) 'الدليفري',
                  if (_enablePreOrders) 'الحجز المسبق',
                  if (_enableInstallments) 'التقسيط',
                ].isEmpty
                    ? 'المبيعات الفورية الأساسية'
                    : [
                        if (_enableDelivery) 'الدليفري',
                        if (_enablePreOrders) 'الحجز المسبق',
                        if (_enableInstallments) 'التقسيط',
                      ].join(' • '),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 18),
              _buildReviewRow(
                icon: Icons.admin_panel_settings_rounded,
                label: 'حساب الآدمن الرئيسي:',
                value: _adminUsernameController.text.trim(),
              ),
              if (_createCashier) ...[
                const Divider(color: Color(0xFFE2E8F0), height: 18),
                _buildReviewRow(
                  icon: Icons.badge_rounded,
                  label: 'حساب الكاشير:',
                  value: '${_cashierNameController.text.trim()} (PIN: ${_cashierPinController.text.trim()})',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.green, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'أمان أوفلاين: كافة بياناتك وإعداداتك تُحفظ محلياً على جهازك بنسبة 100% دون الحاجة للاتصال بالإنترنت.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF166534), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureToggleTile({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: value
                ? AppColors.primary.withValues(alpha: 0.1)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: value ? AppColors.primary : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          key: key,
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildNavigationRow() {
    return Row(
      children: [
        if (_currentStep > 0)
          OutlinedButton.icon(
            key: const Key('setup_prev_step_button'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _isSubmitting ? null : _goToPrevStep,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text('السابق', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        const Spacer(),
        if (_currentStep < 4)
          ElevatedButton.icon(
            key: const Key('setup_next_step_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _goToNextStep,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('التالي', style: TextStyle(fontWeight: FontWeight.bold)),
          )
        else
          ElevatedButton.icon(
            key: const Key('setup_finish_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _isSubmitting ? null : _finishSetup,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.rocket_launch_rounded, size: 18),
            label: Text(
              _isSubmitting ? 'جاري تهيئة النظام...' : 'حفظ الإعدادات وبدء استخدام النظام',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }
}
