class Money {
  final int piasters;

  const Money(this.piasters);

  static Money fromString(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
    final parts = cleaned.split('.');
    if (parts.length == 1) {
      return Money(int.parse(parts[0]) * 100);
    }
    final whole = int.parse(parts[0]);
    final frac = parts[1].padRight(2, '0').substring(0, 2);
    return Money(whole * 100 + int.parse(frac));
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
