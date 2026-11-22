import 'dart:convert';
import 'package:crypto/crypto.dart';

const String kLicenseSecretKey = 'BAY3AH_OFFLINE_SECRET_KEY_@2026_ENTERPRISE_SECURE';

class DecodedLicensePayload {
  final String machineId;
  final String type; // 'lifetime', 'annual', 'trial_extension'
  final String tier; // 'basic', 'pro', 'enterprise'
  final DateTime? expiryDate;

  const DecodedLicensePayload({
    required this.machineId,
    required this.type,
    required this.tier,
    this.expiryDate,
  });
}

class LicenseCryptoCodec {
  static const String secretKey = kLicenseSecretKey;

  /// Generates a signed cryptographic license key for a specific Machine ID.
  static String generateKey({
    required String machineId,
    required String type,
    required String tier,
    DateTime? expiryDate,
  }) {
    final payloadMap = {
      'mid': machineId.trim().toUpperCase(),
      'type': type.trim().toLowerCase(),
      'tier': tier.trim().toLowerCase(),
      'exp': expiryDate?.toIso8601String() ?? 'none',
      'iat': DateTime.now().toIso8601String(),
    };

    final jsonStr = jsonEncode(payloadMap);
    final payloadB64 = base64Url.encode(utf8.encode(jsonStr)).replaceAll('=', '');

    final hmac = Hmac(sha256, utf8.encode(secretKey));
    final sig = hmac
        .convert(utf8.encode(payloadB64))
        .toString()
        .substring(0, 12)
        .toUpperCase();

    return 'B3H-$payloadB64-$sig';
  }

  /// Cryptographic offline key verification.
  /// Decodes and validates HMAC-SHA256 signature and machine ID match.
  static DecodedLicensePayload? verifyKey(
    String key, {
    String? expectedMachineId,
  }) {
    try {
      final clean = key.trim();
      if (!clean.startsWith('B3H-')) return null;

      final lastDash = clean.lastIndexOf('-');
      if (lastDash <= 4) return null;

      final payloadB64 = clean.substring(4, lastDash);
      final signature = clean.substring(lastDash + 1).toUpperCase();

      // 1. Verify HMAC-SHA256 signature
      final hmac = Hmac(sha256, utf8.encode(secretKey));
      final expectedSig = hmac
          .convert(utf8.encode(payloadB64))
          .toString()
          .substring(0, 12)
          .toUpperCase();

      if (signature != expectedSig) return null;

      // 2. Decode payload
      final normalizedB64 = base64Url.normalize(payloadB64);
      final jsonStr = utf8.decode(base64Url.decode(normalizedB64));
      final Map<String, dynamic> data = jsonDecode(jsonStr);

      final mid = data['mid'] as String?;
      final type = data['type'] as String? ?? 'lifetime';
      final tier = data['tier'] as String? ?? 'enterprise';
      final expStr = data['exp'] as String?;

      if (mid == null || mid.isEmpty) return null;

      if (expectedMachineId != null &&
          expectedMachineId.toUpperCase() != mid.toUpperCase()) {
        return null;
      }

      DateTime? expiryDate;
      if (expStr != null && expStr != 'none') {
        expiryDate = DateTime.tryParse(expStr);
      }

      return DecodedLicensePayload(
        machineId: mid,
        type: type,
        tier: tier,
        expiryDate: expiryDate,
      );
    } catch (_) {
      return null;
    }
  }
}
