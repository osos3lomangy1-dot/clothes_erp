import 'dart:io';
import 'package:clothes_erp/core/services/license_crypto_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bay3ah Keygen HTML Offline Tool & Codec Parity', () {
    test('tool/bay3ah_keygen.html exists, is offline-safe, and is excluded from pubspec assets', () {
      final htmlFile = File('tool/bay3ah_keygen.html');
      expect(htmlFile.existsSync(), isTrue);

      final html = htmlFile.readAsStringSync();
      expect(html, contains(kLicenseSecretKey));
      expect(html, isNot(contains('crypto.subtle')));
      expect(html, isNot(contains('https://')));
      expect(html, isNot(contains('http://')));
      expect(html, contains('>>> 0'));

      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('bay3ah_keygen.html')));
    });

    test('LicenseCryptoCodec verifies keys and Master Rescue PINs accurately (including >>> 0 unsigned 32-bit parity)', () {
      // License key round-trip for all types & tiers
      final lifetimeKey = LicenseCryptoCodec.generateKey(
        machineId: 'win-test-1234',
        type: 'lifetime',
        tier: 'enterprise',
      );
      final decodedLifetime = LicenseCryptoCodec.verifyKey(
        lifetimeKey,
        expectedMachineId: 'WIN-TEST-1234',
      );
      expect(decodedLifetime, isNotNull);
      expect(decodedLifetime!.machineId, 'WIN-TEST-1234');
      expect(decodedLifetime.type, 'lifetime');
      expect(decodedLifetime.tier, 'enterprise');
      expect(decodedLifetime.expiryDate, isNull);

      final annualExp = DateTime.now().add(const Duration(days: 365));
      final annualKey = LicenseCryptoCodec.generateKey(
        machineId: 'MOB-9988-ABCD',
        type: 'annual',
        tier: 'pro',
        expiryDate: annualExp,
      );
      final decodedAnnual = LicenseCryptoCodec.verifyKey(
        annualKey,
        expectedMachineId: 'MOB-9988-ABCD',
      );
      expect(decodedAnnual, isNotNull);
      expect(decodedAnnual!.type, 'annual');
      expect(decodedAnnual.tier, 'pro');
      expect(decodedAnnual.expiryDate, isNotNull);

      // Master Rescue PIN verification across multiple challenges
      final challenges = [
        'RESCUE-1A2B-3C4D',
        'RESCUE-FFFF-0001',
        LicenseCryptoCodec.generateRescueChallenge('WIN-TEST-1234'),
      ];
      for (final ch in challenges) {
        final pin = LicenseCryptoCodec.computeMasterRescuePin(ch);
        expect(pin.length, 6);
        expect(LicenseCryptoCodec.verifyMasterRescuePin(ch, pin), isTrue);
        expect(LicenseCryptoCodec.verifyMasterRescuePin(ch, '000000'), isFalse);
      }
    });

    test('Cross-checks JS implementation inside tool/bay3ah_keygen.html against Dart LicenseCryptoCodec when Node.js is available', () async {
      // Extract the inline <script> from tool/bay3ah_keygen.html and run via node if installed
      final nodeCheck = await Process.run('node', ['--version']).catchError(
        (_) => ProcessResult(0, 1, '', ''),
      );
      if (nodeCheck.exitCode != 0) {
        // Node.js not installed in this environment; skip live JS process execution
        return;
      }

      final html = File('tool/bay3ah_keygen.html').readAsStringSync();
      final scriptStart = html.indexOf('<script>') + '<script>'.length;
      final scriptEnd = html.lastIndexOf('</script>');
      final jsBody = html.substring(scriptStart, scriptEnd);

      final probeScript = '''
const window = {};
const document = { getElementById: () => ({}), createElement: () => ({}) };
const navigator = {};
$jsBody
const key = window.Bay3ahKeygen.generateLicenseKey("WIN-PARITY-777", "annual", "pro", 365);
const pin1 = window.Bay3ahKeygen.computeMasterRescuePin("RESCUE-1A2B-3C4D");
const pin2 = window.Bay3ahKeygen.computeMasterRescuePin("RESCUE-FFFF-0001");
const dartKey = process.argv[2];
const verifiedDartKey = window.Bay3ahKeygen.verifyLicenseKey(dartKey, "WIN-PARITY-777");
console.log(JSON.stringify({ key, pin1, pin2, verifiedValid: verifiedDartKey.valid }));
''';

      final tmpFile = File('${Directory.systemTemp.path}/bay3ah_keygen_parity_probe.js');
      tmpFile.writeAsStringSync(probeScript);
      addTearDown(() {
        if (tmpFile.existsSync()) tmpFile.deleteSync();
      });

      final dartKey = LicenseCryptoCodec.generateKey(
        machineId: 'WIN-PARITY-777',
        type: 'trial_extension',
        tier: 'basic',
        expiryDate: DateTime.now().add(const Duration(days: 14)),
      );

      final res = await Process.run('node', [tmpFile.path, dartKey]);
      expect(res.exitCode, 0, reason: 'Node stderr: ${res.stderr}');
      final out = res.stdout.toString().trim();
      expect(out, isNotEmpty);

      // Parse JS output & verify against Dart LicenseCryptoCodec
      final jsKeyMatch = RegExp(r'"key":"([^"]+)"').firstMatch(out)!;
      final jsKey = jsKeyMatch.group(1)!;
      final verifiedByDart = LicenseCryptoCodec.verifyKey(
        jsKey,
        expectedMachineId: 'WIN-PARITY-777',
      );
      expect(verifiedByDart, isNotNull);
      expect(verifiedByDart!.type, 'annual');
      expect(verifiedByDart.tier, 'pro');

      final jsPin1 = RegExp(r'"pin1":"(\d{6})"').firstMatch(out)!.group(1)!;
      final jsPin2 = RegExp(r'"pin2":"(\d{6})"').firstMatch(out)!.group(1)!;
      expect(LicenseCryptoCodec.verifyMasterRescuePin('RESCUE-1A2B-3C4D', jsPin1), isTrue);
      expect(LicenseCryptoCodec.verifyMasterRescuePin('RESCUE-FFFF-0001', jsPin2), isTrue);
      expect(out, contains('"verifiedValid":true'));
    });
  });
}

