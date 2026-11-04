import 'package:flutter/widgets.dart';

import '../settings/settings_scope.dart';

/// Converts ASCII digits (0-9) in [text] to Eastern Arabic-Indic digits (٠-٩)
/// strictly when [arabicIndic] is true. Otherwise returns [text] unmodified.
String localizeDigits(String text, {required bool arabicIndic}) {
  if (!arabicIndic || text.isEmpty) return text;

  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0x0030 && rune <= 0x0039) {
      buffer.writeCharCode(0x0660 + (rune - 0x0030));
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Formats [d] as `m:ss` or `h:mm:ss` for durations >= 1 hour.
///
/// Negative durations clamp to `0:00`.
String formatDuration(Duration d) {
  final totalSeconds = d.inSeconds;
  if (totalSeconds <= 0) return '0:00';

  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final mm = minutes.toString().padLeft(2, '0');
    return '$hours:$mm:$ss';
  } else {
    return '$minutes:$ss';
  }
}

/// Formats integer [n] as a plain string representation.
String formatCount(int n) {
  return n.toString();
}

/// Convenience localization extension on [BuildContext] for numeral conversions.
extension LocalizedNumberContext on BuildContext {
  /// Whether Arabic-Indic digits are active for the current context.
  ///
  /// Strictly true ONLY when interface language is 'ar' AND `arabicNumerals` is enabled.
  bool get usesArabicIndicDigits {
    final settings = SettingsScope.maybeOf(this)?.settings;
    if (settings != null) {
      return settings.language == 'ar' && settings.arabicNumerals;
    }
    return false;
  }

  /// Formats [d] as duration localized according to user numeral settings.
  String formatDurationLocalized(Duration d) {
    return localizeDigits(formatDuration(d), arabicIndic: usesArabicIndicDigits);
  }

  /// Formats [n] as count localized according to user numeral settings.
  String formatCountLocalized(int n) {
    return localizeDigits(formatCount(n), arabicIndic: usesArabicIndicDigits);
  }

  /// Converts digits within [text] if Arabic numerals are active.
  String localizeDigitsText(String text) {
    return localizeDigits(text, arabicIndic: usesArabicIndicDigits);
  }
}
