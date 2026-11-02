import 'package:flutter/widgets.dart';

/// Bidirectional text direction resolver.
///
/// Determines [TextDirection] by scanning for the first strong directional character.
/// Non-directional characters (whitespace, digits, punctuation, and symbols) are skipped.
TextDirection textDirectionFor(String text) {
  if (text.isEmpty) {
    return TextDirection.ltr;
  }

  for (final rune in text.runes) {
    // Skip ASCII control codes, spaces, common punctuation, and digits
    if (rune <= 0x0040) {
      continue;
    }
    // Skip ASCII brackets, symbols
    if (rune >= 0x005B && rune <= 0x0060) {
      continue;
    }
    if (rune >= 0x007B && rune <= 0x00BF) {
      continue;
    }
    // Skip general punctuation, superscripts, currency, math symbols
    if (rune >= 0x2000 && rune <= 0x2BFF) {
      continue;
    }
    // Skip Arabic numbers and format characters
    if (rune >= 0x0660 && rune <= 0x066C) {
      continue;
    }

    // Strong RTL ranges: Arabic, Hebrew, Syriac, Thaana, Samaritan, etc.
    if ((rune >= 0x0590 && rune <= 0x05FF) || // Hebrew
        (rune >= 0x0600 && rune <= 0x06FF) || // Arabic
        (rune >= 0x0750 && rune <= 0x077F) || // Arabic Supplement
        (rune >= 0x08A0 && rune <= 0x08FF) || // Arabic Extended-A
        (rune >= 0xFB50 && rune <= 0xFDFF) || // Arabic Presentation Forms-A
        (rune >= 0xFE70 && rune <= 0xFEFF)) {
      // Arabic Presentation Forms-B
      return TextDirection.rtl;
    }

    // Strong Latin / Greek / Cyrillic / CJK / etc.
    return TextDirection.ltr;
  }

  return TextDirection.ltr;
}

/// Static localization dictionaries and lookup engine for Aestheticy.
abstract final class AppStrings {
  /// English (US) dictionary.
  static const Map<String, String> en = {
    'app.name': 'Aestheticy',
    'app.credit': 'by mido',
    'nav.library': 'Library',
    'nav.albums': 'Albums',
    'nav.artists': 'Artists',
    'nav.tracks': 'Tracks',
    'nav.yours': 'Yours',
    'nav.playlists': 'Playlists',
    'nav.favorites': 'Favorites',
    'nav.recent': 'Recent',
    'nav.tools': 'Tools',
    'nav.audioLab': 'Audio Lab',
    'nav.folders': 'Folders',
    'nav.settings': 'Settings',
    'common.soon': 'Soon',
    'common.play': 'Play',
    'common.pause': 'Pause',
    'common.next': 'Next',
    'common.previous': 'Previous',
    'common.shuffle': 'Shuffle',
    'common.repeat': 'Repeat',
    'common.volume': 'Volume',
    'common.queue': 'Queue',
    'common.lyrics': 'Lyrics',
    'common.equalizer': 'Equalizer',
    'common.fullScreen': 'Full Screen',
    'greeting.morning': 'Good morning',
    'greeting.afternoon': 'Good afternoon',
    'greeting.evening': 'Good evening',
    'welcome.title': 'Welcome to Aestheticy',
    'welcome.prompt': 'What should we call you?',
    'welcome.namePlaceholder': 'Your name',
    'welcome.addFolder': 'Add your music folder',
  };

  /// Modern Standard Arabic (العربية الفصحى) dictionary.
  static const Map<String, String> ar = {
    'app.name': 'Aestheticy',
    'app.credit': 'by mido',
    'nav.library': 'المكتبة',
    'nav.albums': 'الألبومات',
    'nav.artists': 'الفنانون',
    'nav.tracks': 'المقاطع',
    'nav.yours': 'مجموعتك',
    'nav.playlists': 'قوائم التشغيل',
    'nav.favorites': 'المفضلة',
    'nav.recent': 'الأخيرة',
    'nav.tools': 'الأدوات',
    'nav.audioLab': 'مختبر الصوت',
    'nav.folders': 'المجلدات',
    'nav.settings': 'الإعدادات',
    'common.soon': 'قريباً',
    'common.play': 'تشغيل',
    'common.pause': 'إيقاف مؤقت',
    'common.next': 'التالي',
    'common.previous': 'السابق',
    'common.shuffle': 'خلط',
    'common.repeat': 'تكرار',
    'common.volume': 'مستوى الصوت',
    'common.queue': 'قائمة الانتظار',
    'common.lyrics': 'كلمات الأغاني',
    'common.equalizer': 'معادل الصوت',
    'common.fullScreen': 'ملء الشاشة',
    'greeting.morning': 'صباح الخير',
    'greeting.afternoon': 'مساء الخير',
    'greeting.evening': 'مساء الخير',
    'welcome.title': 'مرحباً بك في Aestheticy',
    'welcome.prompt': 'ماذا تحب أن نناديك؟',
    'welcome.namePlaceholder': 'اسمك',
    'welcome.addFolder': 'أضف مجلد الموسيقى الخاص بك',
  };

  /// Resolves [key] for [language].
  ///
  /// Fallback hierarchy: requested language -> 'en' -> the key itself.
  /// Never throws.
  static String t(String key, {String language = 'en'}) {
    final Map<String, String> targetMap = switch (language) {
      'ar' => ar,
      _ => en,
    };

    final value = targetMap[key];
    if (value != null && value.isNotEmpty) {
      return value;
    }

    // Fallback to English if not found in requested language
    if (language != 'en') {
      final fallback = en[key];
      if (fallback != null && fallback.isNotEmpty) {
        return fallback;
      }
    }

    // Fallback to key itself
    return key;
  }
}

/// Convenience localization extension on [BuildContext].
extension AppStringsContextExtension on BuildContext {
  /// Translates [key] using the ambient locale from [Localizations] or [Directionality].
  String t(String key) {
    final locale = Localizations.maybeLocaleOf(this);
    final language = locale?.languageCode ??
        (Directionality.maybeOf(this) == TextDirection.rtl ? 'ar' : 'en');
    return AppStrings.t(key, language: language);
  }
}
