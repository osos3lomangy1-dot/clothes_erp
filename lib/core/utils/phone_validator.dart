import 'package:flutter/services.dart';

import 'money.dart';

/// Unified phone number normalization & validation for Egyptian mobile,
/// landline, and international numbers.
class PhoneValidator {
  const PhoneValidator._();

  static final TextInputFormatter digitsOnlyFormatter =
      FilteringTextInputFormatter.digitsOnly;

  /// Converts Arabic-Indic digits to ASCII and strips whitespace/separators.
  static String normalize(String input) {
    return Money.normalizeDigits(input)
        .replaceAll(RegExp(r'[\s\-()]'), '')
        .trim();
  }

  /// Validates [input] and returns a clear Arabic error message or `null`.
  ///
  /// Rules:
  /// - Rejects letters or invalid symbols.
  /// - Egyptian mobile numbers starting with `01` must be 11 digits starting
  ///   with `010`, `011`, `012`, or `015`.
  /// - Landline or international numbers must be 8 to 15 digits.
  static String? validate(String? input, {bool required = false}) {
    final raw = input?.trim() ?? '';
    if (raw.isEmpty) {
      return required ? 'يرجى إدخال رقم الهاتف' : null;
    }

    final normalized = normalize(raw);
    final digitsOnly =
        normalized.startsWith('+') ? normalized.substring(1) : normalized;

    if (digitsOnly.isEmpty || !RegExp(r'^\d+$').hasMatch(digitsOnly)) {
      return 'رقم الهاتف يجب أن يحتوي على أرقام فقط دون حروف أو رموز';
    }

    if (digitsOnly.startsWith('01')) {
      if (digitsOnly.length != 11) {
        return 'رقم الموبايل المصري يجب أن يتكون من 11 رقماً';
      }
      if (!RegExp(r'^01[0125]\d{8}$').hasMatch(digitsOnly)) {
        return 'رقم الموبايل يجب أن يبدأ بـ 010 أو 011 أو 012 أو 015';
      }
      return null;
    }

    if (digitsOnly.length < 8 || digitsOnly.length > 15) {
      return 'رقم الهاتف يجب أن يتكون من 8 إلى 15 رقماً';
    }

    return null;
  }
}

