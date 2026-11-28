import '../l10n/app_strings.dart';

/// Time-of-day buckets for the Home screen greeting.
enum HomeGreetingPeriod {
  /// 05:00 - 11:59
  morning,

  /// 12:00 - 16:59
  afternoon,

  /// 17:00 - 20:59
  evening,

  /// 21:00 - 04:59
  night,
}

/// Resolves the [HomeGreetingPeriod] for a local [DateTime].
HomeGreetingPeriod homeGreetingPeriodFor(DateTime now) {
  final hour = now.hour;
  if (hour >= 5 && hour <= 11) {
    return HomeGreetingPeriod.morning;
  }
  if (hour >= 12 && hour <= 16) {
    return HomeGreetingPeriod.afternoon;
  }
  if (hour >= 17 && hour <= 20) {
    return HomeGreetingPeriod.evening;
  }
  return HomeGreetingPeriod.night;
}

/// Returns the `AppStrings` key for the Home greeting at [now].
String homeGreetingKey(DateTime now, {required bool hasName}) {
  final period = homeGreetingPeriodFor(now);
  return switch (period) {
    HomeGreetingPeriod.morning =>
      hasName ? 'home.greeting.morningNamed' : 'home.greeting.morning',
    HomeGreetingPeriod.afternoon =>
      hasName ? 'home.greeting.afternoonNamed' : 'home.greeting.afternoon',
    HomeGreetingPeriod.evening =>
      hasName ? 'home.greeting.eveningNamed' : 'home.greeting.evening',
    HomeGreetingPeriod.night =>
      hasName ? 'home.greeting.nightNamed' : 'home.greeting.night',
  };
}

/// Formats the localized Home greeting for [now], [userName], and [language].
String formatHomeGreeting(
  DateTime now, {
  required String userName,
  required String language,
}) {
  final trimmed = userName.trim();
  final hasName = trimmed.isNotEmpty;
  final key = homeGreetingKey(now, hasName: hasName);
  return AppStrings.t(
    key,
    language: language,
    args: hasName ? {'name': trimmed} : null,
  );
}
