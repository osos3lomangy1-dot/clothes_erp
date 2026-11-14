import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/features/feature_gate.dart';
import '../../../auth/presentation/cubits/auth_cubit.dart';
import '../../../auth/presentation/cubits/auth_state.dart';
import '../../../installments/data/services/manager_pin_service.dart';
import '../cubits/settings_cubit.dart';

class SystemSettingsScreen extends StatelessWidget {
  const SystemSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SettingsCubit>()..start(),
      child: const _SystemSettingsView(),
    );
  }
}

class _SystemSettingsView extends StatelessWidget {
  const _SystemSettingsView();

  bool _isAdmin(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    if (auth is! AuthAuthenticated) return true;
    return auth.user.role != 'cashier';
  }

  String _userId(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    if (auth is AuthAuthenticated) return auth.user.id;
    return 'admin';
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _isAdmin(context);
    if (!isAdmin) {
      return const Scaffold(
        body: Center(child: Text('إعدادات النظام متاحة للمدير فقط')),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'إعدادات النظام',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
      ),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, state) {
          if (state.isLoading && state.features.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final togglable = FeatureKeys.definitions
              .where((d) => !d.coreAlwaysEnabled)
              .toList();
          final installmentsEnabled =
              state.features[FeatureKeys.installments] ?? false;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle('الميزات (Features)'),
              Card(
                child: Column(
                  children: [
                    for (final def in togglable) ...[
                      _featureTile(context, state, def),
                      if (def != togglable.last) const Divider(height: 1),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'الميزات الأساسية (المصادقة، نقطة البيع، المخزون، حركات المخزن، العملاء) مفعّلة دائمًا.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              const SizedBox(height: 20),
              _sectionTitle('طرق الدفع'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('نقدي (Cash)'),
                      value: state.cashEnabled,
                      onChanged: (v) async {
                        final err = await context
                            .read<SettingsCubit>()
                            .setPaymentMethod(
                              'payment.cash',
                              v,
                              _userId(context),
                            );
                        if (err != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('بطاقة (Card)'),
                      value: state.cardEnabled,
                      onChanged: (v) async {
                        final err = await context
                            .read<SettingsCubit>()
                            .setPaymentMethod(
                              'payment.card',
                              v,
                              _userId(context),
                            );
                        if (err != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      },
                    ),
                    if (installmentsEnabled) ...[
                      const Divider(height: 1),
                      SwitchListTile(
                        key: const Key('payment_installment_toggle'),
                        title: const Text('تقسيط (Installment)'),
                        value: state.installmentPaymentEnabled,
                        onChanged: (v) async {
                          final err = await context
                              .read<SettingsCubit>()
                              .setPaymentMethod(
                                'payment.installment',
                                v,
                                _userId(context),
                              );
                          if (err != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(err),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              if (installmentsEnabled) ...[
                const SizedBox(height: 20),
                _sectionTitle('إعدادات التقسيط'),
                const _InstallmentSettingsSection(),
              ],
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'كل تغيير يُسجَّل في سجل التدقيق (audit log).',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.onSurface,
        ),
      ),
    );
  }

  Widget _featureTile(
    BuildContext context,
    SettingsState state,
    FeatureDefinition def,
  ) {
    final enabled = state.features[def.key] ?? def.defaultEnabled;
    String? subtitle;
    if (def.dependencies.isNotEmpty) {
      final deps = def.dependencies
          .map((d) => FeatureKeys.byKey[d]?.label ?? d)
          .join('، ');
      subtitle = 'يعتمد على: $deps';
    }
    return SwitchListTile(
      title: Text(def.label),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: enabled,
      onChanged: (v) async {
        final err = await context.read<SettingsCubit>().toggleFeature(
          def.key,
          v,
          _userId(context),
        );
        if (err != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err), backgroundColor: AppColors.error),
          );
        }
      },
    );
  }
}

class _InstallmentSettingsSection extends StatefulWidget {
  const _InstallmentSettingsSection();

  @override
  State<_InstallmentSettingsSection> createState() =>
      _InstallmentSettingsSectionState();
}

class _InstallmentSettingsSectionState
    extends State<_InstallmentSettingsSection> {
  bool _pinRequired = true;
  bool _pinSet = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPinStatus();
  }

  Future<void> _loadPinStatus() async {
    final pinSvc = getIt<ManagerPinService>();
    final required = await pinSvc.isPinRequired();
    final set = await pinSvc.isPinSet();
    if (mounted) {
      setState(() {
        _pinRequired = required;
        _pinSet = set;
        _loading = false;
      });
    }
  }

  String _userId(BuildContext context) {
    final auth = context.read<AuthCubit>().state;
    if (auth is AuthAuthenticated) return auth.user.id;
    return 'admin';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        key: Key('installment_settings_section'),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final pinSvc = getIt<ManagerPinService>();
    return Card(
      key: const Key('installment_settings_section'),
      child: Column(
        children: [
          SwitchListTile(
            key: const Key('installment_pin_required_toggle'),
            title: const Text('طلب الرقم السري للمدير (Manager PIN)'),
            subtitle: const Text('تأكيد المدير عند إنشاء عقد تقسيط أو إلغائه'),
            value: _pinRequired,
            onChanged: (v) async {
              final uid = _userId(context);
              await pinSvc.setPinRequired(required: v, userId: uid);
              if (mounted) {
                setState(() => _pinRequired = v);
              }
            },
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('الرقم السري للمدير'),
            subtitle: Text(
              _pinSet ? 'الرقم السري مُعيَّن' : 'لم يتم تعيين الرقم السري بعد',
            ),
            trailing: OutlinedButton(
              onPressed: () => _showSetPinDialog(context),
              child: Text(_pinSet ? 'تغيير' : 'تعيين'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSetPinDialog(BuildContext context) async {
    final controller = TextEditingController();
    final uid = _userId(context);
    final pinSvc = getIt<ManagerPinService>();
    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(_pinSet ? 'تغيير الرقم السري' : 'تعيين الرقم السري'),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'الرقم السري الجديد'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final res = await pinSvc.setPin(
                  pin: controller.text,
                  userId: uid,
                );
                res.fold(
                  (f) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(f.message),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  (_) {
                    if (mounted) {
                      setState(() => _pinSet = true);
                    }
                  },
                );
              }
              if (dialogCtx.mounted) {
                Navigator.of(dialogCtx).pop();
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
