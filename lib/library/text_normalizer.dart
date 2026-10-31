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

  static final RegExp _accentRegex = RegExp(
    r'[àáâãäåāèéêëēìíîïīòóôõöøōùúûüūýÿçćčñńšžßæœ]',
  );

  static const Map<String, String> _accentMap = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u',
    'ý': 'y', 'ÿ': 'y',
    'ç': 'c', 'ć': 'c', 'č': 'c',
    'ñ': 'n', 'ń': 'n',
    'š': 's',
    'ž': 'z',
    'ß': 'ss',
    'æ': 'ae',
    'œ': 'oe',
  };

  /// Normalizes [input] for search indexing and queries.
  ///
  /// Converts to lowercase, strips Arabic diacritics and unifies Arabic letter
  /// variants, replaces common Latin accented characters with ASCII equivalents,
  /// and condenses whitespace.
  static String normalize(String? input) {
    if (input == null || input.isEmpty) return '';

    var hasNonAscii = false;
    for (var i = 0; i < input.length; i++) {
      if (input.codeUnitAt(i) > 127) {
        hasNonAscii = true;
        break;
      }
    }

    var result = input.toLowerCase();

    if (hasNonAscii) {
      // 1. Remove Arabic harakat/tashkeel & tatweel.
      result = result.replaceAll(_arabicTashkeel, '');

      // 2. Unify Arabic letter variants.
      result = result
          .replaceAll(_arabicAlefVariants, 'ا')
          .replaceAll('ى', 'ي')
          .replaceAll('ة', 'ه');

      // 3. Normalize Latin accented letters in a single pass.
      result = result.replaceAllMapped(_accentRegex, (m) {
        return _accentMap[m.group(0)!] ?? m.group(0)!;
      });
    }

    // 4. Collapse consecutive spaces.
    return result.contains('  ')
        ? result.replaceAll(RegExp(r'\s+'), ' ').trim()
        : result.trim();
  }
}
