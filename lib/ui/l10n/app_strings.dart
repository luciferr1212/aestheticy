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

/// Pure function determining the greeting localization key for a given [DateTime].
///
/// * Morning: 05:00 to 11:59
/// * Afternoon: 12:00 to 17:59
/// * Evening: otherwise (18:00 to 04:59)
String greetingKey(DateTime now) {
  final totalMinutes = now.hour * 60 + now.minute;
  if (totalMinutes >= 5 * 60 && totalMinutes <= 11 * 60 + 59) {
    return 'greeting.morning';
  }
  if (totalMinutes >= 12 * 60 && totalMinutes <= 17 * 60 + 59) {
    return 'greeting.afternoon';
  }
  return 'greeting.evening';
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
    'nav.recent': 'Recently played',
    'nav.tools': 'Tools',
    'nav.audioLab': 'Audio Lab',
    'nav.lastFm': 'Last.fm',
    'nav.folders': 'Folders',
    'nav.settings': 'Settings',
    'common.soon': 'Soon',
    'common.search': 'Search',
    'common.sort': 'Sort',
    'common.cancel': 'Cancel',
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
    'common.back': 'Back',
    'common.close': 'Close',
    'common.searchShortcut': 'Ctrl K',
    'greeting.morning': 'Good morning',
    'greeting.afternoon': 'Good afternoon',
    'greeting.evening': 'Good evening',
    'welcome.title': 'Welcome to Aestheticy',
    'welcome.description':
        'Pick the folders that hold your music. Your files are never changed, we only read them.',
    'welcome.prompt': 'What should we call you?',
    'welcome.nameHelper': 'Used for greetings.',
    'welcome.namePlaceholder': 'Your name',
    'welcome.addFolder': 'Add music folder',
    'scan.title': 'Scanning your music',
    'scan.tracksFound': 'tracks found',
    'scan.albums': 'albums',
    'scan.skipped': 'skipped',
    'sort.recentlyAdded': 'Recently added',
    'sort.title': 'Title',
    'sort.artist': 'Artist',
    'sort.year': 'Year',
    'sort.album': 'Album',
    'sort.duration': 'Duration',
    'view.square': 'Square',
    'view.wide': 'Wide',
    'view.list': 'List',
    'artist.mergedBadge': 'Merged',
    'artist.mergeInto': 'Merge into...',
    'artist.rules': 'Artist rules...',
    'artist.choosePicture': 'Choose picture...',
    'artist.refreshPicture': 'Refresh picture',
    'player.openNowPlaying': 'Open Now Playing',
    'player.noTrack': 'No track playing',
    'tracks.headerNumber': '#',
    'tracks.headerTitle': 'Title',
    'tracks.headerArtist': 'Artist',
    'tracks.headerAlbum': 'Album',
    'tracks.headerDuration': 'Duration',
    'tracks.count': 'tracks',
    'albums.count': 'albums',
    'artists.count': 'artists',
    'album.playAlbum': 'Play',
    'album.shuffleAlbum': 'Shuffle',
    'album.tracksCount': 'tracks',
  };

  /// Modern Standard Arabic (العربية الفصحى) dictionary.
  static const Map<String, String> ar = {
    'app.name': 'Aestheticy',
    'app.credit': 'by mido',
    'nav.library': 'المكتبة',
    'nav.albums': 'الألبومات',
    'nav.artists': 'الفنانون',
    'nav.tracks': 'الأغاني',
    'nav.yours': 'خاص بك',
    'nav.playlists': 'قوائم التشغيل',
    'nav.favorites': 'المفضلة',
    'nav.recent': 'تم تشغيلها مؤخراً',
    'nav.tools': 'الأدوات',
    'nav.audioLab': 'معمل الصوت',
    'nav.lastFm': 'Last.fm',
    'nav.folders': 'المجلدات',
    'nav.settings': 'الإعدادات',
    'common.soon': 'قريباً',
    'common.search': 'بحث',
    'common.sort': 'الترتيب',
    'common.cancel': 'إلغاء',
    'common.play': 'تشغيل',
    'common.pause': 'إيقاف مؤقت',
    'common.next': 'التالي',
    'common.previous': 'السابق',
    'common.shuffle': 'عشوائي',
    'common.repeat': 'تكرار',
    'common.volume': 'مستوى الصوت',
    'common.queue': 'قائمة الانتظار',
    'common.lyrics': 'كلمات الأغاني',
    'common.equalizer': 'معادل الصوت',
    'common.fullScreen': 'ملء الشاشة',
    'common.back': 'رجوع',
    'common.close': 'إغلاق',
    'common.searchShortcut': 'Ctrl K',
    'greeting.morning': 'صباح الخير',
    'greeting.afternoon': 'مساء الخير',
    'greeting.evening': 'مساء الخير',
    'welcome.title': 'مرحباً بك في Aestheticy',
    'welcome.description':
        'اختر المجلدات التي تحتوي على موسيقاك. لن يتم تعديل ملفاتك أبداً، نحن نقرأها فقط.',
    'welcome.prompt': 'ماذا تحب أن نناديك؟',
    'welcome.nameHelper': 'تُستخدم للترحيب بك.',
    'welcome.namePlaceholder': 'اسمك',
    'welcome.addFolder': 'إضافة مجلد موسيقى',
    'scan.title': 'جاري فحص موسيقاك',
    'scan.tracksFound': 'أغنية تم العثور عليها',
    'scan.albums': 'ألبوم',
    'scan.skipped': 'تم تخطيه',
    'sort.recentlyAdded': 'أضيف مؤخراً',
    'sort.title': 'العنوان',
    'sort.artist': 'الفنان',
    'sort.year': 'السنة',
    'sort.album': 'الألبوم',
    'sort.duration': 'المدة',
    'view.square': 'مربع',
    'view.wide': 'عريض',
    'view.list': 'قائمة',
    'artist.mergedBadge': 'مدمج',
    'artist.mergeInto': 'دمج مع...',
    'artist.rules': 'قواعد الفنانين...',
    'artist.choosePicture': 'اختيار صورة...',
    'artist.refreshPicture': 'تحديث الصورة',
    'player.openNowPlaying': 'فتح المشغل',
    'player.noTrack': 'لا يوجد مقطع قيد التشغيل',
    'tracks.headerNumber': '#',
    'tracks.headerTitle': 'العنوان',
    'tracks.headerArtist': 'الفنان',
    'tracks.headerAlbum': 'الألبوم',
    'tracks.headerDuration': 'المدة',
    'tracks.count': 'أغاني',
    'albums.count': 'ألبومات',
    'artists.count': 'فنانين',
    'album.playAlbum': 'تشغيل',
    'album.shuffleAlbum': 'عشوائي',
    'album.tracksCount': 'أغنية',
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
