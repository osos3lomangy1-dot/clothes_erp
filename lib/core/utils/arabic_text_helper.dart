class ArabicTextHelper {
  /// Cleans and normalizes Arabic text by removing diacritics, unifying
  /// Alef, Yaa, Taa Marbuta variations, and trimming spaces.
  static String normalize(String text) {
    var s = text.trim().toLowerCase();
    // Remove Arabic diacritics / tashkeel
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');
    // Normalize Alef variations (أ, إ, آ, ٱ -> ا)
    s = s.replaceAll(RegExp(r'[أإآٱ]'), 'ا');
    // Normalize Yaa (ى -> ي)
    s = s.replaceAll('ى', 'ي');
    // Normalize Taa Marbuta (ة -> ه)
    s = s.replaceAll('ة', 'ه');
    // Normalize multiple spaces into single space
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  /// Returns true if two strings are identical after Arabic normalization.
  static bool isExactMatch(String a, String b) {
    final normA = normalize(a);
    final normB = normalize(b);
    return normA.isNotEmpty && normA == normB;
  }

  /// Returns true if target is similar to query (substring or word overlap).
  static bool isSimilar(String query, String target) {
    final normQ = normalize(query);
    final normT = normalize(target);
    if (normQ.isEmpty || normT.isEmpty) return false;
    if (normQ == normT) return true;

    // Substring match
    if (normQ.length >= 3 && normT.contains(normQ)) return true;
    if (normT.length >= 3 && normQ.contains(normT)) return true;

    // Word overlap match
    final wordsQ = normQ.split(' ').where((w) => w.length >= 2).toSet();
    final wordsT = normT.split(' ').where((w) => w.length >= 2).toSet();
    if (wordsQ.isNotEmpty && wordsT.isNotEmpty) {
      final intersection = wordsQ.intersection(wordsT);
      if (intersection.length >= 2) return true;
      if (wordsQ.length == 1 && intersection.isNotEmpty && normQ.length >= 3) return true;
    }

    return false;
  }
}

