import 'package:flutter_test/flutter_test.dart';
import 'package:clothes_erp/core/features/feature_gate.dart';

void main() {
  group('FeatureKeys Arabic labels', () {
    test('all labels contain Arabic, no mojibake', () {
      for (final def in FeatureKeys.definitions) {
        expect(def.label, isNotEmpty,
            reason: '${def.key} label is empty');
        expect(def.label.contains('Ø'), isFalse,
            reason: '${def.key} has mojibake: ${def.label}');
        expect(def.label.contains('Ù'), isFalse,
            reason: '${def.key} has mojibake: ${def.label}');
        expect(def.label.contains('Ã'), isFalse,
            reason: '${def.key} has mojibake: ${def.label}');
        expect(def.label.contains('Â'), isFalse,
            reason: '${def.key} has mojibake: ${def.label}');
        final hasArabic =
            def.label.runes.any((r) => r >= 0x0600 && r <= 0x06FF);
        expect(hasArabic, isTrue,
            reason: '${def.key} must contain Arabic: ${def.label}');
      }
    });

    test('no Arabic label contains replacement character U+FFFD', () {
      for (final def in FeatureKeys.definitions) {
        expect(def.label.contains('\uFFFD'), isFalse,
            reason: '${def.key} contains replacement char: ${def.label}');
      }
    });
  });
}

