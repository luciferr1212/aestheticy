/// Pure Dart text normalization utility for search and index queries.
///
/// Strips Arabic diacritics (harakat/tashkeel), unifies Arabic letter variants
/// (Alef, Taa Marbuta, Alef Maqsura), strips common Latin accents, and lowers
/// case to enable tolerant search across multilingual music libraries.
library;

/// Text normalization helper for indexing and search query pre-processing.
abstract final class TextNormalizer {
  static final RegExp _arabicTashkeel = RegExp(
    r'[\u064B-\u065F\u0670\u0640]',
  );

  static final RegExp _arabicAlefVariants = RegExp(r'[آأإٱ]');

  static final Map<RegExp, String> _latinAccentReplacements = {
    RegExp(r'[àáâãäåā]'): 'a',
    RegExp(r'[èéêëē]'): 'e',
    RegExp(r'[ìíîïī]'): 'i',
    RegExp(r'[òóôõöøō]'): 'o',
    RegExp(r'[ùúûüū]'): 'u',
    RegExp(r'[ýÿ]'): 'y',
    RegExp(r'[çćč]'): 'c',
    RegExp(r'[ñń]'): 'n',
    RegExp(r'[š]'): 's',
    RegExp(r'[ž]'): 'z',
    RegExp(r'ß'): 'ss',
    RegExp(r'æ'): 'ae',
    RegExp(r'œ'): 'oe',
  };

  /// Normalizes [input] for search indexing and queries.
  ///
  /// Converts to lowercase, strips Arabic diacritics and unifies Arabic letter
  /// variants, replaces common Latin accented characters with ASCII equivalents,
  /// and condenses whitespace.
  static String normalize(String? input) {
    if (input == null || input.isEmpty) return '';

    var result = input.toLowerCase();

    // 1. Remove Arabic harakat/tashkeel & tatweel.
    result = result.replaceAll(_arabicTashkeel, '');

    // 2. Unify Arabic letter variants.
    result = result
        .replaceAll(_arabicAlefVariants, 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');

    // 3. Normalize Latin accented letters.
    for (final entry in _latinAccentReplacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    // 4. Collapse consecutive spaces.
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
