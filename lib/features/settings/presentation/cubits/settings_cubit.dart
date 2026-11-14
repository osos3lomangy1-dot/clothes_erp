import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/features/feature_gate.dart';

class SettingsState extends Equatable {
  final Map<String, bool> features;
  final bool cashEnabled;
  final bool cardEnabled;
  final bool installmentPaymentEnabled;
  final bool isLoading;
  final String? error;

  const SettingsState({
    this.features = const {},
    this.cashEnabled = true,
    this.cardEnabled = true,
    this.installmentPaymentEnabled = false,
    this.isLoading = false,
    this.error,
  });

  SettingsState copyWith({
    Map<String, bool>? features,
    bool? cashEnabled,
    bool? cardEnabled,
    bool? installmentPaymentEnabled,
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

  SettingsCubit(this._featureGate) : super(const SettingsState(isLoading: true));

  void start() {
    _sub?.cancel();
    _sub = _featureGate.watchFeatures().listen((features) {
      emit(state.copyWith(features: features, isLoading: false, clearError: true));
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

  Future<String?> setPaymentMethod(String methodKey, bool enabled, String userId) async {
    try {
      final cash = methodKey == 'payment.cash' ? enabled : state.cashEnabled;
      final card = methodKey == 'payment.card' ? enabled : state.cardEnabled;
      final inst = methodKey == 'payment.installment'
          ? enabled
          : state.installmentPaymentEnabled;
      if (!cash && !card && !inst) {
        return 'يجب تفعيل طريقة دفع واحدة على الأقل';
      }
      await _featureGate.setMeta(methodKey, enabled ? '1' : '0', userId: userId);
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
    return super.close();
  }
}
