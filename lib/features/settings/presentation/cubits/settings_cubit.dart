import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/constants/retail_sector.dart';
import '../../../../core/features/feature_gate.dart';

class SettingsState extends Equatable {
  final Map<String, bool> features;
  final bool cashEnabled;
  final bool cardEnabled;
  final bool installmentPaymentEnabled;
  final bool creditPaymentEnabled;
  final bool cloudSyncEnabled;
  final String sectorMode;
  final bool isLoading;
  final String? error;

  const SettingsState({
    this.features = const {},
    this.cashEnabled = true,
    this.cardEnabled = true,
    this.installmentPaymentEnabled = false,
    this.creditPaymentEnabled = true,
    this.cloudSyncEnabled = false,
    this.sectorMode = RetailSector.apparel,
    this.isLoading = false,
    this.error,
  });

  SettingsState copyWith({
    Map<String, bool>? features,
    bool? cashEnabled,
    bool? cardEnabled,
    bool? installmentPaymentEnabled,
    bool? creditPaymentEnabled,
    bool? cloudSyncEnabled,
    String? sectorMode,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return SettingsState(
      features: features ?? this.features,
      cashEnabled: cashEnabled ?? this.cashEnabled,
      cardEnabled: cardEnabled ?? this.cardEnabled,
      installmentPaymentEnabled:
          installmentPaymentEnabled ?? this.installmentPaymentEnabled,
      creditPaymentEnabled: creditPaymentEnabled ?? this.creditPaymentEnabled,
      cloudSyncEnabled: cloudSyncEnabled ?? this.cloudSyncEnabled,
      sectorMode: sectorMode ?? this.sectorMode,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    features,
    cashEnabled,
    cardEnabled,
    installmentPaymentEnabled,
    creditPaymentEnabled,
    cloudSyncEnabled,
    sectorMode,
    isLoading,
    error,
  ];
}

@injectable
class SettingsCubit extends Cubit<SettingsState> {
  final FeatureGate _featureGate;
  StreamSubscription<Map<String, bool>>? _sub;
  StreamSubscription<String?>? _cashSub;
  StreamSubscription<String?>? _cardSub;
  StreamSubscription<String?>? _installmentSub;
  StreamSubscription<String?>? _creditSub;
  StreamSubscription<String?>? _cloudSyncSub;
  StreamSubscription<String?>? _sectorSub;

  SettingsCubit(this._featureGate)
    : super(const SettingsState(isLoading: true));

  void start() {
    _featureGate.getFeatures().then((features) {
      if (!isClosed) {
        emit(state.copyWith(features: features, isLoading: false, clearError: true));
      }
    });
    _sub?.cancel();
    _sub = _featureGate.watchFeatures().listen((features) {
      emit(
        state.copyWith(features: features, isLoading: false, clearError: true),
      );
    });
    _cashSub?.cancel();
    _cashSub = _featureGate.watchMeta('payment.cash').listen((v) {
      emit(state.copyWith(cashEnabled: v == null ? true : v == '1'));
    });
    _cardSub?.cancel();
    _cardSub = _featureGate.watchMeta('payment.card').listen((v) {
      emit(state.copyWith(cardEnabled: v == null ? true : v == '1'));
    });
    _installmentSub?.cancel();
    _installmentSub = _featureGate.watchMeta('payment.installment').listen((v) {
      emit(state.copyWith(installmentPaymentEnabled: v == '1'));
    });
    _creditSub?.cancel();
    _creditSub = _featureGate.watchMeta('payment.credit').listen((v) {
      emit(state.copyWith(creditPaymentEnabled: v == null ? true : v == '1'));
    });
    _cloudSyncSub?.cancel();
    _cloudSyncSub = _featureGate.watchMeta('sync.cloud_enabled').listen((v) {
      emit(state.copyWith(cloudSyncEnabled: v == '1' || v == 'true'));
    });
    _sectorSub?.cancel();
    _sectorSub = _featureGate.watchMeta(RetailSector.metaKey).listen((v) {
      emit(state.copyWith(sectorMode: v ?? RetailSector.apparel));
    });
  }

  Future<String?> setSectorMode(String mode, String userId) async {
    try {
      await _featureGate.setMeta(
        RetailSector.metaKey,
        mode,
        userId: userId,
      );
      return null;
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      emit(state.copyWith(error: msg));
      return msg;
    }
  }

  Future<String?> setCloudSyncEnabled(bool enabled, String userId) async {
    try {
      await _featureGate.setMeta(
        'sync.cloud_enabled',
        enabled ? '1' : '0',
        userId: userId,
      );
      return null;
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      emit(state.copyWith(error: msg));
      return msg;
    }
  }

  Future<String?> toggleFeature(String key, bool enabled, String userId) async {
    try {
      await _featureGate.setFeatureEnabled(key, enabled, userId: userId);
      return null;
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      emit(state.copyWith(error: msg));
      return msg;
    }
  }

  Future<String?> setPaymentMethod(
    String methodKey,
    bool enabled,
    String userId,
  ) async {
    try {
      final cash = methodKey == 'payment.cash' ? enabled : state.cashEnabled;
      final card = methodKey == 'payment.card' ? enabled : state.cardEnabled;
      final inst = methodKey == 'payment.installment'
          ? enabled
          : state.installmentPaymentEnabled;
      final credit = methodKey == 'payment.credit'
          ? enabled
          : state.creditPaymentEnabled;
      if (!cash && !card && !inst && !credit) {
        return 'يجب تفعيل طريقة دفع واحدة على الأقل';
      }
      await _featureGate.setMeta(
        methodKey,
        enabled ? '1' : '0',
        userId: userId,
      );
      return null;
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      emit(state.copyWith(error: msg));
      return msg;
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _cashSub?.cancel();
    _cardSub?.cancel();
    _installmentSub?.cancel();
    _creditSub?.cancel();
    _cloudSyncSub?.cancel();
    _sectorSub?.cancel();
    return super.close();
  }
}
