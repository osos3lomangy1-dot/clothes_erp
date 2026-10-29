class Money {
  final int piasters;

  const Money(this.piasters);

  int get minorUnits => piasters;

  static Money fromString(String value) {
    final negative = value.trim().startsWith('-');
    final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned.isEmpty) return const Money(0);
    final parts = cleaned.split('.');
    int result;
    if (parts.length == 1) {
      result = int.parse(parts[0]) * 100;
    } else {
      final whole = int.parse(parts[0]);
      final frac = parts[1].padRight(2, '0').substring(0, 2);
      result = whole * 100 + int.parse(frac);
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
