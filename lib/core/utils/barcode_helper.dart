/// Utility helper for generating and sanitizing standard Code 128 / laser-compliant barcodes and SKUs.
class BarcodeHelper {
  /// Converts any size, dimension, unit, or string into a clean, Code 128 / laser-compatible SKU token.
  /// Replaces Arabic letters, symbols (like '×'), and spaces with standard uppercase alphanumeric ASCII chars [A-Z0-9_-].
  ///
  /// Examples:
  /// - '2×3 م' -> '2X3M'
  /// - '1.5×2 م' -> '1_5X2M'
  /// - '100 مل' -> '100ML'
  /// - 'مشاية 1×3 م' -> 'RUNNER1X3M'
  /// - '42' -> '42'
  /// - 'XL' -> 'XL'
  static String sanitizeForSku(String input) {
    if (input.trim().isEmpty) return '';
    String s = input.trim();

    // 1. Normalize multiplication and dimension symbols
    s = s.replaceAll('×', 'X')
         .replaceAll('x', 'X')
         .replaceAll('*', 'X')
         .replaceAll('،', '_')
         .replaceAll(' ', '')
         .replaceAll('.', '_')
         .replaceAll(',', '_');

    // 2. Transliterate common sector units and names to English tokens (longer tokens first!)
    s = s.replaceAll('مشاية', 'RUNNER')
         .replaceAll('مللي', 'ML')
         .replaceAll('مل', 'ML')
         .replaceAll('متر', 'M')
         .replaceAll('كيلو', 'KG')
         .replaceAll('كجم', 'KG')
         .replaceAll('جرام', 'G')
         .replaceAll('سم', 'CM')
         .replaceAll('م', 'M');

    // 3. Remove any remaining non-alphanumeric chars (excluding _ and -)
    s = s.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    s = s.toUpperCase();
    return s;
  }

  /// Generates a standardized, clean Code 128 barcode / SKU.
  /// Example: 'SKU-2X3M-1184'
  static String generateSku({
    required String size,
    int index = 1,
    String prefix = 'SKU',
    int? timestampMillis,
  }) {
    final clean = sanitizeForSku(size);
    final effectiveClean = clean.isNotEmpty ? clean : 'V$index';
    final millis = (timestampMillis ?? DateTime.now().millisecondsSinceEpoch).toString();
    final suffix = millis.length >= 3 ? millis.substring(millis.length - 3) : '001';
    return '$prefix-$effectiveClean-$index$suffix';
  }
}
