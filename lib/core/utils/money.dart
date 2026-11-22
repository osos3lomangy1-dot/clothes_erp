class Money {
  final int piasters;

  const Money(this.piasters);

  int get minorUnits => piasters;

  /// Normalizes Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩) to standard ASCII digits (0-9).
  static String normalizeDigits(String input) {
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    var res = input;
    for (int i = 0; i < 10; i++) {
      res = res.replaceAll(arabic[i], english[i]);
    }
    return res;
  }

  static Money fromString(String value) {
    final normalized = normalizeDigits(value);
    final negative = normalized.trim().startsWith('-');
    final cleaned = normalized.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned.isEmpty) return const Money(0);
    final parts = cleaned.split('.');
    int result;
    if (parts.length == 1) {
      result = (int.tryParse(parts[0]) ?? 0) * 100;
    } else {
      final whole = int.tryParse(parts[0]) ?? 0;
      final frac = parts[1].padRight(2, '0').substring(0, 2);
      result = whole * 100 + (int.tryParse(frac) ?? 0);
    }
    return Money(negative ? -result : result);
  }

  static Money percentDiscount(Money total, int percent) {
    final discount = (total.piasters * percent) ~/ 100;
    return Money(discount);
  }

  static Money fixedDiscount(Money total, Money amount) {
    if (amount.piasters > total.piasters) return Money(total.piasters);
    return amount;
  }

  String toDisplay() {
    final whole = piasters ~/ 100;
    final frac = (piasters % 100).abs().toString().padLeft(2, '0');
    return '$whole.$frac';
  }

  Money operator +(Money other) => Money(piasters + other.piasters);
  Money operator -(Money other) => Money(piasters - other.piasters);
  Money operator *(int factor) => Money(piasters * factor);
  bool operator <(Money other) => piasters < other.piasters;
  bool operator >(Money other) => piasters > other.piasters;
  bool operator <=(Money other) => piasters <= other.piasters;
  bool operator >=(Money other) => piasters >= other.piasters;

  @override
  bool operator ==(Object other) => other is Money && other.piasters == piasters;

  @override
  int get hashCode => piasters.hashCode;
}
